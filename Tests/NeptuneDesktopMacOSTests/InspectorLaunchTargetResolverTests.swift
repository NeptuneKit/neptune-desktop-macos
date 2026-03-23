import Foundation
import Testing
@testable import NeptuneDesktopMacOS

@Suite("InspectorLaunchTargetResolver")
struct InspectorLaunchTargetResolverTests {
    @Test("prefers local dist when env path points to a packaged inspector")
    func prefersEnvProvidedDistDirectory() throws {
        let fileManager = FileManager()
        let temporaryDirectory = try makeTemporaryDirectory()
        let distDirectory = temporaryDirectory.appendingPathComponent("inspector-dist", isDirectory: true)
        try fileManager.createDirectory(at: distDirectory, withIntermediateDirectories: true)

        let indexURL = distDirectory.appendingPathComponent("index.html")
        let html = "<!doctype html><html><body>Inspector</body></html>"
        try Data(html.utf8).write(to: indexURL)

        let resolved = InspectorLaunchTargetResolver.resolve(
            environment: ["NEPTUNE_INSPECTOR_DIST": distDirectory.path],
            fileManager: fileManager
        )

        guard case let .local(resolvedIndexURL, readAccessDirectory) = resolved else {
            Issue.record("Expected local inspector launch target")
            return
        }

        #expect(resolvedIndexURL == indexURL)
        #expect(readAccessDirectory == distDirectory)
    }

    @Test("falls back to the gateway URL when no local dist exists")
    func fallsBackToRemoteURL() {
        let isolatedWorkingDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(
            at: isolatedWorkingDirectory,
            withIntermediateDirectories: true
        )

        let resolved = InspectorLaunchTargetResolver.resolve(
            environment: [:],
            fileManager: FileManager(),
            currentDirectoryURL: isolatedWorkingDirectory
        )

        guard case let .remote(url) = resolved else {
            Issue.record("Expected remote inspector launch target")
            return
        }

        #expect(url.absoluteString == "http://127.0.0.1:18765/")
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
