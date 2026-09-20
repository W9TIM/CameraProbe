import AppKit

// MARK: - Status Bar Controller
//
// Owns the NSStatusItem: a template "video" icon (auto-adapts to light/
// dark menu bar) with a red-dot indicator overlaid directly on top of it
// as a real subview (not appended text) - a plain, opaque colored view
// sitting above the button's image in the view hierarchy, so it reads as
// a tally light sitting on the camera body: large, fully opaque (so it's
// legible against the glyph and menu bar alike), and unaffected by the
// glyph's own template tinting since it's a separate layer.
//
// The dot reflects CameraProbe's own local detection only - never the
// relay's or Home Assistant's state, and never gated on whether those
// integrations are even enabled. It's on exactly when: the camera is
// currently in use by an application that isn't in the
// ignoredApplications exclude list, AND Inactivate isn't on (see
// CameraActivityIndicator in CameraMonitor.swift for the raw signal;
// pauseState.isPaused is ANDed in here). Updates instantly via
// notification and on the Inactivate toggle itself - no polling, no
// dependency on relay/Home Assistant reachability or their Preferences
// checkboxes.

@MainActor
final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem
    private var inactivateMenuItem: NSMenuItem!
    private var settingsWindowController: SettingsWindowController?
    private var activityDot: NSView?

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        configureButton()
        buildMenu()

        // Set the initial state in case the camera was already active
        // (by a non-excluded app) when the app launched.
        updateActivityIndicator(isActive: cameraActivityIndicator.isVisible && !pauseState.isPaused)

        // Not stored: this observer needs to live as long as the app does,
        // same as StatusBarController itself, so there's nothing to clean
        // up before the process exits.
        NotificationCenter.default.addObserver(
            forName: .cameraProbeVisibleActivityChanged,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            guard let isActive = notification.userInfo?["active"] as? Bool else { return }
            DispatchQueue.main.async {
                guard let self else { return }
                self.updateActivityIndicator(isActive: isActive && !pauseState.isPaused)
            }
        }
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }
        let image = NSImage(systemSymbolName: "video.fill", accessibilityDescription: "CameraProbe")
        image?.isTemplate = true
        button.image = image
        button.imagePosition = .imageOnly
        button.title = ""

        // NSStatusBar.system.thickness (not button.bounds) since bounds
        // isn't guaranteed to have its final layout size yet at this
        // point - thickness is the actual, immediately-valid menu bar
        // height that .squareLength sized this button to.
        let side = NSStatusBar.system.thickness
        let dotDiameter: CGFloat = max(9, side * 0.42)
        let dot = NSView(frame: NSRect(
            x: (side - dotDiameter) / 2,
            y: (side - dotDiameter) / 2,
            width: dotDiameter,
            height: dotDiameter
        ))
        dot.wantsLayer = true
        dot.layer?.backgroundColor = NSColor.systemRed.cgColor
        dot.layer?.cornerRadius = dotDiameter / 2
        dot.layer?.borderWidth = 1
        dot.layer?.borderColor = NSColor.white.withAlphaComponent(0.85).cgColor
        dot.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin, .maxYMargin]
        dot.isHidden = true
        button.addSubview(dot)
        activityDot = dot
    }

    private func updateActivityIndicator(isActive: Bool) {
        activityDot?.isHidden = !isActive
    }

    private func buildMenu() {
        let menu = NSMenu()

        let header = NSMenuItem(title: "CameraProbe \(appVersion)", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        let aboutItem = NSMenuItem(title: "About CameraProbe", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        let preferencesItem = NSMenuItem(title: "Preferences…", action: #selector(showPreferences), keyEquivalent: ",")
        preferencesItem.target = self
        menu.addItem(preferencesItem)

        inactivateMenuItem = NSMenuItem(title: "Inactivate", action: #selector(toggleInactive), keyEquivalent: "")
        inactivateMenuItem.target = self
        menu.addItem(inactivateMenuItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit CameraProbe", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "CameraProbe",
            .applicationVersion: appVersion,
            .credits: NSAttributedString(
                string: "Watches for camera activity and flips a physical relay / notifies Home Assistant."
            )
        ])
    }

    @objc private func showPreferences() {
        // Always built fresh so the fields reflect whatever is currently
        // saved, even if a previous Preferences window was left open with
        // unsaved edits and then dismissed via the titlebar close button.
        let controller = SettingsWindowController()
        settingsWindowController = controller
        controller.show()
    }

    @objc private func toggleInactive() {
        let isPaused = pauseState.toggle()
        inactivateMenuItem.title = isPaused ? "Reactivate" : "Inactivate"

        // Update the dot immediately rather than waiting for the next
        // camera event.
        updateActivityIndicator(isActive: cameraActivityIndicator.isVisible && !isPaused)

        // OSLog's Logger.info(_:) builds its format string at compile time via
        // string interpolation, so it can't take a ternary of two different
        // string literals - each branch needs its own call.
        if isPaused {
            logger.info("Notifications paused from menu bar")
        } else {
            logger.info("Notifications resumed from menu bar")
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
