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
        injector.setLocalCursorLocked(false)
        injector.releaseEverything()
        transport.stop()
        onState?(.stopped)
    }

    private func wire() {
        // Return edge crossed locally (client owns its own topology, R3):
        // ask the server for control back. Repeats on further outward moves
        // until the server's LEAVE lands — natural retry over lossy UDP.
        injector.onExitEdge = { [weak self] exit in
            self?.transport.send([.leaveRequest(x: Float(exit.x), y: Float(exit.y))])
        }
        transport.onEvent = { [weak self] event in
            guard let self else { return }
            switch event {
            case .connected:
                Log.session.info("client session: connected to server")
                // Connected and unfocused: freeze this machine's arrow (R16).
                // ENTER unlocks it; LEAVE re-locks; disconnection below always
                // unlocks — worst case the lock dies with the heartbeat (6 s).
                self.injector.setLocalCursorLocked(true)
                self.onState?(.connected(peer: "servidor"))
            case .disconnected:
                Log.session.info("client session: disconnected — releasing held keys")
                // Wire gone mid-chord: synthesize key-ups so nothing stays
                // stuck (R7) and NEVER keep the cursor locked behind a dead
                // link (R16). The transport keeps reconnecting on its own.
                self.injector.setLocalCursorLocked(false)
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
