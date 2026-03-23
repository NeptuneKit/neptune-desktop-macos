import Foundation

enum InspectorLaunchTarget: Equatable {
    case local(indexURL: URL, readAccessDirectory: URL)
    case remote(URL)
}

enum InspectorLaunchTargetResolver {
    private static let remoteURL = URL(string: "http://127.0.0.1:18765/")!
    private static let distEnvironmentKey = "NEPTUNE_INSPECTOR_DIST"

    static func resolve(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default,
        currentDirectoryURL: URL = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        )
    ) -> InspectorLaunchTarget {
        for candidateDirectory in candidateDirectories(
            environment: environment,
            currentDirectoryURL: currentDirectoryURL
        ) {
            if let localTarget = localTargetIfAvailable(
                in: candidateDirectory,
                fileManager: fileManager
            ) {
                return localTarget
            }
        }

        return .remote(remoteURL)
    }

    private static func candidateDirectories(
        environment: [String: String],
        currentDirectoryURL: URL
    ) -> [URL] {
        var candidates: [URL] = []

        if let distPath = environment[distEnvironmentKey]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !distPath.isEmpty {
            candidates.append(
                URL(fileURLWithPath: distPath, relativeTo: currentDirectoryURL).standardizedFileURL
            )
        }

        let fallbackPath = URL(
            fileURLWithPath: "../neptune-inspector-h5/dist",
            relativeTo: currentDirectoryURL
        )
        candidates.append(fallbackPath.standardizedFileURL)

        return candidates
    }

    private static func localTargetIfAvailable(
        in distDirectory: URL,
        fileManager: FileManager
    ) -> InspectorLaunchTarget? {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: distDirectory.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return nil
        }

        let indexURL = distDirectory.appendingPathComponent("index.html", isDirectory: false)
        guard fileManager.fileExists(atPath: indexURL.path) else {
            return nil
        }

        return .local(
            indexURL: indexURL,
            readAccessDirectory: distDirectory
        )
    }
}
