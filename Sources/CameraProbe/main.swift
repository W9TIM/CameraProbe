import AppKit
import Foundation

// MARK: - Command-line flags
//
// Kept even though this is now a GUI app - handy for scripting/
// diagnostics from Terminal without needing the menu bar UI at all.
// --test/--status/--version/--help all exit immediately without
// launching the app.

let cliArguments = Set(CommandLine.arguments.dropFirst())

if cliArguments.contains("--version") {
    print("CameraProbe \(appVersion)")
    exit(0)
}

if cliArguments.contains("--help") {
    printUsage()
    exit(0)
}

if cliArguments.contains("--status") {
    printStatus()
    exit(0)
}

if cliArguments.contains("--test") {
    exit(runSelfTest() ? 0 : 1)
}

// MARK: - Single instance
//
// Two copies would run two camera monitors and send every relay/Home
// Assistant call twice, so a second launch just exits. Placed after the
// CLI flags on purpose: --status/--test/--version/--help must still work
// while the menu bar app is running. Matches on bundle identifier when
// running from the .app, and on the executable name when running
// unbundled (e.g. `swift run` during development).

let currentPID = ProcessInfo.processInfo.processIdentifier
let myBundleID = Bundle.main.bundleIdentifier

let otherInstances = NSWorkspace.shared.runningApplications.filter { running in
    guard running.processIdentifier != currentPID else { return false }
    if let myBundleID {
        return running.bundleIdentifier == myBundleID
    }
    return running.executableURL?.lastPathComponent == "CameraProbe"
}

if let existing = otherInstances.first {
    print("CameraProbe is already running (pid \(existing.processIdentifier)); exiting.")
    exit(0)
}

// MARK: - Launch the menu bar app
//
// .accessory hides the Dock icon and app-menu bar (the CLI equivalent
// of Info.plist's LSUIElement=true) - this only ever shows up as a menu
// bar item, never in the Dock or Cmd+Tab switcher.

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let appDelegate = AppDelegate()
app.delegate = appDelegate

app.run()
