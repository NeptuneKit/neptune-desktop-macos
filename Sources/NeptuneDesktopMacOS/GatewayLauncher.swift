import Foundation

public final class GatewayLauncher: @unchecked Sendable {
    public typealias LogHandler = @Sendable (String) -> Void
    public typealias StateChangeHandler = @Sendable (Bool) -> Void

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
    private var logHandler: LogHandler?
    private var stateChangeHandler: StateChangeHandler?

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
        let logHandler = self.logHandler
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

        return Self.configurationFromEnvironment()
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

    private static func configurationFromEnvironment() -> Configuration {
        let runtime = DesktopRuntimeConfiguration.fromEnvironment()

        return Configuration(
            binaryPath: runtime.binaryPath,
            host: runtime.host,
            port: runtime.port
        )
    }

    private static func mergedEnvironment(host: String, port: Int) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["NEPTUNE_HOST"] = host
        environment["NEPTUNE_PORT"] = String(port)
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
}
