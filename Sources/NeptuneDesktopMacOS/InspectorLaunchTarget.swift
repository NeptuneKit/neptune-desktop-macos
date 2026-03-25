import Foundation

enum InspectorLaunchTarget: Equatable {
    case local(indexURL: URL, readAccessDirectory: URL)
    case remote(URL)
}

enum InspectorLaunchTargetResolver {
    private static let remoteURL = URL(string: "http://127.0.0.1:18765/")!
    private static let inspectorURLEnvironmentKey = "NEPTUNE_INSPECTOR_URL"
    private static let distEnvironmentKey = "NEPTUNE_INSPECTOR_DIST"
    private static let defaultPackagedInspectorDirectoryURL: URL? = {
        Bundle.module.resourceURL?.appendingPathComponent("inspector", isDirectory: true)
    }()

    static func resolve(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default,
        currentDirectoryURL: URL = URL(
            fileURLWithPath: FileManager.default.currentDirectoryPath,
            isDirectory: true
        ),
        packagedInspectorDirectoryURL: URL? = defaultPackagedInspectorDirectoryURL
    ) -> InspectorLaunchTarget {
        if let inspectorURL = remoteTargetIfAvailable(environment: environment) {
            return inspectorURL
        }

        for candidateDirectory in candidateDirectories(
            environment: environment,
            currentDirectoryURL: currentDirectoryURL,
            packagedInspectorDirectoryURL: packagedInspectorDirectoryURL
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

    private static func remoteTargetIfAvailable(
        environment: [String: String]
    ) -> InspectorLaunchTarget? {
        guard let rawURL = environment[inspectorURLEnvironmentKey]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawURL.isEmpty,
              let url = URL(string: rawURL) else {
            return nil
        }

        return .remote(url)
    }

    private static func candidateDirectories(
        environment: [String: String],
        currentDirectoryURL: URL,
        packagedInspectorDirectoryURL: URL?
    ) -> [URL] {
        var candidates: [URL] = []

        if let distPath = environment[distEnvironmentKey]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !distPath.isEmpty {
            candidates.append(
                URL(fileURLWithPath: distPath, relativeTo: currentDirectoryURL).standardizedFileURL
            )
        }

        if let packagedInspectorDirectoryURL {
            candidates.append(packagedInspectorDirectoryURL.standardizedFileURL)
        }

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
