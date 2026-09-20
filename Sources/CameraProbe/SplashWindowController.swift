import AppKit

// MARK: - Splash Screen
//
// A brief borderless window shown at launch, dismissed automatically a
// short time later by AppDelegate. Purely cosmetic - carries no state
// the rest of the app depends on.

@MainActor
final class SplashWindowController {
    private var window: NSWindow?

    func showSplash() {
        let size = NSSize(width: 280, height: 160)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.center()

        let contentView = NSView(frame: NSRect(origin: .zero, size: size))
        contentView.wantsLayer = true
        contentView.layer?.cornerRadius = 14
        contentView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        // Shows the app's own bundle icon (the tally-light artwork in
        // Resources/AppIcon.iconset once built via build-app.sh) instead of
        // a generic symbol. Falls back gracefully to whatever AppKit's
        // applicationIconImage resolves to when running unbundled (e.g.
        // `swift run` during development, before Info.plist's icon applies).
        let iconSize: CGFloat = 80
        let icon = NSImageView(frame: NSRect(x: (size.width - iconSize) / 2, y: 74, width: iconSize, height: iconSize))
        icon.image = NSApp.applicationIconImage
        contentView.addSubview(icon)

        let label = NSTextField(labelWithString: "CameraProbe \(appVersion)")
        label.frame = NSRect(x: 0, y: 44, width: size.width, height: 24)
        label.alignment = .center
        label.font = .systemFont(ofSize: 15, weight: .medium)
        contentView.addSubview(label)

        let subtitle = NSTextField(labelWithString: "Starting up...")
        subtitle.frame = NSRect(x: 0, y: 24, width: size.width, height: 18)
        subtitle.alignment = .center
        subtitle.font = .systemFont(ofSize: 11)
        subtitle.textColor = .secondaryLabelColor
        contentView.addSubview(subtitle)

        window.contentView = contentView
        window.alphaValue = 1
        window.makeKeyAndOrderFront(nil)

        self.window = window
    }

    func dismiss() {
        guard let window else { return }
        self.window = nil

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.3
            window.animator().alphaValue = 0
        }, completionHandler: {
            window.close()
        })
    }
}
