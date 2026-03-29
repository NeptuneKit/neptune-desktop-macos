import Foundation

struct DesktopRuntimeConfiguration: Sendable, Equatable {
    static let defaultBinaryPath = "neptune"
    static let defaultHost = "127.0.0.1"
    static let defaultPort = 18765

    let binaryPath: String
    let host: String
    let port: Int
    let webURL: URL

    static func fromEnvironment(
        _ environment: [String: String] = ProcessInfo.processInfo.environment,
        executableURL: URL? = Bundle.main.executableURL,
        currentDirectoryURL: URL = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        ),
        fileManager: FileManager = .default
    ) -> DesktopRuntimeConfiguration {
        let binaryPath = normalized(environment["NEPTUNE_GATEWAY_BIN"])
            ?? bundledBinaryPath(executableURL: executableURL, fileManager: fileManager)
            ?? managedRepoBinaryPath(currentDirectoryURL: currentDirectoryURL, fileManager: fileManager)
            ?? defaultBinaryPath
        let host = normalized(environment["NEPTUNE_HOST"]) ?? defaultHost

        let portString = normalized(environment["NEPTUNE_PORT"]) ?? String(defaultPort)
        let port = Int(portString) ?? defaultPort

        let explicitWebURL = normalized(environment["NEPTUNE_WEB_URL"])
        let legacyInspectorURL = normalized(environment["NEPTUNE_INSPECTOR_URL"])

        let resolvedWebURL = [explicitWebURL, legacyInspectorURL]
            .compactMap { $0 }
            .compactMap(URL.init(string:))
            .first
            ?? URL(string: "http://\(host):\(port)/")!

        return DesktopRuntimeConfiguration(
            binaryPath: binaryPath,
            host: host,
            port: port,
            webURL: resolvedWebURL
        )
    }

    private static func normalized(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private static func bundledBinaryPath(
        executableURL: URL?,
        fileManager: FileManager
    ) -> String? {
        guard let executableURL else {
            return nil
        }

        let macOSDirectory = executableURL.deletingLastPathComponent()
        let resourcesDirectory = macOSDirectory
            .deletingLastPathComponent()
            .appendingPathComponent("Resources", isDirectory: true)
        let binaryURL = resourcesDirectory
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("neptune", isDirectory: false)

        guard fileManager.isExecutableFile(atPath: binaryURL.path) else {
            return nil
        }

        return binaryURL.path
    }

    private static func managedRepoBinaryPath(
        currentDirectoryURL: URL,
        fileManager: FileManager
    ) -> String? {
        let gatewayRoot = currentDirectoryURL
            .appendingPathComponent("../neptune-gateway-swift", isDirectory: true)
            .standardizedFileURL
        let buildRoot = gatewayRoot.appendingPathComponent(".build", isDirectory: true)
        guard fileManager.fileExists(atPath: buildRoot.path) else {
            return nil
        }

        let candidates = [
            buildRoot.appendingPathComponent("arm64-apple-macosx/debug/neptune"),
            buildRoot.appendingPathComponent("arm64-apple-macosx/release/neptune"),
            buildRoot.appendingPathComponent("x86_64-apple-macosx/debug/neptune"),
            buildRoot.appendingPathComponent("x86_64-apple-macosx/release/neptune"),
        ]

        for candidate in candidates where fileManager.isExecutableFile(atPath: candidate.path) {
            return candidate.path
        }
        return nil
    }
}
