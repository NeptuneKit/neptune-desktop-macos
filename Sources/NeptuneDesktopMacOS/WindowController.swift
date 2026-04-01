import AppKit
import Darwin
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class NeptuneMainWindowController: NSWindowController {
    private let defaultWindowSize = NSSize(width: 1280, height: 860)
    private let viewModel: NeptuneMainWindowViewModel

    init(
        webURL: URL,
        gatewayURL: URL,
        inspectorReleasePageURL: URL,
        onStartCLI: @escaping () -> Void,
        onStopCLI: @escaping () -> Void,
        onImportInspectorArchive: @escaping (URL) -> Result<InspectorLaunchTargetResolver.WebURLResolution, InspectorLaunchTargetResolver.ManualImportError>
    ) {
        self.viewModel = NeptuneMainWindowViewModel(
            webURL: webURL,
            gatewayURL: gatewayURL,
            inspectorReleasePageURL: inspectorReleasePageURL,
            onStartCLI: onStartCLI,
            onStopCLI: onStopCLI,
            onImportInspectorArchive: onImportInspectorArchive
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 860),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Neptune Desktop CLI Shell"
        window.center()
        window.minSize = NSSize(width: 960, height: 640)

        super.init(window: window)
        let host = NSHostingController(rootView: NeptuneMainRootView(viewModel: viewModel))
        window.contentViewController = host
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        Task { @MainActor [viewModel] in
            viewModel.stopClientPolling()
            viewModel.stopLocalWebServer()
        }
    }

    func ensureWindowVisible() {
        guard let window else {
            return
        }

        var visibleFrames = NSScreen.screens.map(\.visibleFrame)
        if let mainVisibleFrame = NSScreen.main?.visibleFrame {
            visibleFrames.removeAll(where: { $0.equalTo(mainVisibleFrame) })
            visibleFrames.insert(mainVisibleFrame, at: 0)
        }

        guard !visibleFrames.isEmpty else {
            window.makeKeyAndOrderFront(nil)
            return
        }

        let normalizedFrame = WindowFrameNormalizer.normalize(
            frame: window.frame,
            visibleFrames: visibleFrames,
            minSize: window.minSize,
            preferredSize: defaultWindowSize,
            centerOnPrimaryVisibleFrame: false
        )

        if !window.frame.equalTo(normalizedFrame) {
            window.setFrame(normalizedFrame, display: true)
        }

        window.makeKeyAndOrderFront(nil)
    }

    func updateCLIStatus(isRunning: Bool) {
        viewModel.updateCLIStatus(isRunning: isRunning)
    }

    func appendLogLine(_ line: String) {
        viewModel.appendLogLine(line)
    }

    func showMissingCLIHint(_ reason: String? = nil) {
        viewModel.showMissingCLIHint(reason)
    }
}

@MainActor
private final class NeptuneMainWindowViewModel: ObservableObject {
    enum HealthState {
        case idle
        case ok
        case warning
        case error
    }

    struct StatusItem: Identifiable {
        let id: String
        let title: String
        var value: String
        var detail: String
        var state: HealthState
    }

    struct RegisteredClientItem: Identifiable {
        let id: String
        let platform: String
        let appId: String
        let sessionId: String
        let deviceId: String
        let callbackEndpoint: String
        let selected: Bool
        let lastSeenText: String
    }

    @Published var statusTitle: String = "CLI 状态：未运行"
    @Published var webURLText: String
    @Published var showRawLogs: Bool = false
    @Published var cliHintText: String = ""
    @Published var cliHintVisible: Bool = false
    @Published var isDropActive: Bool = false
    @Published var logDisplayText: String = ""
    @Published var statuses: [StatusItem]
    @Published var registeredClients: [RegisteredClientItem] = []
    @Published var clientsSummaryText: String = "暂无已注册设备"

    private var webURL: URL
    private let gatewayURL: URL
    private let inspectorReleasePageURL: URL
    private let onStartCLI: () -> Void
    private let onStopCLI: () -> Void
    private let onImportInspectorArchive: (URL) -> Result<InspectorLaunchTargetResolver.WebURLResolution, InspectorLaunchTargetResolver.ManualImportError>

    private var localWebServerProcess: Process?
    private var localWebServerRoot: URL?
    private var localWebServerPort: Int?
    private var allLogLines: [String] = []
    private var summaryLogLines: [String] = []
    private var isCLIActive = false
    private var clientPollingTask: Task<Void, Never>?

    init(
        webURL: URL,
        gatewayURL: URL,
        inspectorReleasePageURL: URL,
        onStartCLI: @escaping () -> Void,
        onStopCLI: @escaping () -> Void,
        onImportInspectorArchive: @escaping (URL) -> Result<InspectorLaunchTargetResolver.WebURLResolution, InspectorLaunchTargetResolver.ManualImportError>
    ) {
        self.webURL = webURL
        self.gatewayURL = gatewayURL
        self.webURLText = "Web URL: \(webURL.absoluteString)"
        self.inspectorReleasePageURL = inspectorReleasePageURL
        self.onStartCLI = onStartCLI
        self.onStopCLI = onStopCLI
        self.onImportInspectorArchive = onImportInspectorArchive
        self.statuses = [
            StatusItem(id: "gateway", title: "Gateway", value: "未运行", detail: "等待启动", state: .warning),
            StatusItem(id: "bridge", title: "Bridge", value: "待连接", detail: "等待设备上线", state: .idle),
            StatusItem(id: "web", title: "Web", value: "就绪", detail: "本地 H5 地址已加载", state: .ok),
            StatusItem(id: "client", title: "Client", value: "未注册", detail: "等待 clients:register", state: .idle),
        ]

        appendLogLine("[desktop] Web URL: \(webURL.absoluteString)")
        appendLogLine("[desktop] 等待 CLI 启动...")
        appendLogLine("[desktop] 若自动拉取失败，请点击“下载 Web 包”并将 zip 拖入本窗口导入。")
        startClientPolling()
    }

    func updateCLIStatus(isRunning: Bool) {
        isCLIActive = isRunning
        statusTitle = isRunning ? "CLI 状态：运行中" : "CLI 状态：未运行"
        updateStatus(id: "gateway", state: isRunning ? .ok : .warning, value: isRunning ? "在线" : "未运行", detail: isRunning ? "网关进程已启动" : "等待启动")
        if !isRunning {
            updateStatus(id: "client", state: .idle, value: "未注册", detail: "等待网关启动")
        }
    }

    func appendLogLine(_ line: String) {
        let normalized = line.replacingOccurrences(of: "\n", with: "")
        allLogLines.append(normalized)
        if let concise = conciseLogLine(from: normalized) {
            summaryLogLines.append(concise)
        }
        updateStatusFromLogLine(normalized)
        refreshLogView()
    }

    func showMissingCLIHint(_ reason: String? = nil) {
        var text = "未检测到可用 neptune CLI。请下载完整桌面包，或点击“下载 CLI”后配置 NEPTUNE_GATEWAY_BIN。"
        if let reason, !reason.isEmpty {
            text += " 原因：\(reason)"
        }
        cliHintText = text
        cliHintVisible = true
        appendLogLine("[desktop] \(text)")
    }

    func handleStartCLI() {
        onStartCLI()
    }

    func handleStopCLI() {
        onStopCLI()
    }

    func handleRepairAll() {
        appendLogLine("[desktop] 执行一键修复：重启网关与桥接。")
        updateStatus(id: "gateway", state: .warning, value: "修复中", detail: "正在重启网关")
        updateStatus(id: "bridge", state: .warning, value: "修复中", detail: "正在重建端口桥接")
        updateStatus(id: "client", state: .warning, value: "等待重连", detail: "请保持模拟器前台")
        onStopCLI()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.onStartCLI()
            self?.appendLogLine("[desktop] 一键修复已触发启动。")
        }
    }

    func handleOpenWeb() {
        NSWorkspace.shared.open(resolvedOpenWebURL())
    }

    func handleCopyWebURL() {
        let openURL = resolvedOpenWebURL()
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(openURL.absoluteString, forType: .string)
        appendLogLine("[desktop] 已复制 Web URL")
    }

    func handleOpenWebReleasePage() {
        NSWorkspace.shared.open(inspectorReleasePageURL)
    }

    func handleOpenGatewayReleasePage() {
        NSWorkspace.shared.open(GatewayLauncher.gatewayReleasePageURL())
    }

    func handleToggleRawLogs(_ enabled: Bool) {
        showRawLogs = enabled
        refreshLogView()
    }

    func stopClientPolling() {
        clientPollingTask?.cancel()
        clientPollingTask = nil
    }

    func handleDropArchive(itemProviders: [NSItemProvider]) -> Bool {
        for provider in itemProviders {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { [weak self] data, _ in
                    guard let self, let data,
                          let rawURL = URL(dataRepresentation: data, relativeTo: nil) else {
                        return
                    }
                    Task { @MainActor in
                        self.isDropActive = false
                        guard rawURL.pathExtension.lowercased() == "zip" else {
                            self.appendLogLine("[desktop] 导入失败：仅支持 .zip 包")
                            return
                        }
                        self.handleImportInspectorArchive(rawURL)
                    }
                }
                return true
            }
        }
        return false
    }

    func stopLocalWebServer() {
        localWebServerProcess?.terminate()
        localWebServerProcess = nil
    }

    private func startClientPolling() {
        stopClientPolling()
        clientPollingTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.refreshRegisteredClients()
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    private func refreshRegisteredClients() async {
        guard isCLIActive else {
            if !registeredClients.isEmpty {
                registeredClients = []
                clientsSummaryText = "暂无已注册设备"
            }
            return
        }

        var components = URLComponents(url: gatewayURL, resolvingAgainstBaseURL: false)
        components?.path = "/v2/clients"
        components?.query = nil
        guard let url = components?.url else {
            return
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                return
            }
            let snapshots = try GatewayClientsSnapshotParser.decodeList(from: data)
            let items = snapshots.map { snapshot in
                RegisteredClientItem(
                    id: "\(snapshot.platform)|\(snapshot.appId)|\(snapshot.sessionId)|\(snapshot.deviceId)",
                    platform: snapshot.platform,
                    appId: snapshot.appId,
                    sessionId: snapshot.sessionId,
                    deviceId: snapshot.deviceId,
                    callbackEndpoint: snapshot.callbackEndpoint,
                    selected: snapshot.selected,
                    lastSeenText: shortLastSeenText(snapshot.lastSeenAt)
                )
            }
            registeredClients = items
            clientsSummaryText = items.isEmpty ? "暂无已注册设备" : "已注册 \(items.count) 台设备"
            updateClientStatusFromList(items)
        } catch {
            // 静默忽略轮询异常，避免刷屏日志
        }
    }

    private func handleImportInspectorArchive(_ archiveURL: URL) {
        switch onImportInspectorArchive(archiveURL) {
        case .success(let resolution):
            webURL = resolution.webURL
            webURLText = "Web URL: \(webURL.absoluteString)"
            updateStatus(id: "web", state: .ok, value: "已导入", detail: "使用本地拖入 Web 资源")
            for line in resolution.logs {
                appendLogLine(line)
            }
            appendLogLine("[desktop] 当前已切换到导入的本地 Web 资源。")
        case .failure(let error):
            appendLogLine("[desktop] \(error.localizedDescription)")
        }
    }

    private func resolvedOpenWebURL() -> URL {
        guard webURL.isFileURL else {
            return webURL
        }
        guard let servedURL = ensureServedHTTPURL(for: webURL) else {
            return webURL
        }
        return servedURL
    }

    private func ensureServedHTTPURL(for fileWebURL: URL) -> URL? {
        let indexURL = URL(fileURLWithPath: fileWebURL.path, isDirectory: false)
        let distDirectory = indexURL.deletingLastPathComponent()

        guard FileManager.default.fileExists(atPath: indexURL.path),
              FileManager.default.fileExists(atPath: distDirectory.path) else {
            appendLogLine("[desktop] 本地 Web 资源不存在，回退 file:// 打开。")
            updateStatus(id: "web", state: .warning, value: "回退 file://", detail: "本地 dist 缺失")
            return nil
        }

        let gatewayValue = URLComponents(url: fileWebURL, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "gateway" })?
            .value

        if let process = localWebServerProcess,
           process.isRunning,
           localWebServerRoot == distDirectory,
           let port = localWebServerPort {
            return makeServedIndexURL(port: port, gatewayValue: gatewayValue)
        }

        localWebServerProcess?.terminate()
        localWebServerProcess = nil
        localWebServerRoot = nil
        localWebServerPort = nil

        guard let port = findAvailablePort(start: 39600, maxAttempts: 100) else {
            appendLogLine("[desktop] 未找到可用端口用于本地 Web 服务，回退 file:// 打开。")
            return nil
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", "-c", pythonSPAServerScript, String(port), distDirectory.path]
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        do {
            try process.run()
            usleep(200_000)
            guard process.isRunning else {
                appendLogLine("[desktop] 本地 Web 服务启动失败，回退 file:// 打开。")
                return nil
            }
            localWebServerProcess = process
            localWebServerRoot = distDirectory
            localWebServerPort = port
            appendLogLine("[desktop] 已启动本地 Web 服务：http://127.0.0.1:\(port)")
            updateStatus(id: "web", state: .ok, value: "本地服务", detail: "127.0.0.1:\(port)")
            return makeServedIndexURL(port: port, gatewayValue: gatewayValue)
        } catch {
            appendLogLine("[desktop] 本地 Web 服务启动异常：\(error.localizedDescription)")
            updateStatus(id: "web", state: .error, value: "启动失败", detail: "本地服务异常")
            return nil
        }
    }

    private func makeServedIndexURL(port: Int, gatewayValue: String?) -> URL {
        var components = URLComponents()
        components.scheme = "http"
        components.host = "127.0.0.1"
        components.port = port
        components.path = "/index.html"
        if let gatewayValue, !gatewayValue.isEmpty {
            components.queryItems = [URLQueryItem(name: "gateway", value: gatewayValue)]
        }
        return components.url ?? URL(string: "http://127.0.0.1:\(port)/index.html")!
    }

    private var pythonSPAServerScript: String {
        """
import functools
import http.server
import os
import socketserver
import sys
import urllib.parse

port = int(sys.argv[1])
root = sys.argv[2]

class SPAHandler(http.server.SimpleHTTPRequestHandler):
    protocol_version = 'HTTP/1.0'

    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=root, **kwargs)

    def _rewrite_missing_to_index(self):
        parsed = urllib.parse.urlsplit(self.path)
        decoded_path = urllib.parse.unquote(parsed.path)
        path = decoded_path.lstrip('/')
        candidate = os.path.join(root, path)
        if parsed.path.endswith('/'):
            candidate = os.path.join(candidate, 'index.html')
        if os.path.exists(candidate):
            return

        for marker in ('/assets/', '/mocks/'):
            idx = decoded_path.find(marker)
            if idx >= 0:
                normalized_path = decoded_path[idx:]
                normalized_candidate = os.path.join(root, normalized_path.lstrip('/'))
                if os.path.exists(normalized_candidate):
                    query = ('?' + parsed.query) if parsed.query else ''
                    self.path = normalized_path + query
                    return

        query = ('?' + parsed.query) if parsed.query else ''
        self.path = '/index.html' + query

    def do_GET(self):
        self._rewrite_missing_to_index()
        if self._path_only() == '/index.html':
            return self._serve_index_with_base(include_body=True)
        return super().do_GET()

    def do_HEAD(self):
        self._rewrite_missing_to_index()
        if self._path_only() == '/index.html':
            return self._serve_index_with_base(include_body=False)
        return super().do_HEAD()

    def _path_only(self):
        return urllib.parse.urlsplit(self.path).path

    def _serve_index_with_base(self, include_body):
        index_path = os.path.join(root, 'index.html')
        try:
            with open(index_path, 'rb') as fp:
                html = fp.read().decode('utf-8')
        except Exception:
            self.send_error(404, 'File not found')
            return

        if '<base ' not in html:
            html = html.replace('<head>', '<head>\\n    <base href="/">', 1)

        body = html.encode('utf-8')
        self.send_response(200)
        self.send_header('Content-Type', 'text/html; charset=utf-8')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        if include_body:
            self.wfile.write(body)

    def log_message(self, format, *args):
        pass

class ThreadingTCPServer(socketserver.ThreadingMixIn, socketserver.TCPServer):
    daemon_threads = True
    allow_reuse_address = True

server = ThreadingTCPServer(('127.0.0.1', port), functools.partial(SPAHandler))
server.serve_forever()
"""
    }

    private func findAvailablePort(start: Int, maxAttempts: Int) -> Int? {
        guard start > 0, start < 65535 else { return nil }
        for offset in 0..<maxAttempts {
            let candidate = start + offset
            guard candidate <= 65535 else { break }
            if isPortAvailable(candidate) {
                return candidate
            }
        }
        return nil
    }

    private func isPortAvailable(_ port: Int) -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { Darwin.close(fd) }

        var opt: Int32 = 1
        _ = withUnsafePointer(to: &opt) {
            setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, $0, socklen_t(MemoryLayout<Int32>.size))
        }

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(UInt16(port)).bigEndian
        addr.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { ptr in
                Darwin.bind(fd, ptr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return bindResult == 0
    }

    private func conciseLogLine(from line: String) -> String? {
        if line.contains("[Vapor] GET /v2/clients") {
            return nil
        }
        if line.contains("[desktop]") || line.contains("[bridge]") {
            return line
        }
        if line.contains("POST /v2/clients:register") {
            return line
        }
        if line.contains("No live ui-tree snapshot available") || line.contains("/v2/ui-tree/snapshot") {
            return line
        }
        if line.contains("Failed to start gateway launcher") || line.contains("register failed") {
            return line
        }
        return nil
    }

    private func refreshLogView() {
        let source = showRawLogs ? allLogLines : summaryLogLines
        let tail = source.suffix(600)
        logDisplayText = tail.joined(separator: "\n") + (tail.isEmpty ? "" : "\n")
    }

    private func updateStatusFromLogLine(_ line: String) {
        if line.contains("Failed to start gateway launcher") ||
            line.contains("未找到可用 gateway CLI") ||
            (line.contains("gateway stderr:") && line.contains("Abort.404")) {
            updateStatus(id: "gateway", state: .error, value: "异常", detail: "网关需修复")
        } else if line.contains("Launched gateway process") || line.contains("[Vapor] Server started on") {
            updateStatus(id: "gateway", state: .ok, value: "在线", detail: "网关可用")
        }

        if line.contains("[bridge]") && line.contains("失败") {
            updateStatus(id: "bridge", state: .warning, value: "异常", detail: "桥接失败，需重试")
        } else if line.contains("[bridge] 已建立") || line.contains("[bridge] 发现动态回调端口") {
            updateStatus(id: "bridge", state: .ok, value: "已连接", detail: "端口映射正常")
        } else if line.contains("[bridge] 未检测到已连接 Harmony target") {
            updateStatus(id: "bridge", state: .warning, value: "待连接", detail: "未检测到设备")
        }

        if line.contains("POST /v2/clients:register") {
            updateStatus(id: "client", state: .ok, value: "已注册", detail: "客户端注册成功")
        }
        if line.contains("No live ui-tree snapshot available") {
            updateStatus(id: "client", state: .warning, value: "无快照", detail: "客户端在线但无可用快照")
        }
        if !isCLIActive {
            updateStatus(id: "client", state: .idle, value: "未注册", detail: "等待网关启动")
        }
    }

    private func updateClientStatusFromList(_ items: [RegisteredClientItem]) {
        guard isCLIActive else { return }
        guard !items.isEmpty else {
            updateStatus(id: "client", state: .warning, value: "未注册", detail: "等待 clients:register")
            return
        }
        let selectedCount = items.filter(\.selected).count
        let detail = selectedCount > 0 ? "已选择 \(selectedCount) 台设备" : "已注册 \(items.count) 台设备"
        updateStatus(id: "client", state: .ok, value: "\(items.count) 台", detail: detail)
    }

    private func updateStatus(id: String, state: HealthState, value: String, detail: String) {
        guard let index = statuses.firstIndex(where: { $0.id == id }) else {
            return
        }
        statuses[index].state = state
        statuses[index].value = value
        statuses[index].detail = detail
    }

    private func shortLastSeenText(_ raw: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = formatter.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
        guard let date else { return raw }

        let output = DateFormatter()
        output.locale = Locale(identifier: "zh_CN")
        output.dateFormat = "HH:mm:ss"
        return output.string(from: date)
    }
}

private struct NeptuneMainRootView: View {
    @ObservedObject var viewModel: NeptuneMainWindowViewModel
    @State private var isLogPanelCollapsed = false

    private let columns: [GridItem] = [
        GridItem(.adaptive(minimum: 220, maximum: 320), spacing: 12)
    ]

    var body: some View {
        VSplitView {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HeaderRow(
                        statusTitle: viewModel.statusTitle,
                        isLogPanelCollapsed: isLogPanelCollapsed,
                        onToggleLogPanel: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isLogPanelCollapsed.toggle()
                            }
                        }
                    )

                    GroupBox("运行状态") {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(viewModel.statuses) { item in
                                StatusCardView(item: item)
                            }
                        }
                        .padding(.top, 4)
                    }

                    GroupBox("已注册设备") {
                        RegisteredClientsPanelView(
                            summaryText: viewModel.clientsSummaryText,
                            clients: viewModel.registeredClients
                        )
                        .padding(.top, 4)
                    }

                    GroupBox("Web 地址") {
                        Text(viewModel.webURLText)
                            .font(.system(size: 12, weight: .regular, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .padding(.top, 2)
                    }

                    GroupBox("常用操作") {
                        OperationsPanelView(viewModel: viewModel)
                            .padding(.top, 2)
                    }

                    DropZoneView(
                        isActive: viewModel.isDropActive,
                        onDropFiles: { providers in
                            viewModel.handleDropArchive(itemProviders: providers)
                        },
                        onHoverChanged: { isHovering in
                            viewModel.isDropActive = isHovering
                        }
                    )
                    .frame(height: 72)

                    if viewModel.cliHintVisible {
                        Text(viewModel.cliHintText)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.primary)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.orange.opacity(0.10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.orange.opacity(0.8), lineWidth: 1)
                            )
                    }
                }
                .padding(16)
            }
            .frame(minHeight: 300)

            if isLogPanelCollapsed {
                CollapsedLogBarView {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isLogPanelCollapsed = false
                    }
                }
                .frame(height: 40)
            } else {
                LogPanelView(
                    text: viewModel.logDisplayText,
                    showRawLogs: Binding(
                        get: { viewModel.showRawLogs },
                        set: { viewModel.handleToggleRawLogs($0) }
                    ),
                    onCollapse: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isLogPanelCollapsed = true
                        }
                    }
                )
                .frame(minHeight: 240)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct OperationsPanelView: View {
    @ObservedObject var viewModel: NeptuneMainWindowViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("主操作")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                ActionTileButton(
                    title: "启动 CLI",
                    subtitle: "启动网关与桥接",
                    symbol: "play.fill",
                    tint: .green,
                    isProminent: true
                ) {
                    viewModel.handleStartCLI()
                }
                ActionTileButton(
                    title: "停止 CLI",
                    subtitle: "结束本地服务",
                    symbol: "stop.fill",
                    tint: .red,
                    isProminent: false
                ) {
                    viewModel.handleStopCLI()
                }
                ActionTileButton(
                    title: "打开 Web",
                    subtitle: "在浏览器中打开",
                    symbol: "safari.fill",
                    tint: .accentColor,
                    isProminent: true
                ) {
                    viewModel.handleOpenWeb()
                }
            }

            Divider()

            Text("诊断与辅助")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                ActionTileButton(
                    title: "一键修复",
                    subtitle: "重启并重建连接",
                    symbol: "wrench.and.screwdriver.fill",
                    tint: .orange,
                    isProminent: false
                ) {
                    viewModel.handleRepairAll()
                }
                ActionTileButton(
                    title: "复制 URL",
                    subtitle: "复制当前访问地址",
                    symbol: "doc.on.doc.fill",
                    tint: .secondary,
                    isProminent: false
                ) {
                    viewModel.handleCopyWebURL()
                }
            }

            Divider()

            Text("下载分发")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                ActionTileButton(
                    title: "下载 Web 包",
                    subtitle: "获取前端发布包",
                    symbol: "shippingbox.fill",
                    tint: .blue,
                    isProminent: false
                ) {
                    viewModel.handleOpenWebReleasePage()
                }
                ActionTileButton(
                    title: "下载 CLI",
                    subtitle: "获取网关命令行",
                    symbol: "terminal.fill",
                    tint: .purple,
                    isProminent: false
                ) {
                    viewModel.handleOpenGatewayReleasePage()
                }
            }
        }
    }
}

private struct ActionTileButton: View {
    let title: String
    let subtitle: String
    let symbol: String
    let tint: Color
    let isProminent: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isProminent ? .white : tint)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isProminent ? .white : .primary)
                    Text(subtitle)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(isProminent ? Color.white.opacity(0.85) : .secondary)
                }
                Spacer(minLength: 4)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isProminent ? tint : tint.opacity(0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isProminent ? tint.opacity(0.95) : tint.opacity(0.35), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct HeaderRow: View {
    let statusTitle: String
    let isLogPanelCollapsed: Bool
    let onToggleLogPanel: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Text("Neptune Desktop")
                .font(.system(size: 22, weight: .semibold))
            Button(isLogPanelCollapsed ? "展开日志" : "收起日志") {
                onToggleLogPanel()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            Spacer(minLength: 8)
            Text(statusTitle.replacingOccurrences(of: "CLI 状态：", with: ""))
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.accentColor.opacity(0.14))
                .clipShape(Capsule())
        }
    }
}

private struct StatusCardView: View {
    let item: NeptuneMainWindowViewModel.StatusItem

    private var accentColor: Color {
        switch item.state {
        case .idle:
            return .secondary
        case .ok:
            return .green
        case .warning:
            return .orange
        case .error:
            return .red
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(item.value)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(accentColor)
            Text(item.detail)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(accentColor.opacity(0.65), lineWidth: 1)
        )
    }
}

private struct RegisteredClientsPanelView: View {
    let summaryText: String
    let clients: [NeptuneMainWindowViewModel.RegisteredClientItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(summaryText)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            if clients.isEmpty {
                Text("等待设备发起 clients:register ...")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
            } else {
                VStack(spacing: 8) {
                    ForEach(clients) { item in
                        RegisteredClientRowView(item: item)
                    }
                }
            }
        }
    }
}

private struct RegisteredClientRowView: View {
    let item: NeptuneMainWindowViewModel.RegisteredClientItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(item.platform.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.16))
                    .clipShape(Capsule())
                Text(item.selected ? "已选择" : "未选择")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(item.selected ? Color.green : .secondary)
                Spacer()
                Text("lastSeen \(item.lastSeenText)")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.secondary)
            }
            Text(item.appId)
                .font(.system(size: 12, weight: .semibold))
                .textSelection(.enabled)
            Text("device: \(item.deviceId)   session: \(item.sessionId)")
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }
}

private struct DropZoneView: View {
    let isActive: Bool
    let onDropFiles: ([NSItemProvider]) -> Bool
    let onHoverChanged: (Bool) -> Void

    var body: some View {
        let activeColor = Color.accentColor
        let idleColor = Color(nsColor: .tertiaryLabelColor)

        return ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill((isActive ? activeColor : Color(nsColor: .windowBackgroundColor)).opacity(isActive ? 0.12 : 0.65))
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                .foregroundStyle(isActive ? activeColor : idleColor)
            VStack(spacing: 4) {
                Text(isActive ? "松开鼠标导入 Web zip 包" : "将 Web zip 包拖入这里导入")
                    .font(.system(size: 13, weight: .semibold))
                Text("仅支持 .zip")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(isActive ? activeColor : .primary)
        }
        .onDrop(of: [UTType.fileURL], isTargeted: nil) { providers in
            onDropFiles(providers)
        }
        .onDrop(of: [UTType.fileURL], delegate: HoverDropDelegate(onHoverChanged: onHoverChanged, onDropFiles: onDropFiles))
    }
}

private struct LogPanelView: View {
    let text: String
    @Binding var showRawLogs: Bool
    let onCollapse: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("日志")
                    .font(.headline)
                Spacer()
                Button("收起") {
                    onCollapse()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                Toggle("显示原始日志", isOn: $showRawLogs)
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }

            ScrollView {
                Text(text)
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(10)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            )
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .padding(.top, 8)
    }
}

private struct CollapsedLogBarView: View {
    let onExpand: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text("日志面板已收起")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer()
            Button("展开日志") {
                onExpand()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }
}

private struct HoverDropDelegate: DropDelegate {
    let onHoverChanged: (Bool) -> Void
    let onDropFiles: ([NSItemProvider]) -> Bool

    func validateDrop(info: DropInfo) -> Bool {
        true
    }

    func dropEntered(info: DropInfo) {
        onHoverChanged(true)
    }

    func dropExited(info: DropInfo) {
        onHoverChanged(false)
    }

    func performDrop(info: DropInfo) -> Bool {
        onHoverChanged(false)
        return onDropFiles(info.itemProviders(for: [UTType.fileURL]))
    }
}
