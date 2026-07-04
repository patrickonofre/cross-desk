import Foundation
import Network

/// DTLS-PSK server (R9, R10). Accepts one client at a time; extra incoming
/// connections are refused while a client is active.
///
/// Optionally advertises itself over Bonjour (R25) and, when started in
/// pairing mode (PSK derived from the short token), rotates the client to a
/// long-term 128-bit secret via PAIR_SET/PAIR_ACK (R29, PROTOCOL.md §6).
///
/// Thread-safety: all mutable state is confined to `queue`; public methods
/// hop onto it. Marked `@unchecked Sendable` for that reason.
public final class DTLSServer: @unchecked Sendable {
    private let port: UInt16
    /// Current listener PSK — replaced by the rotated secret's PSK on PAIR_ACK.
    private var psk: Data
    private let advertiseName: String?
    /// True while the listener PSK comes from the short pairing token; cleared
    /// once a client acknowledges the rotated secret.
    private var pairing: Bool
    private let queue = DispatchQueue(label: "crossdesk.transport.server")

    private var listener: NWListener?
    /// Bumped on every listener (re)build — stale state callbacks from a
    /// cancelled listener compare against it and bail out.
    private var listenerGeneration = 0
    private var listenerRetries = 0
    private var connection: NWConnection?
    private var handshakeDone = false
    private var lastReceived = Date.distantPast
    private var heartbeatTimer: DispatchSourceTimer?
    /// Secret offered to the connected client, until it ACKs (idempotent
    /// resend — always this same value for the lifetime of the attempt).
    private var pendingSecret: String?
    private var pairTimer: DispatchSourceTimer?

    /// Called on the transport queue.
    public var onEvent: (@Sendable (TransportEvent) -> Void)?
    /// Pairing completed: the client persisted this secret (32 hex chars) and
    /// ACKed. Fired on the transport queue, after the listener starts
    /// rotating to the secret's PSK. Caller persists it (PROTOCOL.md §6:
    /// server persists on ACK).
    public var onPaired: (@Sendable (String) -> Void)?

    /// `advertiseName`: Bonjour instance name; nil = no discovery (R25).
    /// `pairing`: true when `psk` was derived from a short pairing token —
    /// enables the PAIR_SET rotation after the first HELLO (R29).
    public init(port: UInt16, psk: Data, advertiseName: String? = nil, pairing: Bool = false) {
        self.port = port
        self.psk = psk
        self.advertiseName = advertiseName
        self.pairing = pairing
    }

    public func start() throws {
        let listener = try makeListener()
        self.listener = listener
        listener.start(queue: queue)
        Log.transport.info("server: starting, psk fingerprint \(PairingKey.fingerprint(psk: self.psk), privacy: .public), pairing \(self.pairing, privacy: .public), advertise \(self.advertiseName ?? "off", privacy: .public)")
    }

    private func makeListener() throws -> NWListener {
        let listener = try NWListener(
            using: DTLSParameters.make(psk: psk),
            on: NWEndpoint.Port(rawValue: port)!
        )
        if let advertiseName {
            var txt = NWTXTRecord()
            txt["proto"] = String(ProtocolConstants.version)
            listener.service = NWListener.Service(
                name: advertiseName,
                type: ProtocolConstants.bonjourServiceType,
                txtRecord: txt
            )
        }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            self.queue.async { self.accept(connection) }
        }
        listenerGeneration += 1
        let generation = listenerGeneration
        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                Log.transport.info("server: listening on udp/\(self.port, privacy: .public)")
                self.queue.async { self.listenerRetries = 0 }
            case let .waiting(error):
                Log.transport.error("server: listener waiting: \(String(describing: error), privacy: .public)")
            case let .failed(error):
                Log.transport.error("server: listener FAILED: \(String(describing: error), privacy: .public)")
                self.queue.async {
                    guard generation == self.listenerGeneration else { return }
                    // A rotated listener can lose the bind race against the
                    // just-cancelled socket (EADDRINUSE) — retry briefly
                    // before declaring the server dead.
                    if self.listenerRetries > 0 {
                        self.listenerRetries -= 1
                        self.restartListenerLater()
                    } else {
                        self.onEvent?(.disconnected(reason: "listener failed: \(error)"))
                    }
                }
            default:
                break
            }
        }
        return listener
    }

    public func stop() {
        queue.async { [self] in
            // Best-effort BYE straight on the connection — send() would enqueue
            // behind this block and run after teardown.
            if handshakeDone, let connection {
                connection.send(content: Message.bye.encoded(), completion: .idempotent)
            }
            teardownConnection(notify: false)
            listener?.cancel()
            listener = nil
        }
    }

    /// Encodes and sends messages, splitting into ≤1200-byte datagrams (§1).
    public func send(_ messages: [Message]) {
        queue.async { [self] in
            guard let connection, handshakeDone else { return }
            for datagram in Self.datagrams(from: messages) {
                connection.send(content: datagram, completion: .idempotent)
            }
        }
    }

    // MARK: - Internals (on queue)

    private func accept(_ connection: NWConnection) {
        guard self.connection == nil else {
            Log.transport.info("server: refusing extra connection from \(String(describing: connection.endpoint), privacy: .public)")
            connection.cancel() // one client only (MVP)
            return
        }
        Log.transport.info("server: incoming connection from \(String(describing: connection.endpoint), privacy: .public)")
        self.connection = connection
        handshakeDone = false
        lastReceived = Date()

        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            self.queue.async {
                switch state {
                case .ready:
                    Log.transport.info("server: DTLS handshake OK, waiting HELLO")
                    self.receiveLoop(connection)
                case let .waiting(error):
                    Log.transport.error("server: conn waiting: \(String(describing: error), privacy: .public)")
                case let .failed(error):
                    Log.transport.error("server: conn FAILED: \(String(describing: error), privacy: .public)")
                    self.peerDropped(reason: "connection failed: \(error)")
                case .cancelled:
                    self.peerDropped(reason: "connection cancelled")
                default:
                    break
                }
            }
        }
        connection.start(queue: queue)

        // A peer that never completes HELLO (e.g. wrong PSK stuck in the DTLS
        // handshake) must not hold the single client slot forever.
        queue.asyncAfter(deadline: .now() + TransportTiming.handshakeTimeout) {
            [weak self, weak connection] in
            guard let self, let connection, connection === self.connection,
                  !self.handshakeDone else { return }
            self.peerDropped(reason: "handshake timeout")
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

    private func handleDatagram(_ data: Data) {
        lastReceived = Date()
        guard let decoded = try? Message.decodeAll(data) else { return } // malformed → drop datagram
        var inputMessages: [Message] = []

        for message in decoded {
            switch message {
            case let .hello(clientVersion, name):
                let negotiated = min(clientVersion, ProtocolConstants.version)
                guard negotiated >= 1 else {
                    send([.bye])
                    peerDropped(reason: "no common protocol version")
                    return
                }
                connection?.send(
                    content: Message.helloAck(protoVersion: negotiated).encoded(),
                    completion: .idempotent
                )
                if !handshakeDone {
                    handshakeDone = true
                    Log.transport.info("server: HELLO from '\(name, privacy: .public)' v\(clientVersion, privacy: .public) → connected (v\(negotiated, privacy: .public))")
                    startHeartbeat()
                    if pairing { beginPairing() }
                    onEvent?(.connected(peerName: name))
                }
            case .heartbeat:
                break // lastReceived already updated
            case .pairAck:
                completePairing()
            case .bye:
                peerDropped(reason: "peer sent BYE")
                return
            default:
                inputMessages.append(message)
            }
        }
        if !inputMessages.isEmpty {
            onEvent?(.messages(inputMessages))
        }
    }

    // MARK: - Pairing rotation (R29, PROTOCOL.md §6)

    /// Offers the long-term secret to the just-connected client. The same
    /// secret is resent every 2 s until PAIR_ACK — resends must be idempotent
    /// over lossy UDP. A new connection attempt gets a fresh secret (the
    /// previous one was never persisted anywhere: server persists on ACK).
    private func beginPairing() {
        let secret = PairingKey.generateCode()
        pendingSecret = secret
        sendPairSetOnQueue()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(
            deadline: .now() + TransportTiming.pairSetResendInterval,
            repeating: TransportTiming.pairSetResendInterval
        )
        timer.setEventHandler { [weak self] in self?.sendPairSetOnQueue() }
        timer.resume()
        pairTimer = timer
        Log.transport.info("server: pairing — offering rotated secret, fingerprint \(PairingKey.fingerprint(psk: PairingKey.psk(fromCode: secret)), privacy: .public)")
    }

    private func sendPairSetOnQueue() {
        guard let pendingSecret, let connection, handshakeDone else { return }
        connection.send(content: Message.pairSet(code: pendingSecret).encoded(), completion: .idempotent)
    }

    /// PAIR_ACK: the client persisted the secret — now (and only now) the
    /// server adopts it (PROTOCOL.md §6) and rotates the listener so every
    /// future handshake requires the secret. The active connection keeps its
    /// already-derived DTLS keys and survives the listener swap.
    private func completePairing() {
        guard let secret = pendingSecret else { return } // duplicate ACK
        pendingSecret = nil
        pairTimer?.cancel()
        pairTimer = nil
        pairing = false
        psk = PairingKey.psk(fromCode: secret)
        Log.transport.info("server: PAIR_ACK — rotating listener to secret PSK")
        listenerRetries = 5
        restartListenerNow()
        onPaired?(secret)
    }

    private func restartListenerNow() {
        if let listener {
            listener.stateUpdateHandler = nil
            listener.cancel()
            self.listener = nil
        }
        do {
            let listener = try makeListener()
            self.listener = listener
            listener.start(queue: queue)
        } catch {
            Log.transport.error("server: listener rebuild threw \(String(describing: error), privacy: .public)")
            if listenerRetries > 0 {
                listenerRetries -= 1
                restartListenerLater()
            }
        }
    }

    private func restartListenerLater() {
        queue.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.restartListenerNow()
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
                self.peerDropped(reason: "peer timeout")
                return
            }
            connection.send(content: Message.heartbeat.encoded(), completion: .idempotent)
        }
        timer.resume()
        heartbeatTimer = timer
    }

    private func peerDropped(reason: String) {
        Log.transport.info("server: peer dropped — \(reason, privacy: .public)")
        let wasConnected = handshakeDone || connection != nil
        teardownConnection(notify: false)
        if wasConnected {
            onEvent?(.disconnected(reason: reason))
        }
    }

    private func teardownConnection(notify: Bool) {
        heartbeatTimer?.cancel()
        heartbeatTimer = nil
        // Unacknowledged pairing dies with the connection — the next attempt
        // starts over with a fresh secret (PROTOCOL.md §6 failure table).
        pairTimer?.cancel()
        pairTimer = nil
        pendingSecret = nil
        if let connection {
            connection.stateUpdateHandler = nil
            connection.cancel()
        }
        connection = nil
        handshakeDone = false
        if notify {
            onEvent?(.disconnected(reason: "stopped"))
        }
    }

    static func datagrams(from messages: [Message]) -> [Data] {
        var result: [Data] = []
        var current = Data()
        for message in messages {
            let encoded = message.encoded()
            if !current.isEmpty, current.count + encoded.count > ProtocolConstants.maxDatagramSize {
                result.append(current)
                current = Data()
            }
            current.append(encoded)
        }
        if !current.isEmpty {
            result.append(current)
        }
        return result
    }
}
