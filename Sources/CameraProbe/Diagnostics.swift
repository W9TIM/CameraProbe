import AppKit
import Foundation

// MARK: - Self-test and status
//
// Backs `CameraProbe --test` and `CameraProbe --status`. These run as a
// one-off CLI invocation (not the long-running monitor), so every check
// here is synchronous - async network calls are bridged to synchronous
// via a semaphore since there's no RunLoop spinning to deliver callbacks
// through otherwise.

struct CheckResult {
    let label: String
    let passed: Bool
    let detail: String?
}

private func padded(_ label: String, width: Int = 34) -> String {
    label.padding(toLength: max(label.count, width), withPad: ".", startingAt: 0)
}

func checkDNS(_ host: String) -> CheckResult {
    CheckResult(label: "DNS (\(host))", passed: testDNS(host), detail: nil)
}

/// Holds the outcome of the dataTask closure below. The closure runs on
/// a background queue while checkHTTPReachable blocks the calling thread
/// on `semaphore.wait()`, so the wait/signal pair is what actually makes
/// writing here (in the closure) and reading there (after the wait)
/// safe - the class only needs to tell the compiler that's handled.
private final class ResultBox: @unchecked Sendable {
    var passed = false
    var detail: String?
}

func checkHTTPReachable(label: String, host: String, port: Int) -> CheckResult {
    guard let url = URL(string: "http://\(host):\(port)/") else {
        return CheckResult(label: label, passed: false, detail: "Bad URL")
    }

    var request = URLRequest(url: url)
    request.timeoutInterval = 5

    let semaphore = DispatchSemaphore(value: 0)
    let result = ResultBox()

    let task = networkSession.dataTask(with: request) { _, response, error in
        if let error = error {
            result.detail = error.localizedDescription
        } else if let http = response as? HTTPURLResponse {
            result.passed = true
            result.detail = "HTTP \(http.statusCode)"
        }
        semaphore.signal()
    }
    task.resume()
    _ = semaphore.wait(timeout: .now() + 6)

    return CheckResult(label: label, passed: result.passed, detail: result.detail)
}

/// Runs `/usr/bin/log stream` briefly to confirm the binary exists and
/// isn't immediately rejected - the same tool CameraMonitor.swift relies
/// on for its whole camera-detection mechanism.
func checkLogStreamAccess() -> CheckResult {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
    process.arguments = ["stream", "--style", "compact", "--predicate", "process == \"cameracaptured\""]

    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe

    do {
        try process.run()
    } catch {
        return CheckResult(label: "Log stream access", passed: false, detail: error.localizedDescription)
    }

    Thread.sleep(forTimeInterval: 1.0)
    let stillRunning = process.isRunning
    process.terminate()

    return CheckResult(
        label: "Log stream access",
        passed: stillRunning,
        detail: stillRunning ? nil : "log stream exited immediately - check permissions"
    )
}

// MARK: - Login Item / running-instance checks
//
// Replaces the old LaunchAgent-based checks. There's no plist or launchd
// label to query anymore - Login Item status comes straight from
// SMAppService (see LoginItem.swift), and "is the monitor actually
// running right now" comes from asking NSWorkspace whether another
// instance of this same app bundle is already running. This diagnostic
// code runs as a one-off CLI invocation (--test/--status) that exits
// before ever calling NSApplication.run(), so it never registers itself
// as a running application and can't self-match.

struct LoginItemStatus {
    let supported: Bool
    let enabled: Bool
    let detail: String
}

func loginItemStatus() -> LoginItemStatus {
    guard LoginItem.isSupported else {
        return LoginItemStatus(supported: false, enabled: false, detail: "Not running from an installed .app")
    }
    let enabled = LoginItem.isEnabled
    return LoginItemStatus(
        supported: true,
        enabled: enabled,
        detail: enabled ? "Enabled" : "Disabled"
    )
}

func isMonitorRunning() -> Bool {
    guard let bundleID = Bundle.main.bundleIdentifier else { return false }
    return NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == bundleID }
}

// MARK: - --test

func runSelfTest() -> Bool {
    print("CameraProbe \(appVersion) - self test\n")

    var results: [CheckResult] = []

    results.append(checkDNS(relayHost))
    results.append(checkDNS(homeAssistantHost))

    if enableRelay {
        results.append(checkHTTPReachable(label: "Relay reachability", host: relayHost, port: relayPort))
    }

    if enableHomeAssistant {
        results.append(checkHTTPReachable(label: "Home Assistant reachability", host: homeAssistantHost, port: homeAssistantPort))
    }

    results.append(checkLogStreamAccess())

    let loginItem = loginItemStatus()
    if loginItem.supported {
        results.append(CheckResult(label: "Start at Login", passed: true, detail: loginItem.detail))
    }

    results.append(CheckResult(label: "CameraProbe running", passed: isMonitorRunning(), detail: nil))

    for result in results {
        let status = result.passed ? "OK" : "FAIL"
        if let detail = result.detail, !detail.isEmpty {
            print("\(padded(result.label)) \(status) (\(detail))")
        } else {
            print("\(padded(result.label)) \(status)")
        }
    }

    let failedCount = results.filter { !$0.passed }.count
    print("")
    print(failedCount == 0 ? "All checks passed." : "\(failedCount) check(s) failed.")

    return failedCount == 0
}

// MARK: - --status

func printStatus() {
    print("CameraProbe \(appVersion)\n")

    let relayResult = enableRelay
        ? checkHTTPReachable(label: "Relay", host: relayHost, port: relayPort)
        : CheckResult(label: "Relay", passed: true, detail: "disabled")

    let haResult = enableHomeAssistant
        ? checkHTTPReachable(label: "Home Assistant", host: homeAssistantHost, port: homeAssistantPort)
        : CheckResult(label: "Home Assistant", passed: true, detail: "disabled")

    let loginItem = loginItemStatus()

    func line(_ label: String, _ value: String) {
        print("\(padded(label, width: 20)) \(value)")
    }

    line("Relay", relayResult.passed ? "OK" : "FAIL")
    line("Home Assistant", haResult.passed ? "OK" : "FAIL")
    line("Start at Login", loginItem.supported ? loginItem.detail : "N/A (not an installed .app)")
    line("Camera Monitor", isMonitorRunning() ? "Running" : "Not running")
}

// MARK: - --help

func printUsage() {
    print("""
    CameraProbe \(appVersion)

    Usage:
      CameraProbe                Launch the menu bar app (splash screen, then runs in the menu bar)
      CameraProbe --status       Show whether CameraProbe is running and reachable
      CameraProbe --test         Run diagnostics: DNS, relay, Home Assistant, log access, Login Item
      CameraProbe --version      Print the version
      CameraProbe --help         Show this message

    Preferences (relay, Home Assistant, ignored apps, Start at Login) are
    edited from the app's menu bar icon, not from the command line.
    """)
}
