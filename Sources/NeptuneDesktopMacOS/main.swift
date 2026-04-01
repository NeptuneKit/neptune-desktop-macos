import AppKit
import Dispatch

final class NeptuneDesktopApplication: NSObject, NSApplicationDelegate, @unchecked Sendable {
    private static let defaultHarmonyCallbackPort = 28767
    private struct RuntimeResolution {
        let configuration: DesktopRuntimeConfiguration
        let message: String?
    }

    private var windowController: NeptuneMainWindowController?
    private let gatewayLauncher = GatewayLauncher()
    private lazy var runtimeResolution: RuntimeResolution = Self.resolveRuntimeConfiguration()
    private var runtimeConfiguration: DesktopRuntimeConfiguration { runtimeResolution.configuration }
    private var runtimeResolutionMessage: String? { runtimeResolution.message }
    private lazy var inspectorReleasePageURL = InspectorLaunchTargetResolver.releasePageURL()
    private lazy var inspectorWebResolution = InspectorLaunchTargetResolver.resolveWebURL(
        gatewayURL: runtimeConfiguration.webURL
    )
    private lazy var harmonyBridgeManager = HarmonyPortBridgeManager(
        configuration: .init(
            enabled: runtimeConfiguration.harmonyAutoBridgeEnabled,
            hdcPath: runtimeConfiguration.hdcPath,
            gatewayPort: runtimeConfiguration.port,
            gatewayAliasPorts: runtimeConfiguration.port == DesktopRuntimeConfiguration.defaultPort
                ? []
                : [DesktopRuntimeConfiguration.defaultPort],
            callbackPorts: [Self.defaultHarmonyCallbackPort],
            intervalSeconds: runtimeConfiguration.harmonyBridgeIntervalSeconds
        ),
        callbackPortProvider: GatewayClientCallbackPortProvider(
            gatewayHost: runtimeConfiguration.host,
            gatewayPort: runtimeConfiguration.port
        )
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        gatewayLauncher.setConfigurationOverride(
            .init(
                binaryPath: runtimeConfiguration.binaryPath,
                host: runtimeConfiguration.host,
                port: runtimeConfiguration.port,
                hdcPath: runtimeConfiguration.hdcPath
            )
        )
        let controller = NeptuneMainWindowController(
            webURL: inspectorWebResolution.webURL,
            gatewayURL: runtimeConfiguration.webURL,
            inspectorReleasePageURL: inspectorReleasePageURL,
            onStartCLI: { [weak self] in
                self?.startGateway()
            },
            onStopCLI: { [weak self] in
                self?.gatewayLauncher.stop()
                self?.harmonyBridgeManager.stop()
            },
            onImportInspectorArchive: { [weak self] archiveURL in
                guard let self else {
                    return .failure(.system("应用状态不可用，请重试。"))
                }
                return InspectorLaunchTargetResolver.importManualInspectorArchive(
                    archiveURL: archiveURL,
                    gatewayURL: self.runtimeConfiguration.webURL
                )
            }
        )
        windowController = controller
        bindLauncherEvents()
        controller.showWindow(nil)
        if let runtimeResolutionMessage {
            controller.appendLogLine(runtimeResolutionMessage)
        }
        for line in inspectorWebResolution.logs {
            controller.appendLogLine(line)
        }
        ensureWindowVisible(controller)
        NSApp.activate(ignoringOtherApps: true)
        startGateway()
        harmonyBridgeManager.start()
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
        harmonyBridgeManager.stop()
        gatewayLauncher.stop()
    }

    @MainActor
    private func startGateway() {
        do {
            try gatewayLauncher.start()
        } catch {
            let message = "Failed to start gateway launcher: \(error)"
            NSLog("%@", message)
            windowController?.appendLogLine("[desktop] \(message)")
            windowController?.showMissingCLIHint(error.localizedDescription)
            windowController?.updateCLIStatus(isRunning: false)
        }
    }

    private func bindLauncherEvents() {
        harmonyBridgeManager.setLogHandler { [weak self] line in
            DispatchQueue.main.async {
                self?.windowController?.appendLogLine(line)
            }
        }
        gatewayLauncher.setLogHandler { [weak self] line in
            DispatchQueue.main.async {
                self?.windowController?.appendLogLine(line)
                if line.contains("未找到可用 gateway CLI") ||
                    line.contains("No such file or directory") ||
                    line.contains("command not found") {
                    self?.windowController?.showMissingCLIHint()
                }
            }
        }
        gatewayLauncher.setStateChangeHandler { [weak self] isRunning in
            DispatchQueue.main.async {
                self?.windowController?.updateCLIStatus(isRunning: isRunning)
                if isRunning {
                    self?.harmonyBridgeManager.start()
                } else {
                    self?.harmonyBridgeManager.stop()
                }
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

    private static func resolveRuntimeConfiguration() -> RuntimeResolution {
        let environment = ProcessInfo.processInfo.environment
        let hasExplicitWebURL =
            !(environment["NEPTUNE_WEB_URL"]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) ||
            !(environment["NEPTUNE_INSPECTOR_URL"]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        let base = DesktopRuntimeConfiguration.fromEnvironment(environment)
        let resolved = base.resolvingPortConflict(hasExplicitWebURL: hasExplicitWebURL)
        guard resolved.port != base.port else {
            return RuntimeResolution(configuration: resolved, message: nil)
        }

        let message =
            "[desktop] 端口 \(base.port) 已占用，自动切换到 \(resolved.port)。"
        return RuntimeResolution(configuration: resolved, message: message)
    }
}

let application = NSApplication.shared
let delegate = NeptuneDesktopApplication()
application.delegate = delegate
application.setActivationPolicy(.regular)
application.run()
