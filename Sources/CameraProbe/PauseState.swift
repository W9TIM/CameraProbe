import Foundation

// MARK: - Inactivate / Reactivate (menu bar toggle)
//
// Backs the "Inactivate" menu item. When paused, camera detection keeps
// running internally (CameraState/generation tracking stays consistent),
// but relay/Home Assistant notifications are suppressed until the user
// picks "Reactivate" - same idea as ignoredApplications, just a manual
// global switch instead of a per-app config list.

final class PauseState: @unchecked Sendable {
    private let lock = NSLock()
    private var _isPaused = false

    var isPaused: Bool {
        lock.lock(); defer { lock.unlock() }
        return _isPaused
    }

    /// Sets the paused state and returns the new value, so callers (e.g.
    /// the menu item) can update their UI from a single source of truth
    /// instead of tracking their own separate bool.
    @discardableResult
    func setPaused(_ value: Bool) -> Bool {
        lock.lock(); defer { lock.unlock() }
        _isPaused = value
        return _isPaused
    }

    @discardableResult
    func toggle() -> Bool {
        lock.lock(); defer { lock.unlock() }
        _isPaused.toggle()
        return _isPaused
    }
}

let pauseState = PauseState()
