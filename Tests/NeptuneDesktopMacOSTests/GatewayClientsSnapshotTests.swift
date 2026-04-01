import Foundation
import Testing
@testable import NeptuneDesktopMacOS

@Suite("GatewayClientsSnapshot")
struct GatewayClientsSnapshotTests {
    @Test("decodes /v2/clients payload and keeps core identity fields")
    func decodesClientsPayload() throws {
        let json = """
        {
          "items": [
            {
              "platform": "harmony",
              "appId": "io.github.neptune.demo",
              "sessionId": "sim-session-alpha",
              "deviceId": "sim-device-alpha",
              "callbackEndpoint": "http://127.0.0.1:33421/v2/callback",
              "preferredTransports": ["httpCallback"],
              "lastSeenAt": "2026-03-31T23:52:17Z",
              "expiresAt": "2026-03-31T23:53:17Z",
              "ttlSeconds": 60,
              "selected": true
            }
          ]
        }
        """

        let snapshots = try GatewayClientsSnapshotParser.decodeList(from: Data(json.utf8))
        #expect(snapshots.count == 1)
        #expect(snapshots[0].platform == "harmony")
        #expect(snapshots[0].appId == "io.github.neptune.demo")
        #expect(snapshots[0].sessionId == "sim-session-alpha")
        #expect(snapshots[0].deviceId == "sim-device-alpha")
        #expect(snapshots[0].callbackEndpoint == "http://127.0.0.1:33421/v2/callback")
        #expect(snapshots[0].ttlSeconds == 60)
        #expect(snapshots[0].selected == true)
    }

    @Test("extracts callback ports and drops invalid endpoint values")
    func extractsCallbackPorts() throws {
        let json = """
        {
          "items": [
            {
              "platform": "harmony",
              "appId": "demo.one",
              "sessionId": "s1",
              "deviceId": "d1",
              "callbackEndpoint": "http://127.0.0.1:33421/v2/callback",
              "preferredTransports": ["httpCallback"],
              "lastSeenAt": "2026-03-31T23:52:17Z",
              "expiresAt": "2026-03-31T23:53:17Z",
              "ttlSeconds": 60,
              "selected": true
            },
            {
              "platform": "harmony",
              "appId": "demo.two",
              "sessionId": "s2",
              "deviceId": "d2",
              "callbackEndpoint": "http://127.0.0.1:33422/v2/callback",
              "preferredTransports": ["httpCallback"],
              "lastSeenAt": "2026-03-31T23:52:17Z",
              "expiresAt": "2026-03-31T23:53:17Z",
              "ttlSeconds": 60,
              "selected": false
            }
          ]
        }
        """

        let ports = try GatewayClientsSnapshotParser.callbackPorts(from: Data(json.utf8))
        #expect(ports == [33421, 33422])
    }
}
