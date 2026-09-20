import Foundation

// MARK: - Camera State
//
// Original version used two unsynchronized `var`s read/written from the
// pipe's readabilityHandler. That handler is not guaranteed to be
// serialized with the main-queue closures reading the same properties,
// so this wraps state behind a lock and adds a "generation" counter.
//
// The generation counter fixes a real race: when the camera turns on,
// we wait 3 seconds before asking macOS which app is frontmost (see
// activeApplicationDetectionDelay). If the camera turns back off during
// that wait, the old code would still fire "camera_on" for a camera
// that is, by then, already off. Capturing the generation lets the
// delayed closure check "is this still the same activation" before
// acting.

final class CameraState: @unchecked Sendable {
    private let lock = NSLock()
    private var _active = false
    private var _initialized = false
    private var _generation = 0
    // Whether the "camera on" notification was actually sent for the
    // current session (false if the detected app is in ignoredApplications,
    // if notifications are paused via the menu bar, or if the camera
    // turned off again before detection finished). Reset on every new
    // activation. Read on deactivate() so the matching "off" notification
    // is suppressed too - otherwise a suppressed "on" would still produce
    // a lone "camera off" with no preceding "on".
    private var _currentSessionNotified = false

    var initialized: Bool {
        lock.lock(); defer { lock.unlock() }
        return _initialized
    }

    func markInitialized() {
        lock.lock(); defer { lock.unlock() }
        _initialized = true
    }

    /// Transitions to active if not already active.
    /// Returns the new generation on success, or nil if already active.
    func activate() -> Int? {
        lock.lock(); defer { lock.unlock() }
        guard !_active else { return nil }
        _active = true
        _generation += 1
        _currentSessionNotified = false
        return _generation
    }

    /// Marks the current session as notified, provided `generation` is
    /// still the active one (i.e. the camera hasn't turned off and back
    /// on again since).
    func markNotified(generation: Int) {
        lock.lock(); defer { lock.unlock() }
        guard _active, _generation == generation else { return }
        _currentSessionNotified = true
    }

    /// Transitions to inactive if currently active.
    /// Returns (didDeactivate, shouldNotify) - shouldNotify is true only
    /// if the matching "on" notification was actually sent.
    func deactivate() -> (didDeactivate: Bool, shouldNotify: Bool) {
        lock.lock(); defer { lock.unlock() }
        guard _active else { return (false, false) }
        _active = false
        let shouldNotify = _currentSessionNotified
        _currentSessionNotified = false
        return (true, shouldNotify)
    }

    /// True if still active and no newer activation has occurred since `generation`.
    func isCurrentGeneration(_ generation: Int) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return _active && _generation == generation
    }
}

let cameraState = CameraState()

// MARK: - Visible Camera Activity
//
// Tracks whether the camera is currently active AND being used by an
// application that isn't in the ignoredApplications exclude list. This
// is the sole source of truth for the menu bar's red dot - deliberately
// local-only, independent of the relay/Home Assistant integrations and
// whether they're even enabled (see StatusBarController). Changes are
// pushed out instantly via the notification below rather than polled.
//
// Deliberately tracks raw activity only, independent of Inactivate/pause
// - StatusBarController is what combines this with pauseState.isPaused
// to decide the dot's actual on-screen state (dark while paused, per the
// same intent as the relay/Home Assistant suppression).
extension Notification.Name {
    static let cameraProbeVisibleActivityChanged = Notification.Name("CameraProbeVisibleActivityChanged")
}

final class CameraActivityIndicator: @unchecked Sendable {
    private let lock = NSLock()
    private var _isVisible = false

    var isVisible: Bool {
        lock.lock(); defer { lock.unlock() }
        return _isVisible
    }

    func setVisible(_ value: Bool) {
        lock.lock()
        let changed = _isVisible != value
        _isVisible = value
        lock.unlock()

        guard changed else { return }
        NotificationCenter.default.post(
            name: .cameraProbeVisibleActivityChanged,
            object: nil,
            userInfo: ["active": value]
        )
    }
}

let cameraActivityIndicator = CameraActivityIndicator()

// MARK: - Camera Monitor Service
//
// Wraps the `log stream` subprocess. On top of the original behavior,
// this adds:
//  - line buffering, so a "DidStartRunning"/"DidStopRunning" marker
//    split across two chunks of availableData isn't silently missed
//  - a termination handler that restarts the subprocess with backoff
//    if it dies unexpectedly (log stream can be killed/restarted by
//    the system independently of this process)
//  - a stop() that's distinguished from an unexpected exit, so
//    shutting down cleanly doesn't trigger a restart
//
// task/pipe/pendingBuffer/restartAttempts/isStopping are touched from
// two different queues: the main queue (start/stop, and the
// asyncAfter restart closure) and whatever background queue Process
// and Pipe invoke their callbacks on (readabilityHandler,
// terminationHandler). Swift 6's strict concurrency checker correctly
// flags that as unsynchronized shared mutable state, so everything
// below goes through a lock, same as CameraState above, and the class
// tells the compiler that's handled manually via `@unchecked Sendable`.

final class CameraMonitorService: @unchecked Sendable {
    private let lock = NSLock()
    private var task: Process?
    private var pipe: Pipe?
    private var pendingBuffer = ""
    private var restartAttempts = 0
    private var isStopping = false

    private let predicate =
        "process == \"cameracaptured\" AND subsystem == \"com.apple.cameracapture\" " +
        "AND (eventMessage CONTAINS \"DidStartRunning\" OR eventMessage CONTAINS \"DidStopRunning\")"

    func start() {
        lock.lock()
        isStopping = false
        lock.unlock()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        process.arguments = [
            "stream",
            "--style", "compact",
            "--predicate", predicate
        ]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe

        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.processAvailableData(data)
        }

        process.terminationHandler = { [weak self] proc in
            self?.handleUnexpectedExit(status: proc.terminationStatus)
        }

        do {
            try process.run()
            logger.info("Camera log stream started (pid \(process.processIdentifier))")
            lock.lock()
            restartAttempts = 0
            task = process
            pipe = outputPipe
            lock.unlock()
        } catch {
            print("Failed to start log stream: \(error)")
            logger.error("Failed to start log stream: \(error.localizedDescription, privacy: .public)")
            scheduleRestart()
        }
    }

    /// Stops the log stream intentionally (e.g. on SIGINT/SIGTERM, or app quit).
    /// Marked so the termination handler doesn't treat this as a crash.
    func stop() {
        lock.lock()
        isStopping = true
        let currentPipe = pipe
        let currentTask = task
        pipe = nil
        task = nil
        lock.unlock()

        currentPipe?.fileHandleForReading.readabilityHandler = nil
        if let currentTask, currentTask.isRunning {
            currentTask.terminate()
        }
    }

    private func handleUnexpectedExit(status: Int32) {
        lock.lock()
        let stopping = isStopping
        let currentPipe = pipe
        lock.unlock()

        guard !stopping else { return }

        logger.error("Camera log stream exited unexpectedly (status \(status)). Restarting...")
        currentPipe?.fileHandleForReading.readabilityHandler = nil
        scheduleRestart()
    }

    private func scheduleRestart() {
        lock.lock()
        restartAttempts += 1
        let attempts = restartAttempts
        lock.unlock()

        let delaySeconds = min(30.0, pow(2.0, Double(attempts)))
        logger.info("Restarting camera log stream in \(delaySeconds, format: .fixed(precision: 0))s")
        DispatchQueue.main.asyncAfter(deadline: .now() + delaySeconds) { [weak self] in
            self?.start()
        }
    }

    private func processAvailableData(_ data: Data) {
        guard let chunk = String(data: data, encoding: .utf8), !chunk.isEmpty else { return }

        lock.lock()
        pendingBuffer += chunk
        let lines = pendingBuffer.components(separatedBy: "\n")
        // The last element is either "" (buffer ended on a newline) or a
        // partial line waiting for more data; keep it for next time.
        pendingBuffer = lines.last ?? ""
        lock.unlock()

        for line in lines.dropLast() {
            handleLogLine(line)
        }
    }

    private func handleLogLine(_ line: String) {
        // Ignore buffered/backlog events emitted when the log stream first attaches.
        if !cameraState.initialized {
            if line.contains("DidStartRunning") || line.contains("DidStopRunning") {
                cameraState.markInitialized()
            }
            return
        }

        if line.contains("DidStartRunning") {
            guard let generation = cameraState.activate() else { return }

            DispatchQueue.main.asyncAfter(deadline: .now() + activeApplicationDetectionDelay) {
                guard cameraState.isCurrentGeneration(generation) else {
                    logger.info("Camera turned off before app detection finished; skipping notification")
                    return
                }

                let application = getActiveApplication()
                let isIgnored = isApplicationIgnored(application)

                // Raw activity signal only - StatusBarController combines
                // this with pauseState.isPaused to decide the dot's actual
                // on-screen state.
                cameraActivityIndicator.setVisible(!isIgnored)

                if pauseState.isPaused {
                    print("Camera application:", application, "(paused, no notification sent)")
                    logger.info("CAMERA ON - \(application, privacy: .public) (paused via menu bar)")
                    return
                }

                if isIgnored {
                    print("Camera application:", application, "(ignored, no notification sent)")
                    logger.info("CAMERA ON - \(application, privacy: .public) (ignored by config)")
                    return
                }

                cameraState.markNotified(generation: generation)

                print("Camera application:", application)
                logger.info("CAMERA ON - \(application, privacy: .public)")

                sendRelayCommand("on")
                sendHomeAssistantEvent("camera_on", data: application)
            }
        }

        if line.contains("DidStopRunning") {
            let (didDeactivate, shouldNotify) = cameraState.deactivate()
            guard didDeactivate else { return }

            cameraActivityIndicator.setVisible(false)

            guard shouldNotify else {
                logger.info("CAMERA OFF (suppressed - matching \"on\" was never notified)")
                return
            }

            logger.info("CAMERA OFF")

            sendRelayCommand("off")
            sendHomeAssistantEvent("camera_off")
        }
    }
}

let cameraMonitor = CameraMonitorService()

func startCameraMonitor() {
    cameraMonitor.start()
}
