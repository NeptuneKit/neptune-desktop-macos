import AppKit
import Dispatch

@MainActor
final class NeptuneDesktopApplication: NSObject, NSApplicationDelegate {
    private var windowController: NeptuneMainWindowController?
    private let gatewayLauncher = GatewayLauncher()

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            try gatewayLauncher.start()
        } catch {
            NSLog("Failed to start gateway launcher: %@", String(describing: error))
        }

        let controller = NeptuneMainWindowController(
            launchTarget: InspectorLaunchTargetResolver.resolve()
        )
        windowController = controller
        controller.showWindow(nil)
        ensureWindowVisible(controller)
        NSApp.activate(ignoringOtherApps: true)
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
