import AppKit

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
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        gatewayLauncher.stop()
    }
}

let application = NSApplication.shared
let delegate = NeptuneDesktopApplication()
application.delegate = delegate
application.setActivationPolicy(.regular)
application.run()
