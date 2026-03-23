import Foundation

public final class GatewayLauncher {
    public private(set) var isRunning = false

    public init() {}

    public func start() throws {
        // TODO: launch or attach `neptune-gateway-swift` here.
        // The desktop shell should own the lifecycle once the real gateway package is wired in.
        isRunning = true
    }

    public func stop() {
        // TODO: stop the embedded gateway process/service here.
        isRunning = false
    }
}
