import Foundation

/// Client orchestration (R6–R8): receives remote input over DTLS and injects
/// it locally; releases everything held on LEAVE/disconnect (R7).
public final class ClientSession: @unchecked Sendable {
    private let transport: DTLSClient
    private let injector: InputInjector

    /// Called on the transport queue.
    public var onState: (@Sendable (SessionState) -> Void)?

    public init(
        host: String,
        port: UInt16,
        pairingCode: String,
        deviceName: String,
        injector: InputInjector = InputInjector()
    ) {
        self.transport = DTLSClient(
            host: host,
            port: port,
            psk: PairingKey.psk(fromCode: pairingCode),
            deviceName: deviceName
        )
        self.injector = injector
        wire()
    }

    public func start() {
        transport.start()
        onState?(.waitingPeer)
    }

    public func stop() {
        injector.releaseEverything()
        transport.stop()
        onState?(.stopped)
    }

    private func wire() {
        transport.onEvent = { [weak self] event in
            guard let self else { return }
            switch event {
            case .connected:
                self.onState?(.connected(peer: "servidor"))
            case .disconnected:
                // Wire gone mid-chord: synthesize key-ups so nothing stays
                // stuck (R7). The transport keeps reconnecting on its own.
                self.injector.releaseEverything()
                self.onState?(.waitingPeer)
            case let .messages(messages):
                // Injected directly from the transport queue. CGEventPost off
                // the main thread = design.md uncertainty T2; if UAT shows
                // issues, bounce these to the main queue.
                for message in messages {
                    self.injector.apply(message)
                }
            }
        }
    }
}
