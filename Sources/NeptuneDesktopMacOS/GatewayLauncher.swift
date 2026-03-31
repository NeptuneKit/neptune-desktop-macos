import Foundation

public final class GatewayLauncher: @unchecked Sendable {
    public typealias LogHandler = (String) -> Void
    public typealias StateChangeHandler = (Bool) -> Void

    public struct Configuration: Sendable {
        public let binaryPath: String
        public let host: String
        public let port: Int
        public let hdcPath: String

        public init(
            binaryPath: String,
            host: String,
            port: Int,
            hdcPath: String
        ) {
            self.binaryPath = binaryPath
            self.host = host
            self.port = port
            self.hdcPath = hdcPath
        }
    }

    public private(set) var isRunning = false

    private let lock = NSLock()
    private var process: Process?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var logHandler: LogHandler?
    private var stateChangeHandler: StateChangeHandler?
    private var configurationOverride: Configuration?

    public init() {}

    deinit {
        stop()
    }

    public func start() throws {
        lock.lock()
        guard process == nil else {
            let stateHandler = stateChangeHandler
            isRunning = true
            lock.unlock()
            stateHandler?(true)
            return
        }

        let logHandler = self.logHandler
        let configuration = self.configurationOverride ?? Self.configurationFromEnvironment(logHandler: logHandler)
        if Self.shouldAutoCleanupGatewayProcesses() {
            let killed = Self.cleanupStaleManagedGatewayProcesses(logHandler: logHandler)
            if killed > 0 {
                // Give the OS a short window to release listener sockets.
                usleep(250_000)
            }
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [configuration.binaryPath]
        process.environment = Self.mergedEnvironment(
            host: configuration.host,
            port: configuration.port,
            hdcPath: configuration.hdcPath
        )

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            self?.forwardPipeOutput(handle, prefix: "gateway stdout")
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            self?.forwardPipeOutput(handle, prefix: "gateway stderr")
        }

        process.terminationHandler = { [weak self] terminatedProcess in
            self?.handleTermination(process: terminatedProcess)
        }

        do {
            try process.run()
        } catch {
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            lock.unlock()
            throw error
        }

        self.process = process
        self.stdoutPipe = stdoutPipe
        self.stderrPipe = stderrPipe
        isRunning = true
        let launchMessage = "Launched gateway process: \(configuration.binaryPath) \(configuration.host):\(configuration.port)"
        let stateHandler = self.stateChangeHandler
        lock.unlock()

        NSLog("%@", launchMessage)
        logHandler?(launchMessage)
        stateHandler?(true)
    }

    public func stop() {
        lock.lock()
        let process = self.process
        guard process != nil else {
            isRunning = false
            lock.unlock()
            return
        }

        cleanupLocked()
        lock.unlock()

        guard let process, process.isRunning else {
            isRunning = false
            return
        }

        process.terminate()
        stateChangeHandler?(false)
    }

    public var currentConfiguration: Configuration? {
        lock.lock()
        defer { lock.unlock() }

        guard process != nil else {
            return nil
        }

        return configurationOverride ?? Self.configurationFromEnvironment(logHandler: nil)
    }

    public func setLogHandler(_ handler: LogHandler?) {
        lock.lock()
        defer { lock.unlock() }
        logHandler = handler
    }

    public func setStateChangeHandler(_ handler: StateChangeHandler?) {
        lock.lock()
        defer { lock.unlock() }
        stateChangeHandler = handler
    }

    public func setConfigurationOverride(_ configuration: Configuration?) {
        lock.lock()
        defer { lock.unlock() }
        configurationOverride = configuration
    }

    public static func gatewayReleasePageURL(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL {
        let repo = {
            let raw = environment["NEPTUNE_GATEWAY_RELEASE_REPO"]?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let raw, !raw.isEmpty {
                return raw
            }
            return "linhay/neptune-gateway-swift"
        }()
        return URL(string: "https://github.com/\(repo)/releases/latest")!
    }

    private func handleTermination(process: Process) {
        lock.lock()
        if self.process === process {
            cleanupLocked()
            let terminationMessage = "Gateway process terminated with status: \(process.terminationStatus)"
            let logHandler = self.logHandler
            let stateHandler = self.stateChangeHandler
            lock.unlock()

            NSLog("%@", terminationMessage)
            logHandler?(terminationMessage)
            stateHandler?(false)
            return
        }
        lock.unlock()
    }

    private func cleanupLocked() {
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil
        stdoutPipe = nil
        stderrPipe = nil
        process = nil
        isRunning = false
    }

    private static func configurationFromEnvironment(logHandler: LogHandler?) -> Configuration {
        let runtime = DesktopRuntimeConfiguration.fromEnvironment()
        let preparedBinaryPath = ensureGatewayBinaryIfNeeded(
            runtime: runtime,
            logHandler: logHandler
        )

        return Configuration(
            binaryPath: preparedBinaryPath ?? runtime.binaryPath,
            host: runtime.host,
            port: runtime.port,
            hdcPath: runtime.hdcPath
        )
    }

    private static func mergedEnvironment(host: String, port: Int, hdcPath: String) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["NEPTUNE_HOST"] = host
        environment["NEPTUNE_PORT"] = String(port)
        environment["NEPTUNE_HDC_PATH"] = hdcPath

        let hdcDirectory = URL(fileURLWithPath: hdcPath).deletingLastPathComponent().path
        if !hdcDirectory.isEmpty {
            let currentPath = environment["PATH"] ?? ""
            let pathSegments = currentPath.split(separator: ":").map(String.init)
            if !pathSegments.contains(hdcDirectory) {
                environment["PATH"] = hdcDirectory + (currentPath.isEmpty ? "" : ":" + currentPath)
            }
        }
        return environment
    }

    private func forwardPipeOutput(_ handle: FileHandle, prefix: String) {
        let data = handle.availableData
        guard !data.isEmpty, let output = String(data: data, encoding: .utf8) else {
            return
        }

        for line in output.split(whereSeparator: \.isNewline) {
            let message = "\(prefix): \(line)"
            NSLog("%@", message)
            emitLog(message)
        }
    }

    private func emitLog(_ line: String) {
        lock.lock()
        let handler = logHandler
        lock.unlock()
        handler?(line)
    }

    private static func ensureGatewayBinaryIfNeeded(
        runtime: DesktopRuntimeConfiguration,
        logHandler: LogHandler?
    ) -> String? {
        guard runtime.binaryPath == DesktopRuntimeConfiguration.defaultBinaryPath else {
            return nil
        }
        logHandler?("[desktop] 开始自动定位 gateway CLI（默认命令 neptune）。")
        if let managedBinary = resolveManagedBinary(logHandler: logHandler) {
            return managedBinary
        }
        if let brewBinary = resolveBinaryFromBrew(logHandler: logHandler) {
            return brewBinary
        }
        if let releaseBinary = resolveBinaryFromGitHubRelease(logHandler: logHandler) {
            return releaseBinary
        }
        if let builtBinary = buildManagedGatewayBinary(logHandler: logHandler) {
            return builtBinary
        }

        logHandler?("[desktop] 未找到可用 gateway CLI，继续尝试 PATH 中的 neptune。")
        return nil
    }

    private static func resolveManagedBinary(logHandler: LogHandler?) -> String? {
        guard let gatewayRoot = DesktopRuntimeConfiguration.managedGatewayProjectRoot() else {
            logHandler?("[desktop] 未检测到本地 neptune-gateway-swift 仓库。")
            return nil
        }
        logHandler?("[desktop] 检测到本地仓库：\(gatewayRoot.path)")
        if let existing = DesktopRuntimeConfiguration.managedRepoBinaryPath(gatewayRoot: gatewayRoot) {
            logHandler?("[desktop] 使用仓库内 gateway CLI：\(existing)")
            return existing
        }
        logHandler?("[desktop] 本地仓库存在，但未发现已构建 neptune 二进制。")
        return nil
    }

    private static func resolveBinaryFromBrew(logHandler: LogHandler?) -> String? {
        guard let brewPath = resolveCommandPath("brew") else {
            logHandler?("[desktop] 未找到 Homebrew（PATH 可能缺少 /opt/homebrew/bin 或 /usr/local/bin）。")
            return nil
        }
        logHandler?("[desktop] 检测到 Homebrew：\(brewPath)")

        var formulas: [String] = []
        if let override = normalizedEnvironmentValue("NEPTUNE_BREW_FORMULA") {
            formulas.append(override)
        }
        formulas.append(contentsOf: ["neptune-gateway-swift", "neptune"])

        var seen: Set<String> = []
        let uniqueFormulas = formulas.filter { seen.insert($0).inserted }
        for formula in uniqueFormulas {
            if let path = resolveInstalledBrewBinary(brewPath: brewPath, formula: formula, logHandler: logHandler) {
                logHandler?("[desktop] 使用 Homebrew 已安装 CLI（\(formula)）：\(path)")
                return path
            }
        }

        for formula in uniqueFormulas {
            logHandler?("[desktop] Homebrew 未找到 \(formula)，尝试安装...")
            let install = runCommand(
                launchPath: brewPath,
                arguments: ["install", formula],
                currentDirectoryURL: nil
            )
            guard install.status == 0 else {
                let output = install.output.trimmingCharacters(in: .whitespacesAndNewlines)
                if !output.isEmpty {
                    logHandler?("[desktop] Homebrew 安装 \(formula) 失败：\(output)")
                }
                continue
            }
            if let path = resolveInstalledBrewBinary(brewPath: brewPath, formula: formula, logHandler: logHandler) {
                logHandler?("[desktop] Homebrew 安装成功（\(formula)）：\(path)")
                return path
            }
        }

        return nil
    }

    private static func resolveInstalledBrewBinary(
        brewPath: String,
        formula: String,
        logHandler: LogHandler?
    ) -> String? {
        let prefix = runCommand(
            launchPath: brewPath,
            arguments: ["--prefix", formula],
            currentDirectoryURL: nil
        )
        guard prefix.status == 0 else {
            let output = prefix.output.trimmingCharacters(in: .whitespacesAndNewlines)
            if !output.isEmpty {
                logHandler?("[desktop] brew --prefix \(formula) 失败：\(output)")
            }
            return nil
        }

        let path = prefix.output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else {
            return nil
        }
        let candidate = URL(fileURLWithPath: path).appendingPathComponent("bin/neptune", isDirectory: false).path
        guard FileManager.default.isExecutableFile(atPath: candidate) else {
            logHandler?("[desktop] \(formula) 已安装，但未找到可执行文件：\(candidate)")
            return nil
        }
        return candidate
    }

    private static func resolveBinaryFromGitHubRelease(logHandler: LogHandler?) -> String? {
        let repo = normalizedEnvironmentValue("NEPTUNE_GATEWAY_RELEASE_REPO") ?? "linhay/neptune-gateway-swift"
        let releaseAPI = "https://api.github.com/repos/\(repo)/releases/latest"
        let curlPath = resolveCommandPath("curl") ?? "/usr/bin/curl"
        let authArgs = githubAuthCurlArguments()
        let releaseResult = runCommand(
            launchPath: curlPath,
            arguments: authArgs + ["-fsSL", releaseAPI],
            currentDirectoryURL: nil
        )
        guard releaseResult.status == 0 else {
            let output = releaseResult.output.trimmingCharacters(in: .whitespacesAndNewlines)
            if !output.isEmpty {
                logHandler?("[desktop] 获取 GitHub Release 失败：\(output)")
            } else {
                logHandler?("[desktop] 获取 GitHub Release 失败，退出码：\(releaseResult.status)")
            }
            return nil
        }

        guard let apiData = releaseResult.output.data(using: .utf8),
              let assetURL = selectDownloadAssetURL(fromReleaseAPIData: apiData) else {
            logHandler?("[desktop] GitHub Release 未找到可下载的 neptune 二进制资产。")
            return nil
        }

        do {
            let installDir = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
                .appendingPathComponent("Library/Application Support/NeptuneDesktop/bin", isDirectory: true)
            try FileManager.default.createDirectory(at: installDir, withIntermediateDirectories: true)
            let tempURL = installDir.appendingPathComponent("neptune.tmp", isDirectory: false)
            let finalURL = installDir.appendingPathComponent("neptune", isDirectory: false)

            logHandler?("[desktop] 尝试从 GitHub Release 下载 gateway CLI...")
            let download = runCommand(
                launchPath: curlPath,
                arguments: authArgs + ["-fL", assetURL.absoluteString, "-o", tempURL.path],
                currentDirectoryURL: nil
            )
            guard download.status == 0 else {
                let output = download.output.trimmingCharacters(in: .whitespacesAndNewlines)
                if !output.isEmpty {
                    logHandler?("[desktop] 下载 Release 资产失败：\(output)")
                }
                return nil
            }

            _ = try? FileManager.default.removeItem(at: finalURL)
            try FileManager.default.moveItem(at: tempURL, to: finalURL)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: finalURL.path)
            logHandler?("[desktop] GitHub Release 下载成功：\(finalURL.path)")
            return finalURL.path
        } catch {
            return nil
        }
    }

    private static func buildManagedGatewayBinary(logHandler: LogHandler?) -> String? {
        guard let gatewayRoot = DesktopRuntimeConfiguration.managedGatewayProjectRoot() else {
            return nil
        }

        logHandler?("[desktop] 尝试本地构建 gateway CLI...")
        let result = runCommand(
            launchPath: "/usr/bin/env",
            arguments: ["swift", "build", "--product", "neptune"],
            currentDirectoryURL: gatewayRoot
        )
        if result.status == 0,
           let builtBinary = DesktopRuntimeConfiguration.managedRepoBinaryPath(gatewayRoot: gatewayRoot) {
            logHandler?("[desktop] 本地构建成功：\(builtBinary)")
            return builtBinary
        }
        let output = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        if !output.isEmpty {
            logHandler?("[desktop] 本地构建失败：\(output)")
        }
        return nil
    }

    static func selectDownloadAssetURL(fromReleaseAPIData data: Data) -> URL? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let assets = json["assets"] as? [[String: Any]] else {
            return nil
        }

        let currentArch = hostArchitectureName()
        let scoredCandidates: [(url: URL, score: Int)] = assets.compactMap { asset in
            guard let name = (asset["name"] as? String)?.lowercased(),
                  let urlString = asset["browser_download_url"] as? String,
                  let url = URL(string: urlString) else {
                return nil
            }
            guard name.hasPrefix("neptune-") else {
                return nil
            }
            guard !name.hasSuffix(".sha256"), !name.contains(".release-info") else {
                return nil
            }

            var score = 0
            if !name.contains(".") { score += 10 }
            if name.contains("macos") || name.contains("darwin") { score += 20 }
            if name.contains(currentArch) { score += 30 }
            if !(name.contains("macos") || name.contains("darwin") || name.contains("linux") || name.contains("windows")) {
                score += 5
            }
            if name.contains("linux") || name.contains("windows") {
                score -= 50
            }

            return (url, score)
        }

        return scoredCandidates.sorted { lhs, rhs in
            if lhs.score == rhs.score {
                return lhs.url.absoluteString < rhs.url.absoluteString
            }
            return lhs.score > rhs.score
        }.first?.url
    }

    private static func hostArchitectureName() -> String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "unknown"
        #endif
    }

    private static func resolveCommandPath(_ name: String) -> String? {
        let envPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let standardPrefixes = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin"
        ]
        let pathCandidates = (envPath.split(separator: ":").map(String.init) + standardPrefixes)
            .filter { !$0.isEmpty }

        var seen: Set<String> = []
        for directory in pathCandidates where seen.insert(directory).inserted {
            let candidate = URL(fileURLWithPath: directory, isDirectory: true)
                .appendingPathComponent(name, isDirectory: false)
                .path
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    private static func normalizedEnvironmentValue(_ key: String) -> String? {
        let raw = ProcessInfo.processInfo.environment[key]
        guard let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }

    private static func githubAuthCurlArguments() -> [String] {
        guard let token = normalizedEnvironmentValue("NEPTUNE_GITHUB_TOKEN") else {
            return []
        }
        return ["-H", "Authorization: Bearer \(token)", "-H", "Accept: application/vnd.github+json"]
    }

    private static func shouldAutoCleanupGatewayProcesses(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        let raw = environment["NEPTUNE_GATEWAY_AUTO_CLEANUP"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard let raw, !raw.isEmpty else {
            return true
        }
        switch raw {
        case "1", "true", "yes", "on":
            return true
        case "0", "false", "no", "off":
            return false
        default:
            return true
        }
    }

    private static func shouldPreferDefaultPort(currentPort: Int) -> Bool {
        let env = ProcessInfo.processInfo.environment
        let hasExplicitPort = !(env["NEPTUNE_PORT"]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        return !hasExplicitPort && currentPort != DesktopRuntimeConfiguration.defaultPort
    }

    private static func cleanupStaleManagedGatewayProcesses(logHandler: LogHandler?) -> Int {
        let pattern = "/neptune-gateway-swift/.build/.*/neptune"
        let pgrepResult = runCommand(
            launchPath: "/usr/bin/env",
            arguments: ["pgrep", "-f", pattern],
            currentDirectoryURL: nil
        )
        guard pgrepResult.status == 0 else {
            return 0
        }

        let currentPID = Int32(ProcessInfo.processInfo.processIdentifier)
        var pids = pgrepResult.output
            .split(whereSeparator: \.isNewline)
            .compactMap { Int32($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { $0 > 0 && $0 != currentPID }

        // Backward-compatible cleanup for legacy `neptune serve` processes occupying default port.
        let lsofResult = runCommand(
            launchPath: "/usr/bin/env",
            arguments: ["lsof", "-nP", "-iTCP:\(DesktopRuntimeConfiguration.defaultPort)", "-sTCP:LISTEN"],
            currentDirectoryURL: nil
        )
        if lsofResult.status == 0 {
            for line in lsofResult.output.split(whereSeparator: \.isNewline).dropFirst() {
                let parts = line.split(whereSeparator: \.isWhitespace)
                guard parts.count >= 2 else { continue }
                let command = String(parts[0]).lowercased()
                guard command == "neptune" else { continue }
                if let pid = Int32(parts[1]), pid > 0, pid != currentPID {
                    pids.append(pid)
                }
            }
        }
        var seen: Set<Int32> = []
        pids = pids.filter { seen.insert($0).inserted }
        guard !pids.isEmpty else {
            return 0
        }

        var killed = 0
        for pid in pids {
            let result = runCommand(
                launchPath: "/usr/bin/env",
                arguments: ["kill", "-TERM", String(pid)],
                currentDirectoryURL: nil
            )
            if result.status == 0 {
                killed += 1
            }
        }
        if killed > 0 {
            logHandler?("[desktop] 启动前已清理历史网关进程：\(killed) 个。")
        }
        return killed
    }

    private static func isPortAvailable(host: String, port: Int) -> Bool {
        guard port > 0, port <= 65535 else {
            return false
        }
        let socketFD = socket(AF_INET, SOCK_STREAM, 0)
        guard socketFD >= 0 else {
            return false
        }
        defer { Darwin.close(socketFD) }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(UInt16(port)).bigEndian
        let normalizedHost = host == "0.0.0.0" ? "127.0.0.1" : host
        guard normalizedHost.withCString({ inet_pton(AF_INET, $0, &address.sin_addr) }) == 1 else {
            return false
        }

        let connectResult = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(socketFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return connectResult != 0
    }

    private static func runCommand(
        launchPath: String,
        arguments: [String],
        currentDirectoryURL: URL?
    ) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectoryURL

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        do {
            try process.run()
            process.waitUntilExit()
            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            return (process.terminationStatus, output)
        } catch {
            return (1, error.localizedDescription)
        }
    }
}
