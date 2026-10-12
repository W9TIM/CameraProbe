import Foundation

// MARK: - Relay Status Poller
//
// Polls the physical relay's own GET /status endpoint (see
// firmware/CameraProbeRelay/CameraProbeRelay.ino's handleStatus) so the
// menu bar red dot reflects the actual remote device state - not just
// "the last command we think we sent" - catching drift if the relay
// missed a command, was toggled by something else, or is unreachable.

// Timer's and URLSession's completion closures are `@Sendable`, so
// capturing `self` in them requires RelayStatusPoller to certify itself
// as Sendable. `timer` is only ever touched from the main run loop
// (start()/stop() are both called from the main-thread status bar setup,
// and the Timer callback itself fires on RunLoop.main); the background
// URLSession completion below only reads immutable captured values and
// calls the (thread-safe) onUpdate closure, never touches `timer` - so
// this is safe by construction, matching CameraState/CameraMonitorService
// elsewhere in this codebase.
final class RelayStatusPoller: @unchecked Sendable {
    private var timer: Timer?
    private let onUpdate: (Bool) -> Void
    private let pollInterval: TimeInterval = 10.0

    init(onUpdate: @escaping (Bool) -> Void) {
        self.onUpdate = onUpdate
    }

    func start() {
        pollNow()
        let timer = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.pollNow()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Triggers an immediate poll outside the regular interval - useful
    /// right after sending an on/off command, so the icon updates
    /// promptly instead of waiting for the next tick.
    func pollNow() {
        // No physical relay to check - fall back to reflecting whether
        // CameraProbe itself currently considers the camera "on" (see
        // CameraActivityIndicator in CameraMonitor.swift), and dark while
        // Inactivate is on. This poll is just a 10s-interval backstop;
        // StatusBarController also updates instantly off the indicator's
        // own change notification and off the Inactivate toggle itself.
        guard enableRelay else {
            onUpdate(cameraActivityIndicator.isVisible && !pauseState.isPaused)
            return
        }

        guard let url = URL(string: "http://\(relayHost):\(relayPort)/status") else {
            onUpdate(false)
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 5

        networkSession.dataTask(with: request) { [weak self] data, _, error in
            guard let self else { return }

            guard error == nil,
                  let data,
                  let text = String(data: data, encoding: .utf8) else {
                self.onUpdate(false)
                return
            }

            let isOn = text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == "ON"
            self.onUpdate(isOn)
        }.resume()
    }
}
