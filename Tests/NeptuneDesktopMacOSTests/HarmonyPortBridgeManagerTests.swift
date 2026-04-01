import Foundation
import Testing
@testable import NeptuneDesktopMacOS

@Suite("HarmonyPortBridgeManager")
struct HarmonyPortBridgeManagerTests {
    @Test("creates reverse port mapping for connected target")
    func createsReversePortMappingForConnectedTarget() {
        let runner = FakeShellCommandRunner(
            responses: [
                .init(
                    expectedArguments: ["hdc", "list", "targets", "-v"],
                    result: .init(status: 0, output: "127.0.0.1:5555 TCP Connected localhost\n")
                ),
                .init(
                    expectedArguments: ["hdc", "-t", "127.0.0.1:5555", "rport", "tcp:18765", "tcp:18765"],
                    result: .init(status: 0, output: "")
                )
            ]
        )
        let manager = HarmonyPortBridgeManager(
            configuration: .init(enabled: true, hdcPath: "hdc", gatewayPort: 18765, gatewayAliasPorts: [], callbackPorts: [], intervalSeconds: 5),
            commandRunner: runner
        )

        manager.reconcileNowForTesting()

        #expect(runner.recordedCalls == [
            ["hdc", "list", "targets", "-v"],
            ["hdc", "-t", "127.0.0.1:5555", "rport", "tcp:18765", "tcp:18765"]
        ])
    }

    @Test("falls back to fport when rport fails")
    func fallsBackToFportWhenRportFails() {
        let runner = FakeShellCommandRunner(
            responses: [
                .init(
                    expectedArguments: ["hdc", "list", "targets", "-v"],
                    result: .init(status: 0, output: "127.0.0.1:5555 TCP Connected localhost\n")
                ),
                .init(
                    expectedArguments: ["hdc", "-t", "127.0.0.1:5555", "rport", "tcp:18765", "tcp:18765"],
                    result: .init(status: 1, output: "Incorrect forward command")
                ),
                .init(
                    expectedArguments: ["hdc", "-t", "127.0.0.1:5555", "fport", "tcp:18765", "tcp:18765"],
                    result: .init(status: 0, output: "")
                )
            ]
        )
        let manager = HarmonyPortBridgeManager(
            configuration: .init(enabled: true, hdcPath: "hdc", gatewayPort: 18765, gatewayAliasPorts: [], callbackPorts: [], intervalSeconds: 5),
            commandRunner: runner
        )

        manager.reconcileNowForTesting()

        #expect(runner.recordedCalls == [
            ["hdc", "list", "targets", "-v"],
            ["hdc", "-t", "127.0.0.1:5555", "rport", "tcp:18765", "tcp:18765"],
            ["hdc", "-t", "127.0.0.1:5555", "fport", "tcp:18765", "tcp:18765"]
        ])
    }

    @Test("bridges callback ports together with gateway port")
    func bridgesCallbackPortsTogetherWithGatewayPort() {
        let runner = FakeShellCommandRunner(
            responses: [
                .init(
                    expectedArguments: ["hdc", "list", "targets", "-v"],
                    result: .init(status: 0, output: "127.0.0.1:5555 TCP Connected localhost\n")
                ),
                .init(
                    expectedArguments: ["hdc", "-t", "127.0.0.1:5555", "rport", "tcp:18765", "tcp:18765"],
                    result: .init(status: 0, output: "")
                ),
                .init(
                    expectedArguments: ["hdc", "-t", "127.0.0.1:5555", "fport", "tcp:28767", "tcp:28767"],
                    result: .init(status: 0, output: "")
                )
            ]
        )
        let manager = HarmonyPortBridgeManager(
            configuration: .init(enabled: true, hdcPath: "hdc", gatewayPort: 18765, gatewayAliasPorts: [], callbackPorts: [28767], intervalSeconds: 5),
            commandRunner: runner
        )

        manager.reconcileNowForTesting()

        #expect(runner.recordedCalls == [
            ["hdc", "list", "targets", "-v"],
            ["hdc", "-t", "127.0.0.1:5555", "rport", "tcp:18765", "tcp:18765"],
            ["hdc", "-t", "127.0.0.1:5555", "fport", "tcp:28767", "tcp:28767"]
        ])
    }

    @Test("bridges dynamically discovered callback ports")
    func bridgesDynamicallyDiscoveredCallbackPorts() {
        let runner = FakeShellCommandRunner(
            responses: [
                .init(
                    expectedArguments: ["hdc", "list", "targets", "-v"],
                    result: .init(status: 0, output: "127.0.0.1:5555 TCP Connected localhost\n")
                ),
                .init(
                    expectedArguments: ["hdc", "-t", "127.0.0.1:5555", "rport", "tcp:18765", "tcp:18765"],
                    result: .init(status: 0, output: "")
                ),
                .init(
                    expectedArguments: ["hdc", "-t", "127.0.0.1:5555", "fport", "tcp:41309", "tcp:41309"],
                    result: .init(status: 0, output: "")
                )
            ]
        )
        let manager = HarmonyPortBridgeManager(
            configuration: .init(enabled: true, hdcPath: "hdc", gatewayPort: 18765, gatewayAliasPorts: [], callbackPorts: [], intervalSeconds: 5),
            commandRunner: runner,
            callbackPortProvider: FakeCallbackPortProvider(ports: [41309])
        )

        manager.reconcileNowForTesting()

        #expect(runner.recordedCalls == [
            ["hdc", "list", "targets", "-v"],
            ["hdc", "-t", "127.0.0.1:5555", "rport", "tcp:18765", "tcp:18765"],
            ["hdc", "-t", "127.0.0.1:5555", "fport", "tcp:41309", "tcp:41309"]
        ])
    }

    @Test("bridges default simulator port to resolved gateway port when alias is configured")
    func bridgesDefaultSimulatorPortAliasToResolvedGatewayPort() {
        let runner = FakeShellCommandRunner(
            responses: [
                .init(
                    expectedArguments: ["hdc", "list", "targets", "-v"],
                    result: .init(status: 0, output: "127.0.0.1:5555 TCP Connected localhost\n")
                ),
                .init(
                    expectedArguments: ["hdc", "-t", "127.0.0.1:5555", "rport", "tcp:18767", "tcp:18767"],
                    result: .init(status: 0, output: "")
                ),
                .init(
                    expectedArguments: ["hdc", "-t", "127.0.0.1:5555", "rport", "tcp:18765", "tcp:18767"],
                    result: .init(status: 0, output: "")
                )
            ]
        )
        let manager = HarmonyPortBridgeManager(
            configuration: .init(
                enabled: true,
                hdcPath: "hdc",
                gatewayPort: 18767,
                gatewayAliasPorts: [18765],
                callbackPorts: [],
                intervalSeconds: 5
            ),
            commandRunner: runner
        )

        manager.reconcileNowForTesting()

        #expect(runner.recordedCalls == [
            ["hdc", "list", "targets", "-v"],
            ["hdc", "-t", "127.0.0.1:5555", "rport", "tcp:18767", "tcp:18767"],
            ["hdc", "-t", "127.0.0.1:5555", "rport", "tcp:18765", "tcp:18767"]
        ])
    }
}

private final class FakeShellCommandRunner: ShellCommandRunning, @unchecked Sendable {
    struct Response {
        let expectedArguments: [String]
        let result: ShellCommandResult
    }

    private let lock = NSLock()
    private var queue: [Response]
    private(set) var recordedCalls: [[String]] = []

    init(responses: [Response]) {
        self.queue = responses
    }

    func run(launchPath: String, arguments: [String]) -> ShellCommandResult {
        lock.lock()
        defer { lock.unlock() }

        let fullArguments = [arguments.first ?? ""] + Array(arguments.dropFirst())
        recordedCalls.append(fullArguments)
        guard !queue.isEmpty else {
            Issue.record("Unexpected command: \(arguments)")
            return ShellCommandResult(status: 1, output: "unexpected command")
        }

        let response = queue.removeFirst()
        #expect(response.expectedArguments == fullArguments)
        return response.result
    }
}

private struct FakeCallbackPortProvider: CallbackPortProviding {
    let ports: [Int]

    func callbackPorts() -> [Int] {
        ports
    }
}
