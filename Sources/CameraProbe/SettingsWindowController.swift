import AppKit

// MARK: - Preferences / Settings Window
//
// Lets the user edit everything that used to require hand-editing
// config.json: relay enabled/host/port, Home Assistant enabled/host/port,
// the ignoredApplications list, and (when running as a real .app bundle)
// Start at Login. "Save" writes through ConfigStore, which persists to
// disk and updates the live config immediately - no restart required.
//
// Laid out with plain frames (matching SplashWindowController's style in
// this codebase) rather than Auto Layout, to keep this self-contained and
// easy to follow.

final class SettingsWindowController: NSWindowController {
    private var relayEnabledCheckbox: NSButton!
    private var relayHostField: NSTextField!
    private var relayPortField: NSTextField!

    private var haEnabledCheckbox: NSButton!
    private var haHostField: NSTextField!
    private var haPortField: NSTextField!

    private var ignoredAppsTextView: NSTextView!
    private var startAtLoginCheckbox: NSButton!
    private var statusLabel: NSTextField!

    convenience init() {
        let width: CGFloat = 460
        let height: CGFloat = 520
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "CameraProbe Preferences"
        window.center()
        window.isReleasedWhenClosed = false

        self.init(window: window)
        buildContent(in: window, size: NSSize(width: width, height: height))
        populateFromCurrentConfig()
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    // MARK: Layout

    private func buildContent(in window: NSWindow, size: NSSize) {
        let contentView = NSView(frame: NSRect(origin: .zero, size: size))
        window.contentView = contentView

        var y = size.height - 40

        y = addSectionHeader("Relay", to: contentView, y: y)
        relayEnabledCheckbox = addCheckbox("Enable relay", to: contentView, y: y)
        y -= 32
        (relayHostField, y) = addLabeledField("Host", to: contentView, y: y)
        (relayPortField, y) = addLabeledField("Port", to: contentView, y: y, numeric: true)

        y -= 12
        y = addSectionHeader("Home Assistant", to: contentView, y: y)
        haEnabledCheckbox = addCheckbox("Enable Home Assistant", to: contentView, y: y)
        y -= 32
        (haHostField, y) = addLabeledField("Host", to: contentView, y: y)
        (haPortField, y) = addLabeledField("Port", to: contentView, y: y, numeric: true)

        y -= 12
        y = addSectionHeader("Ignored Applications (one per line)", to: contentView, y: y)

        let scrollHeight: CGFloat = 100
        y -= scrollHeight
        let scrollView = NSScrollView(frame: NSRect(x: 20, y: y, width: size.width - 40, height: scrollHeight))
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        let textView = NSTextView(frame: scrollView.bounds)
        textView.isEditable = true
        textView.isRichText = false
        textView.font = .systemFont(ofSize: 12)
        textView.autoresizingMask = [.width]
        scrollView.documentView = textView
        contentView.addSubview(scrollView)
        ignoredAppsTextView = textView

        y -= 16
        if LoginItem.isSupported {
            startAtLoginCheckbox = addCheckbox("Start CameraProbe at login", to: contentView, y: y)
        } else {
            let note = NSTextField(labelWithString: "Start at Login is only available when running the installed app.")
            note.frame = NSRect(x: 20, y: y, width: size.width - 40, height: 18)
            note.font = .systemFont(ofSize: 10)
            note.textColor = .secondaryLabelColor
            contentView.addSubview(note)
        }

        y -= 28
        statusLabel = NSTextField(labelWithString: "")
        statusLabel.frame = NSRect(x: 20, y: y, width: size.width - 40, height: 18)
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .systemRed
        contentView.addSubview(statusLabel)

        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancelTapped))
        cancelButton.bezelStyle = .rounded
        cancelButton.frame = NSRect(x: size.width - 220, y: 16, width: 90, height: 28)
        contentView.addSubview(cancelButton)

        let saveButton = NSButton(title: "Save", target: self, action: #selector(saveTapped))
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"
        saveButton.frame = NSRect(x: size.width - 120, y: 16, width: 90, height: 28)
        contentView.addSubview(saveButton)
    }

    private func addSectionHeader(_ title: String, to view: NSView, y: CGFloat) -> CGFloat {
        let label = NSTextField(labelWithString: title)
        label.font = .boldSystemFont(ofSize: 13)
        label.frame = NSRect(x: 20, y: y, width: view.frame.width - 40, height: 20)
        view.addSubview(label)
        return y - 26
    }

    private func addCheckbox(_ title: String, to view: NSView, y: CGFloat) -> NSButton {
        let checkbox = NSButton(checkboxWithTitle: title, target: nil, action: nil)
        checkbox.frame = NSRect(x: 20, y: y, width: view.frame.width - 40, height: 20)
        view.addSubview(checkbox)
        return checkbox
    }

    /// Returns the created field plus the y-coordinate to continue layout from.
    private func addLabeledField(_ title: String, to view: NSView, y: CGFloat, numeric: Bool = false) -> (NSTextField, CGFloat) {
        let label = NSTextField(labelWithString: title)
        label.frame = NSRect(x: 20, y: y, width: 60, height: 22)
        label.alignment = .right
        view.addSubview(label)

        let field = NSTextField(frame: NSRect(x: 90, y: y, width: view.frame.width - 110, height: 22))
        if numeric {
            field.formatter = numericFormatter
        }
        view.addSubview(field)

        return (field, y - 30)
    }

    private let numericFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.allowsFloats = false
        formatter.minimum = 1
        formatter.maximum = 65535
        return formatter
    }()

    // MARK: Data

    private func populateFromCurrentConfig() {
        let config = ConfigStore.shared.config

        relayEnabledCheckbox.state = config.relay.enabled ? .on : .off
        relayHostField.stringValue = config.relay.host
        relayPortField.stringValue = String(config.relay.port)

        haEnabledCheckbox.state = config.homeAssistant.enabled ? .on : .off
        haHostField.stringValue = config.homeAssistant.host
        haPortField.stringValue = String(config.homeAssistant.port)

        ignoredAppsTextView.string = config.ignoredApplications.joined(separator: "\n")

        if LoginItem.isSupported {
            startAtLoginCheckbox.state = LoginItem.isEnabled ? .on : .off
        }
    }

    @objc private func cancelTapped() {
        window?.close()
    }

    @objc private func saveTapped() {
        guard let relayPort = Int(relayPortField.stringValue), (1...65535).contains(relayPort) else {
            statusLabel.stringValue = "Relay port must be a number between 1 and 65535."
            return
        }
        guard let haPort = Int(haPortField.stringValue), (1...65535).contains(haPort) else {
            statusLabel.stringValue = "Home Assistant port must be a number between 1 and 65535."
            return
        }

        let relayHostValue = relayHostField.stringValue.trimmingCharacters(in: .whitespaces)
        let haHostValue = haHostField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !relayHostValue.isEmpty else {
            statusLabel.stringValue = "Relay host can't be empty."
            return
        }
        guard !haHostValue.isEmpty else {
            statusLabel.stringValue = "Home Assistant host can't be empty."
            return
        }

        let ignoredApps = ignoredAppsTextView.string
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        let newConfig = AppConfig(
            relay: RelayConfig(
                enabled: relayEnabledCheckbox.state == .on,
                host: relayHostValue,
                port: relayPort
            ),
            homeAssistant: HomeAssistantConfig(
                enabled: haEnabledCheckbox.state == .on,
                host: haHostValue,
                port: haPort
            ),
            ignoredApplications: ignoredApps
        )

        do {
            try ConfigStore.shared.save(newConfig)
        } catch {
            statusLabel.stringValue = "Failed to save: \(error.localizedDescription)"
            return
        }

        if LoginItem.isSupported {
            LoginItem.setEnabled(startAtLoginCheckbox.state == .on)
        }

        window?.close()
    }
}
