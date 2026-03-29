import Foundation
import Testing
@testable import NeptuneDesktopMacOS

@Suite("DesktopRuntimeConfiguration")
struct DesktopRuntimeConfigurationTests {
    @Test("builds default web URL from host and port when URL override is missing")
    func buildsDefaultWebURLFromHostAndPort() {
        let configuration = DesktopRuntimeConfiguration.fromEnvironment([
            "NEPTUNE_HOST": "127.0.0.1",
            "NEPTUNE_PORT": "18765"
        ], executableURL: nil)

        #expect(configuration.binaryPath == "neptune")
        #expect(configuration.host == "127.0.0.1")
        #expect(configuration.port == 18765)
        #expect(configuration.webURL.absoluteString == "http://127.0.0.1:18765/")
    }

    @Test("uses NEPTUNE_WEB_URL when provided")
    func usesExplicitWebURLOverride() {
        let configuration = DesktopRuntimeConfiguration.fromEnvironment([
            "NEPTUNE_WEB_URL": "https://neptune.example.com/inspector"
        ], executableURL: nil)

        #expect(configuration.webURL.absoluteString == "https://neptune.example.com/inspector")
    }

    @Test("falls back to NEPTUNE_INSPECTOR_URL for backward compatibility")
    func fallsBackToLegacyInspectorURL() {
        let configuration = DesktopRuntimeConfiguration.fromEnvironment([
            "NEPTUNE_INSPECTOR_URL": "http://127.0.0.1:4173"
        ], executableURL: nil)

        #expect(configuration.webURL.absoluteString == "http://127.0.0.1:4173")
    }

    @Test("keeps default port when NEPTUNE_PORT is not numeric")
    func keepsDefaultPortWhenInvalidPort() {
        let configuration = DesktopRuntimeConfiguration.fromEnvironment([
            "NEPTUNE_PORT": "invalid"
        ], executableURL: nil)

        #expect(configuration.port == 18765)
        #expect(configuration.webURL.absoluteString == "http://127.0.0.1:18765/")
    }

    @Test("uses bundled CLI binary when available and env override is missing")
    func usesBundledBinary() throws {
        let fileManager = FileManager.default
        let root = try makeTemporaryDirectory()
        let executableURL = root
            .appendingPathComponent("NeptuneDesktopMacOS.app", isDirectory: true)
            .appendingPathComponent("Contents/MacOS/NeptuneDesktopMacOS", isDirectory: false)
        let bundledCLI = root
            .appendingPathComponent("NeptuneDesktopMacOS.app", isDirectory: true)
            .appendingPathComponent("Contents/Resources/bin/neptune", isDirectory: false)

        try fileManager.createDirectory(
            at: bundledCLI.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("#!/usr/bin/env bash\nexit 0\n".utf8).write(to: bundledCLI)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bundledCLI.path)
        try fileManager.createDirectory(
            at: executableURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        fileManager.createFile(atPath: executableURL.path, contents: Data(), attributes: nil)

        let configuration = DesktopRuntimeConfiguration.fromEnvironment(
            [:],
            executableURL: executableURL,
            fileManager: fileManager
        )

        #expect(configuration.binaryPath == bundledCLI.path)
    }

    @Test("uses managed repo CLI binary when bundled binary is unavailable")
    func usesManagedRepoBinary() throws {
        let fileManager = FileManager.default
        let root = try makeTemporaryDirectory()
        let workspace = root.appendingPathComponent("neptune-desktop-macos", isDirectory: true)
        let managedBinary = root
            .appendingPathComponent("neptune-gateway-swift/.build/arm64-apple-macosx/debug/neptune", isDirectory: false)

        try fileManager.createDirectory(at: workspace, withIntermediateDirectories: true)
        try fileManager.createDirectory(
            at: managedBinary.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("#!/usr/bin/env bash\nexit 0\n".utf8).write(to: managedBinary)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: managedBinary.path)

        let configuration = DesktopRuntimeConfiguration.fromEnvironment(
            [:],
            executableURL: nil,
            currentDirectoryURL: workspace,
            fileManager: fileManager
        )

        #expect(configuration.binaryPath == managedBinary.path)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
