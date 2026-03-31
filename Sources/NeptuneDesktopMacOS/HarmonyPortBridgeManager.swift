import Foundation
import SKProcessRunner

protocol CallbackPortProviding: Sendable {
    func callbackPorts() -> [Int]
}

struct GatewayClientCallbackPortProvider: CallbackPortProviding {
    let gatewayHost: String
    let gatewayPort: Int
    let requestTimeout: TimeInterval

    init(gatewayHost: String, gatewayPort: Int, requestTimeout: TimeInterval = 1.5) {
        self.gatewayHost = gatewayHost
        self.gatewayPort = gatewayPort
        self.requestTimeout = requestTimeout
    }

    func callbackPorts() -> [Int] {
        var components = URLComponents()
        components.scheme = "http"
        components.host = gatewayHost
        components.port = gatewayPort
        components.path = "/v2/clients"
        guard let url = components.url else {
            return []
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        process.arguments = [
            "-sS",
            "--max-time",
            String(format: "%.1f", requestTimeout),
            url.absoluteString
        ]
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return []
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            return []
        }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        return parseCallbackPorts(from: data)
    }

    private func parseCallbackPorts(from data: Data) -> [Int] {
        guard let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []),
              let root = jsonObject as? [String: Any],
              let items = root["items"] as? [[String: Any]] else {
            return []
        }

        var ports: [Int] = []
        for item in items {
            guard let callbackEndpoint = item["callbackEndpoint"] as? String,
                  let url = URL(string: callbackEndpoint),
                  let port = url.port,
                  port > 0,
                  port <= 65_535 else {
                continue
            }
            if !ports.contains(port) {
                ports.append(port)
            }
        }
        return ports
    }
}

struct ShellCommandResult: Sendable {
    let status: Int32
    let output: String
}

protocol ShellCommandRunning: Sendable {
    func run(launchPath: String, arguments: [String]) -> ShellCommandResult
}

struct ProcessShellCommandRunner: ShellCommandRunning {
    func run(launchPath: String, arguments: [String]) -> ShellCommandResult {
        let payload = SKProcessPayload
            .executableURL(URL(fileURLWithPath: launchPath))
            .arguments(arguments)
            .environment(.current())
            .timeoutMs(8_000)
            .maxOutputBytes(256 * 1024)

        do {
            let result = try SKProcessRunner.runSync(payload)
            let output = mergeOutput(stdout: result.stdout, stderr: result.stderr)
            return ShellCommandResult(status: Int32(result.exitCode), output: output)
        } catch {
            return ShellCommandResult(status: -1, output: String(describing: error))
        }
    }

    private func mergeOutput(stdout: String, stderr: String) -> String {
        if stdout.isEmpty {
            return stderr
        }
        if stderr.isEmpty {
            return stdout
        }
        return stdout + "\n" + stderr
    }
}

final class HarmonyPortBridgeManager: @unchecked Sendable {
    typealias LogHandler = (String) -> Void

    struct Configuration: Sendable, Equatable {
        let enabled: Bool
        let hdcPath: String
        let gatewayPort: Int
        let callbackPorts: [Int]
        let intervalSeconds: TimeInterval
    }

    private let configuration: Configuration
    private let commandRunner: ShellCommandRunning
    private let callbackPortProvider: (any CallbackPortProviding)?
    private let queue = DispatchQueue(label: "io.github.neptunekit.desktop.bridge")
    private var timer: DispatchSourceTimer?
    private var isRunning = false
    private var logHandler: LogHandler?
    private var lastLogLine: String?

    init(
        configuration: Configuration,
        commandRunner: ShellCommandRunning = ProcessShellCommandRunner(),
        callbackPortProvider: (any CallbackPortProviding)? = nil
    ) {
        self.configuration = configuration
        self.commandRunner = commandRunner
        self.callbackPortProvider = callbackPortProvider
    }

    func setLogHandler(_ handler: LogHandler?) {
        queue.sync {
            logHandler = handler
        }
    }

    func start() {
        queue.async { [weak self] in
            guard let self else {
                return
            }
            guard self.configuration.enabled else {
                self.emitLogOnce("Harmony 自动桥接已禁用。")
                return
            }
            guard !self.isRunning else {
                return
            }

            self.isRunning = true
            self.emitLog("Harmony 自动桥接已启动。")
            self.reconcileBridge()

            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now() + self.configuration.intervalSeconds, repeating: self.configuration.intervalSeconds)
            timer.setEventHandler { [weak self] in
                self?.reconcileBridge()
            }
            timer.resume()
            self.timer = timer
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else {
                return
            }
            self.timer?.cancel()
            self.timer = nil
            self.isRunning = false
            self.lastLogLine = nil
            self.emitLog("Harmony 自动桥接已停止。")
        }
    }

    func reconcileNowForTesting() {
        queue.sync {
            reconcileBridge()
        }
    }

    private func reconcileBridge() {
        let targets = connectedTargets()
        guard !targets.isEmpty else {
            emitLogOnce("未检测到已连接 Harmony target，等待设备上线。")
            return
        }

        let dynamicPorts = callbackPortProvider?.callbackPorts() ?? []
        if !dynamicPorts.isEmpty {
            emitLog("发现动态回调端口：\(dynamicPorts.map(String.init).joined(separator: ","))")
        }

        for target in targets {
            bridgeGatewayPort(target: target, port: configuration.gatewayPort)
            for callbackPort in mergedCallbackPorts(dynamicPorts: dynamicPorts) {
                bridgeCallbackPort(target: target, port: callbackPort)
            }
        }
    }

    private func bridgeGatewayPort(target: String, port: Int) {
        guard port > 0, port <= 65_535 else {
            return
        }
        let mapping = "tcp:\(port)"
        let rportResult = runHdc(arguments: ["-t", target, "rport", mapping, mapping])
        if rportResult.status == 0 {
            emitLogOnce("已建立网关桥接 target=\(target) \(mapping)->\(mapping)")
            return
        }

        let fallbackResult = runHdc(arguments: ["-t", target, "fport", mapping, mapping])
        if fallbackResult.status == 0 {
            emitLogOnce("已建立网关桥接(target=\(target), 使用 fport 回退) \(mapping)->\(mapping)")
            return
        }

        let detail = condensedOutput(primary: rportResult.output, fallback: fallbackResult.output)
        emitLogOnce("网关桥接失败 target=\(target) port=\(port) detail=\(detail)")
    }

    private func bridgeCallbackPort(target: String, port: Int) {
        guard port > 0, port <= 65_535 else {
            return
        }
        let mapping = "tcp:\(port)"
        let fportResult = runHdc(arguments: ["-t", target, "fport", mapping, mapping])
        if fportResult.status == 0 {
            emitLogOnce("已建立回调桥接 target=\(target) \(mapping)->\(mapping)")
            return
        }

        let detail = condensedOutput(primary: fportResult.output, fallback: "")
        emitLogOnce("回调桥接失败 target=\(target) port=\(port) detail=\(detail)")
    }

    private func mergedCallbackPorts(dynamicPorts: [Int]) -> [Int] {
        var ports: [Int] = configuration.callbackPorts
        for port in dynamicPorts where !ports.contains(port) {
            ports.append(port)
        }
        return ports
    }

    private func connectedTargets() -> [String] {
        let result = runHdc(arguments: ["list", "targets", "-v"])
        guard result.status == 0 else {
            emitLogOnce("无法读取 hdc target 列表：\(result.output.trimmingCharacters(in: .whitespacesAndNewlines))")
            return []
        }

        var targets: [String] = []
        let lines = result.output.split(whereSeparator: \.isNewline)
        for line in lines {
            let text = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                continue
            }
            let parts = text.split(whereSeparator: \.isWhitespace)
            guard parts.count >= 3 else {
                continue
            }
            guard parts[2].lowercased() == "connected" else {
                continue
            }
            targets.append(String(parts[0]))
        }

        return targets
    }

    private func runHdc(arguments: [String]) -> ShellCommandResult {
        commandRunner.run(launchPath: configuration.hdcPath, arguments: arguments)
    }

    private func condensedOutput(primary: String, fallback: String) -> String {
        let merged = "\(primary)\n\(fallback)"
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " | ")
        return merged.isEmpty ? "unknown" : merged
    }

    private func emitLog(_ line: String) {
        let handler = logHandler
        handler?("[bridge] \(line)")
    }

    private func emitLogOnce(_ line: String) {
        guard lastLogLine != line else {
            return
        }
        lastLogLine = line
        emitLog(line)
    }
}
