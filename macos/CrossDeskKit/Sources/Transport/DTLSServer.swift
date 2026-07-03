import Foundation
import Network

/// DTLS-PSK server (R9, R10). Accepts one client at a time; extra incoming
/// connections are refused while a client is active.
///
/// Thread-safety: all mutable state is confined to `queue`; public methods
/// hop onto it. Marked `@unchecked Sendable` for that reason.
public final class DTLSServer: @unchecked Sendable {
    private let port: UInt16
    private let psk: Data
    private let queue = DispatchQueue(label: "crossdesk.transport.server")

    private var listener: NWListener?
    private var connection: NWConnection?
    private var handshakeDone = false
    private var lastReceived = Date.distantPast
    private var heartbeatTimer: DispatchSourceTimer?

    /// Called on the transport queue.
    public var onEvent: (@Sendable (TransportEvent) -> Void)?

    public init(port: UInt16, psk: Data) {
        self.port = port
        self.psk = psk
    }

    public func start() throws {
        let listener = try NWListener(
            using: DTLSParameters.make(psk: psk),
            on: NWEndpoint.Port(rawValue: port)!
        )
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            self.queue.async { self.accept(connection) }
        }
        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                Log.transport.info("server: listening on udp/\(self.port, privacy: .public)")
            case let .waiting(error):
                Log.transport.error("server: listener waiting: \(String(describing: error), privacy: .public)")
            case let .failed(error):
                Log.transport.error("server: listener FAILED: \(String(describing: error), privacy: .public)")
                self.queue.async {
                    self.onEvent?(.disconnected(reason: "listener failed: \(error)"))
                }
            default:
                break
            }
        }
        self.listener = listener
        listener.start(queue: queue)
        Log.transport.info("server: starting, psk fingerprint \(PairingKey.fingerprint(psk: self.psk), privacy: .public)")
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
                    onEvent?(.connected(peerName: name))
                }
            case .heartbeat:
                break // lastReceived already updated
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
