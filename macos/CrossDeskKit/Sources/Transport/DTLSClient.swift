import Foundation
import Network

/// DTLS-PSK client (R9, R10). Reconnects automatically with exponential
/// backoff (1 s → 30 s) until `stop()` is called.
///
/// Connects to a plain host:port or to a Bonjour endpoint discovered via
/// `ServerBrowser` (R27 — SRV resolution is the framework's job). When given
/// a fallback PSK, alternates credentials between handshake timeouts (R30:
/// paired secret first, short token as fallback) and handles the PAIR_SET
/// rotation (R29, PROTOCOL.md §6).
///
/// Thread-safety: state confined to `queue` (see DTLSServer).
public final class DTLSClient: @unchecked Sendable {
    private let endpoint: NWEndpoint
    private let deviceName: String
    /// Credentials in preference order (primary first). One entry = today's
    /// fixed-PSK behavior; two = paired secret + pairing-token fallback.
    private let psks: [Data]
    private var activePSKIndex = 0
    private let queue = DispatchQueue(label: "crossdesk.transport.client")

    private var connection: NWConnection?
    private var handshakeDone = false
    private var stopped = true
    private var reconnectDelay = TransportTiming.reconnectMinDelay
    private var lastReceived = Date.distantPast
    private var heartbeatTimer: DispatchSourceTimer?

    /// Called on the transport queue.
    public var onEvent: (@Sendable (TransportEvent) -> Void)?
    /// PAIR_SET arrived: persist this secret (32 hex chars) BEFORE any reply
    /// hits the wire — the client must never ACK a secret it hasn't stored
    /// (PROTOCOL.md §6). Fired on the transport queue; may repeat with the
    /// same value if the ACK was lost (persisting again is harmless).
    public var onPairSet: (@Sendable (String) -> Void)?

    public init(endpoint: NWEndpoint, psk: Data, fallbackPSK: Data? = nil, deviceName: String) {
        self.endpoint = endpoint
        self.psks = [psk] + (fallbackPSK.map { [$0] } ?? [])
        self.deviceName = deviceName
    }

    public convenience init(host: String, port: UInt16, psk: Data, fallbackPSK: Data? = nil, deviceName: String) {
        self.init(
            endpoint: .hostPort(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!),
            psk: psk,
            fallbackPSK: fallbackPSK,
            deviceName: deviceName
        )
    }

    public func start() {
        queue.async { [self] in
            guard stopped else { return }
            stopped = false
            reconnectDelay = TransportTiming.reconnectMinDelay
            connect()
        }
    }

    public func stop() {
        queue.async { [self] in
            stopped = true
            if handshakeDone {
                connection?.send(content: Message.bye.encoded(), completion: .idempotent)
            }
            teardown()
        }
    }

    public func send(_ messages: [Message]) {
        queue.async { [self] in
            guard let connection, handshakeDone else { return }
            for datagram in DTLSServer.datagrams(from: messages) {
                connection.send(content: datagram, completion: .idempotent)
            }
        }
    }

    // MARK: - Internals (on queue)

    private func connect() {
        guard !stopped else { return }
        let psk = psks[activePSKIndex]
        Log.transport.info("client: connecting to \(String(describing: self.endpoint), privacy: .public), psk fingerprint \(PairingKey.fingerprint(psk: psk), privacy: .public) (credential \(self.activePSKIndex, privacy: .public))")
        let connection = NWConnection(to: endpoint, using: DTLSParameters.make(psk: psk))
        self.connection = connection
        handshakeDone = false

        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            self.queue.async {
                guard connection === self.connection else { return }
                switch state {
                case .ready:
                    Log.transport.info("client: DTLS handshake OK → sending HELLO")
                    self.lastReceived = Date()
                    // DTLS is up; introduce ourselves (PROTOCOL.md §3).
                    connection.send(
                        content: Message.hello(
                            protoVersion: ProtocolConstants.version,
                            name: self.deviceName
                        ).encoded(),
                        completion: .idempotent
                    )
                    self.receiveLoop(connection)
                case let .waiting(error):
                    // Typical here: server unreachable, firewall dropping UDP,
                    // wrong IP. The handshake timeout will recycle the attempt.
                    Log.transport.error("client: waiting — \(String(describing: error), privacy: .public)")
                case let .failed(error):
                    Log.transport.error("client: conn FAILED: \(String(describing: error), privacy: .public)")
                    self.connectionLost(reason: "connection failed: \(error)")
                case .cancelled:
                    break // triggered by our own teardown
                default:
                    break
                }
            }
        }
        connection.start(queue: queue)

        // Connections to a dead/rebinding server can sit in .preparing forever;
        // give the DTLS + HELLO/HELLO_ACK exchange a bounded window, then let
        // the backoff loop try again (R10).
        queue.asyncAfter(deadline: .now() + TransportTiming.handshakeTimeout) {
            [weak self, weak connection] in
            guard let self, let connection, connection === self.connection,
                  !self.handshakeDone else { return }
            self.connectionLost(reason: "handshake timeout")
        }
    }

    private func receiveLoop(_ connection: NWConnection) {
        connection.receiveMessage { [weak self] data, _, _, error in
            guard let self else { return }
            self.queue.async {
                guard connection === self.connection else { return }
                if let data, !data.isEmpty {
                    self.handleDatagram(data)
                }
                if error == nil {
                    self.receiveLoop(connection)
                }
            }
        }
    }

    // Internal (not private) so tests can exercise PAIR_SET dedup semantics
    // without a live connection (the ACK send is nil-safe).
    func handleDatagram(_ data: Data) {
        lastReceived = Date()
        guard let decoded = try? Message.decodeAll(data) else { return }
        var inputMessages: [Message] = []

        for message in decoded {
            switch message {
            case .helloAck:
                if !handshakeDone {
                    handshakeDone = true
                    Log.transport.info("client: HELLO_ACK received → connected")
                    reconnectDelay = TransportTiming.reconnectMinDelay
                    startHeartbeat()
                    onEvent?(.connected(peerName: ""))
                }
            case .heartbeat:
                break
            case let .pairSet(code):
                // Persist-then-ACK, in this order (PROTOCOL.md §6). Duplicate
                // SET (our ACK got lost) → same secret persisted again + re-ACK.
                Log.transport.info("client: PAIR_SET received → persisting rotated secret + ACK")
                onPairSet?(code)
                connection?.send(content: Message.pairAck.encoded(), completion: .idempotent)
            case .bye:
                connectionLost(reason: "peer sent BYE")
                return
            default:
                inputMessages.append(message)
            }
        }
        if !inputMessages.isEmpty {
            onEvent?(.messages(inputMessages))
        }
    }

    private func startHeartbeat() {
        heartbeatTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(
            deadline: .now() + TransportTiming.heartbeatInterval,
            repeating: TransportTiming.heartbeatInterval
        )
        timer.setEventHandler { [weak self] in
            guard let self, let connection = self.connection else { return }
            if Date().timeIntervalSince(self.lastReceived) > TransportTiming.peerTimeout {
                self.connectionLost(reason: "peer timeout")
                return
            }
            connection.send(content: Message.heartbeat.encoded(), completion: .idempotent)
        }
        timer.resume()
        heartbeatTimer = timer
    }

    private func connectionLost(reason: String) {
        Log.transport.info("client: connection lost — \(reason, privacy: .public)")
        let wasConnected = handshakeDone
        // Handshake never completed → likely wrong PSK on this credential
        // (paired secret the server has since forgotten, R30). Alternate to
        // the other credential for the next attempt; harmless when the real
        // cause is a dead server (both time out the same way).
        if !wasConnected, reason == "handshake timeout", psks.count > 1 {
            activePSKIndex = (activePSKIndex + 1) % psks.count
            Log.transport.info("client: switching to credential \(self.activePSKIndex, privacy: .public) for next attempt")
        }
        teardown()
        if wasConnected {
            onEvent?(.disconnected(reason: reason))
        }
        scheduleReconnect()
    }

    private func scheduleReconnect() {
        guard !stopped else { return }
        let delay = reconnectDelay
        Log.transport.info("client: retrying in \(Int(delay), privacy: .public)s")
        reconnectDelay = min(reconnectDelay * 2, TransportTiming.reconnectMaxDelay)
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.connect()
        }
    }

    private func teardown() {
        heartbeatTimer?.cancel()
        heartbeatTimer = nil
        if let connection {
            connection.stateUpdateHandler = nil
            connection.cancel()
        }
        connection = nil
        handshakeDone = false
    }
}
