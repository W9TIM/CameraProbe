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
        return _generation
    }

    /// Transitions to inactive if currently active.
    /// Returns true if a transition happened.
    func deactivate() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard _active else { return false }
        _active = false
        return true
    }

    /// True if still active and no newer activation has occurred since `generation`.
    func isCurrentGeneration(_ generation: Int) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return _active && _generation == generation
    }
}

let cameraState = CameraState()

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

    /// Stops the log stream intentionally (e.g. on SIGINT/SIGTERM).
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

                print("Camera application:", application)
                logger.info("CAMERA ON - \(application, privacy: .public)")

                sendRelayCommand("on")
                sendHomeAssistantEvent("camera_on", data: application)
            }
        }

        if line.contains("DidStopRunning") {
            guard cameraState.deactivate() else { return }

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
