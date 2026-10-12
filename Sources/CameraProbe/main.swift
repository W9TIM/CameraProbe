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
