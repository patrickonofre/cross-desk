import Foundation
import Network

/// Detects whether the current default network path is using a VPN/virtual
/// interface. Network.framework has no dedicated VPN case — `utun` tunnels
/// are classified under `.other`, same as any unknown virtual interface
/// (`NetworkInfo` already ranks physical interfaces first for the same
/// reason). UI-only signal, never a security decision.
public final class VPNMonitor: @unchecked Sendable {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "crossdesk.transport.vpnmonitor")

    /// Called on the monitor's internal queue whenever VPN presence changes
    /// (same convention as `ServerBrowser.onUpdate` — the caller hops to
    /// `@MainActor` itself).
    public var onChange: (@Sendable (Bool) -> Void)?

    public init() {}

    public func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            self?.onChange?(path.usesInterfaceType(.other))
        }
        monitor.start(queue: queue)
    }

    public func stop() {
        monitor.cancel()
    }
}
