import AppKit
import Dispatch

@MainActor
final class NeptuneDesktopApplication: NSObject, NSApplicationDelegate {
    private var windowController: NeptuneMainWindowController?
    private let gatewayLauncher = GatewayLauncher()
    private let runtimeConfiguration = DesktopRuntimeConfiguration.fromEnvironment()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = NeptuneMainWindowController(
            webURL: runtimeConfiguration.webURL,
            onStartCLI: { [weak self] in
                self?.startGateway()
            },
            onStopCLI: { [weak self] in
                self?.gatewayLauncher.stop()
            }
        )
        windowController = controller
        bindLauncherEvents()
        controller.showWindow(nil)
        ensureWindowVisible(controller)
        NSApp.activate(ignoringOtherApps: true)
        startGateway()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        if let windowController {
            ensureWindowVisible(windowController)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        gatewayLauncher.stop()
    }

    private func startGateway() {
        do {
            try gatewayLauncher.start()
        } catch {
            let message = "Failed to start gateway launcher: \(error)"
            NSLog("%@", message)
            windowController?.appendLogLine("[desktop] \(message)")
            windowController?.updateCLIStatus(isRunning: false)
        }
    }

    private func bindLauncherEvents() {
        gatewayLauncher.setLogHandler { [weak self] line in
            Task { @MainActor in
                self?.windowController?.appendLogLine(line)
            }
        }
        gatewayLauncher.setStateChangeHandler { [weak self] isRunning in
            Task { @MainActor in
                self?.windowController?.updateCLIStatus(isRunning: isRunning)
            }
        }
    }

    private func ensureWindowVisible(_ controller: NeptuneMainWindowController) {
        for delay in [0.0, 0.3, 1.0, 2.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                controller.ensureWindowVisible()
            }
        }
    }
}

let application = NSApplication.shared
let delegate = NeptuneDesktopApplication()
application.delegate = delegate
application.setActivationPolicy(.regular)
application.run()
