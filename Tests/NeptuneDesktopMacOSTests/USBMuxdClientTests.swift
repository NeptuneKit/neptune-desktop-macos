import Darwin
import Foundation
import Testing
@testable import NeptuneDesktopMacOS

@Suite("USBMuxdClient")
struct USBMuxdClientTests {
    @Test("connect plist request encodes PortNumber using network byte order")
    func connectRequestUsesNetworkByteOrderPort() throws {
        let payload = try USBMuxdCodec.makePlistPayload(
            messageType: "Connect",
            payload: [
                "DeviceID": 123,
                "PortNumber": USBMuxdCodec.usbmuxPortNumber(8100)
            ]
        )
        let plist = try #require(
            try PropertyListSerialization.propertyList(from: payload, options: [], format: nil) as? [String: Any]
        )
        let portNumber = try #require(plist["PortNumber"] as? NSNumber)
        #expect(portNumber.uint16Value == UInt16((8100 << 8) | (8100 >> 8)))
    }

    @Test("connect handshake succeeds when usbmuxd replies Number=0")
    func connectHandshakeSuccess() throws {
        var pair = [Int32](repeating: -1, count: 2)
        #expect(socketpair(AF_UNIX, SOCK_STREAM, 0, &pair) == 0)
        defer {
            if pair[0] >= 0 { close(pair[0]) }
            if pair[1] >= 0 { close(pair[1]) }
        }

        let serverFD = pair[1]
        let connectorFD = pair[0]
        pair[0] = -1
        pair[1] = -1

        let serverThread = Thread {
            do {
                let packet = try USBMuxdCodec.readPacket(from: serverFD)
                let plist = try #require(try PropertyListSerialization.propertyList(
                    from: packet.payload,
                    options: [],
                    format: nil
                ) as? [String: Any])
                #expect(plist["MessageType"] as? String == "Connect")
                #expect((plist["DeviceID"] as? NSNumber)?.intValue == 42)

                let responsePayload = try USBMuxdCodec.makePlistPayload(
                    messageType: "Result",
                    payload: ["Number": 0]
                )
                let response = USBMuxdPacket(
                    length: UInt32(16 + responsePayload.count),
                    version: USBMuxdProtocol.plist.rawValue,
                    messageType: USBMuxdMessageType.plistPayload.rawValue,
                    tag: packet.tag,
                    payload: responsePayload
                )
                try USBMuxdCodec.writePacket(response, to: serverFD)
            } catch {
                Issue.record("Server thread failed: \(error)")
            }
            close(serverFD)
        }
        serverThread.start()

        let client = USBMuxdClient(
            socketPath: "/var/run/usbmuxd",
            connector: { _ in connectorFD }
        )
        let tunnel = try client.connectToDevice(deviceID: 42, port: 8100)
        let descriptor = tunnel.fileDescriptor
        #expect(fcntl(descriptor, F_GETFD) != -1)
        tunnel.close()
        _ = serverThread
    }

    @Test("connect handshake throws when usbmuxd Number is non-zero")
    func connectHandshakeFailure() throws {
        var pair = [Int32](repeating: -1, count: 2)
        #expect(socketpair(AF_UNIX, SOCK_STREAM, 0, &pair) == 0)
        defer {
            if pair[0] >= 0 { close(pair[0]) }
            if pair[1] >= 0 { close(pair[1]) }
        }

        let serverFD = pair[1]
        let connectorFD = pair[0]
        pair[0] = -1
        pair[1] = -1

        let serverThread = Thread {
            do {
                let packet = try USBMuxdCodec.readPacket(from: serverFD)
                let responsePayload = try USBMuxdCodec.makePlistPayload(
                    messageType: "Result",
                    payload: ["Number": 3]
                )
                let response = USBMuxdPacket(
                    length: UInt32(16 + responsePayload.count),
                    version: USBMuxdProtocol.plist.rawValue,
                    messageType: USBMuxdMessageType.plistPayload.rawValue,
                    tag: packet.tag,
                    payload: responsePayload
                )
                try USBMuxdCodec.writePacket(response, to: serverFD)
            } catch {
                Issue.record("Server thread failed: \(error)")
            }
            close(serverFD)
        }
        serverThread.start()

        let client = USBMuxdClient(
            socketPath: "/var/run/usbmuxd",
            connector: { _ in connectorFD }
        )

        do {
            _ = try client.connectToDevice(deviceID: 7, port: 8100)
            Issue.record("Expected connectToDevice to throw when Number != 0")
        } catch let error as USBMuxdError {
            switch error {
            case .connectRejected(code: let code):
                #expect(code == 3)
            default:
                Issue.record("Unexpected USBMuxdError: \(error)")
            }
        }
        _ = serverThread
    }
}
