import Foundation

// MARK: - Command-line flags
//
// --test/--status/--version/--help all exit immediately without starting
// the monitor - they're one-off diagnostic invocations, not the
// long-running process the LaunchAgent keeps alive.

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

printStartupBanner()

// Sanity-check both hostnames resolve before we start relying on them.
// (Wires up the DNS check that existed in the original file but was
// never actually called.)
testDNS(relayHost)
testDNS(homeAssistantHost)

// Handle SIGINT/SIGTERM so the log-stream subprocess is terminated
// cleanly instead of being left as an orphan when this process exits
// (relevant once this runs under launchd, which sends SIGTERM on unload).
signal(SIGINT, SIG_IGN)
let sigintSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
sigintSource.setEventHandler {
    logger.info("Received SIGINT, shutting down...")
    cameraMonitor.stop()
    exit(0)
}
sigintSource.resume()

signal(SIGTERM, SIG_IGN)
let sigtermSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
sigtermSource.setEventHandler {
    logger.info("Received SIGTERM, shutting down...")
    cameraMonitor.stop()
    exit(0)
}
sigtermSource.resume()

startCameraMonitor()

RunLoop.main.run()
