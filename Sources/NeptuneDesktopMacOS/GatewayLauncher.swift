import Foundation

public final class GatewayLauncher: @unchecked Sendable {
    public struct Configuration: Sendable {
        public let binaryPath: String
        public let host: String
        public let port: Int

        public init(
            binaryPath: String,
            host: String,
            port: Int
        ) {
            self.binaryPath = binaryPath
            self.host = host
            self.port = port
        }
    }

    public private(set) var isRunning = false

    private let lock = NSLock()
    private var process: Process?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?

    public init() {}

    deinit {
        stop()
    }

    public func start() throws {
        lock.lock()
        defer { lock.unlock() }

        guard process == nil else {
            isRunning = true
            return
        }

        let configuration = Self.configurationFromEnvironment()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [configuration.binaryPath]
        process.environment = Self.mergedEnvironment(
            host: configuration.host,
            port: configuration.port
        )

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            Self.forwardPipeOutput(handle, prefix: "gateway stdout")
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            Self.forwardPipeOutput(handle, prefix: "gateway stderr")
        }

        process.terminationHandler = { [weak self] terminatedProcess in
            self?.handleTermination(process: terminatedProcess)
        }

        do {
            try process.run()
        } catch {
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            throw error
        }

        self.process = process
        self.stdoutPipe = stdoutPipe
        self.stderrPipe = stderrPipe
        isRunning = true
        NSLog("Launched gateway process: %@ %@", configuration.binaryPath, "\(configuration.host):\(configuration.port)")
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
    }

    public var currentConfiguration: Configuration? {
        lock.lock()
        defer { lock.unlock() }

        guard process != nil else {
            return nil
        }

        return Self.configurationFromEnvironment()
    }

    private func handleTermination(process: Process) {
        lock.lock()
        defer { lock.unlock() }

        if self.process === process {
            cleanupLocked()
            NSLog("Gateway process terminated with status: %d", process.terminationStatus)
        }
    }

    private func cleanupLocked() {
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil
        stdoutPipe = nil
        stderrPipe = nil
        process = nil
        isRunning = false
    }

    private static func configurationFromEnvironment() -> Configuration {
        let environment = ProcessInfo.processInfo.environment
        let binaryPath = environment["NEPTUNE_GATEWAY_BIN"]
            ?? "neptune-gateway"
        let host = environment["NEPTUNE_HOST"]
            ?? "127.0.0.1"
        let portValue = environment["NEPTUNE_PORT"]
            ?? "18765"
        let port = Int(portValue) ?? 18765

        return Configuration(
            binaryPath: binaryPath,
            host: host,
            port: port
        )
    }

    private static func mergedEnvironment(host: String, port: Int) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["NEPTUNE_HOST"] = host
        environment["NEPTUNE_PORT"] = String(port)
        return environment
    }

    private static func forwardPipeOutput(_ handle: FileHandle, prefix: String) {
        let data = handle.availableData
        guard !data.isEmpty, let output = String(data: data, encoding: .utf8) else {
            return
        }

        for line in output.split(whereSeparator: \.isNewline) {
            NSLog("%@: %@", prefix, String(line))
        }
    }
}
