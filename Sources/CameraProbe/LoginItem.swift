import Foundation
import ServiceManagement

// MARK: - Login Item
//
// Replaces the old LaunchAgent (~/Library/LaunchAgents/com.tim.cameraprobe.plist,
// installed by install.sh). SMAppService registers the running app bundle
// itself as a login item with launchd - no plist to write, no
// `launchctl bootstrap`, and it shows up in System Settings > General >
// Login Items like any other app.
//
// Only meaningful when running from a proper .app bundle (Info.plist with
// a bundle identifier). Running via `swift run` from Terminal has no
// bundle identifier, so SMAppService calls fail - isSupported guards
// against that so the Preferences window can hide/disable the control
// instead of crashing or showing a confusing error.

enum LoginItem {
    /// SMAppService.mainApp requires a real .app bundle (a bundle
    /// identifier in Info.plist). `swift run`/bare executables don't have
    /// one, so this comes back false while developing from Terminal.
    static var isSupported: Bool {
        Bundle.main.bundleIdentifier != nil
    }

    static var isEnabled: Bool {
        guard isSupported else { return false }
        return SMAppService.mainApp.status == .enabled
    }

    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        guard isSupported else {
            print("Start at Login is unavailable outside of a proper .app bundle")
            return false
        }

        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
            logger.info("Start at Login set to \(enabled, privacy: .public)")
            return true
        } catch {
            print("Failed to update Start at Login: \(error.localizedDescription)")
            logger.error("Failed to update Start at Login: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}
