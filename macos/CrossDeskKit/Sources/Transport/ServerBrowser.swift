import Foundation
import Network

/// A CrossDesk server visible on the LAN (R26). The endpoint is the Bonjour
/// service endpoint — hand it straight to `DTLSClient(endpoint:...)`; SRV/port
/// resolution happens inside the connection (R27).
public struct DiscoveredServer: Equatable, Sendable, Identifiable {
    public let name: String
    public let endpoint: NWEndpoint

    /// Bonjour instance names are unique per network (mDNS auto-renames).
    public var id: String { name }

    public init(name: String, endpoint: NWEndpoint) {
        self.name = name
        self.endpoint = endpoint
    }
}

/// Browses `_crossdesk._udp` on the local network (R26).
///
/// Emits the full current list on every change — diffing is the UI's job
/// (SwiftUI ForEach). `permissionDenied` flips when the browser reports a
/// waiting/denied state, which is how a rejected Local Network permission
/// shows up (R33) — the UI uses it to point the user at Settings.
///
/// Thread-safety: state confined to `queue` (same pattern as DTLSServer).
public final class ServerBrowser: @unchecked Sendable {
    private let queue = DispatchQueue(label: "crossdesk.transport.browser")
    private var browser: NWBrowser?
    /// Bumped on stop() — a restart scheduled before the stop must not revive
    /// the browser afterwards.
    private var generation = 0

    /// Full list, sorted by name, on the browser queue.
    public var onUpdate: (@Sendable ([DiscoveredServer]) -> Void)?
    /// true → browsing is blocked (typically Local Network permission denied);
    /// false → recovered. On the browser queue.
    public var onPermissionState: (@Sendable (_ denied: Bool) -> Void)?

    public init() {}

    public func start() {
        queue.async { [self] in
            guard browser == nil else { return }
            let browser = NWBrowser(
                for: .bonjour(type: ProtocolConstants.bonjourServiceType, domain: nil),
                using: NWParameters()
            )
            browser.browseResultsChangedHandler = { [weak self] results, _ in
                self?.publish(results)
            }
            browser.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    Log.transport.info("browser: browsing \(ProtocolConstants.bonjourServiceType, privacy: .public)")
                    self.onPermissionState?(false)
                case let .waiting(error):
                    // Local Network denied surfaces here (dns -65570 policy
                    // denial); the browser stays alive and recovers by itself
                    // if the user grants the permission in Settings.
                    Log.transport.error("browser: waiting — \(String(describing: error), privacy: .public)")
                    self.onPermissionState?(true)
                case let .failed(error):
                    Log.transport.error("browser: FAILED — \(String(describing: error), privacy: .public)")
                    self.queue.async { self.restart() }
                default:
                    break
                }
            }
            self.browser = browser
            browser.start(queue: queue)
        }
    }

    public func stop() {
        queue.async { [self] in
            generation += 1
            browser?.stateUpdateHandler = nil
            browser?.cancel()
            browser = nil
        }
    }

    // MARK: - Internals (on queue)

    private func publish(_ results: Set<NWBrowser.Result>) {
        let servers = results.compactMap { result -> DiscoveredServer? in
            guard case let .service(name, _, _, _) = result.endpoint else { return nil }
            return DiscoveredServer(name: name, endpoint: result.endpoint)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        onUpdate?(servers)
    }

    private func restart() {
        guard browser != nil else { return } // stopped meanwhile
        browser?.stateUpdateHandler = nil
        browser?.cancel()
        browser = nil
        let scheduled = generation
        queue.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self, scheduled == self.generation else { return } // stop() won the race
            // start() hops back onto the queue; the nil browser lets it run.
            self.start()
        }
    }
}
