import AppKit
import Foundation

// MARK: - App Delegate
//
// Replaces the old CLI's plain RunLoop.main.run() startup. This is now
// a menu-bar-only AppKit app (no Dock icon, no app menu bar) - see
// main.swift for the .accessory activation policy that hides it.

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    private var splashWindowController: SplashWindowController?
    private var sigintSource: DispatchSourceSignal?
    private var sigtermSource: DispatchSourceSignal?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let splash = SplashWindowController()
        splash.showSplash()
        splashWindowController = splash

        printStartupBanner()
        testDNS(relayHost)
        testDNS(homeAssistantHost)

        installSignalHandlers()

        statusBarController = StatusBarController()
        startCameraMonitor()

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.splashWindowController?.dismiss()
            self?.splashWindowController = nil
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        cameraMonitor.stop()
    }

    // Signal handling matters even for a GUI app: at logout/shutdown the
    // system can send SIGTERM before routing through the normal
    // NSApplication termination path, and this ensures the log-stream
    // subprocess still gets torn down cleanly either way.
    private func installSignalHandlers() {
        signal(SIGINT, SIG_IGN)
        let sigint = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        sigint.setEventHandler { [weak self] in
            self?.shutdown()
        }
        sigint.resume()
        sigintSource = sigint

        signal(SIGTERM, SIG_IGN)
        let sigterm = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        sigterm.setEventHandler { [weak self] in
            self?.shutdown()
        }
        sigterm.resume()
        sigtermSource = sigterm
    }

    private func shutdown() {
        logger.info("Received termination signal, shutting down...")
        cameraMonitor.stop()
        NSApp.terminate(nil)
    }
}
