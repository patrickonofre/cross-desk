import Foundation
import Network

/// DTLS-PSK client (R9, R10). Reconnects automatically with exponential
/// backoff (1 s → 30 s) until `stop()` is called.
///
/// Thread-safety: state confined to `queue` (see DTLSServer).
public final class DTLSClient: @unchecked Sendable {
    private let host: String
    private let port: UInt16
    private let psk: Data
    private let deviceName: String
    private let queue = DispatchQueue(label: "crossdesk.transport.client")

    private var connection: NWConnection?
    private var handshakeDone = false
    private var stopped = true
    private var reconnectDelay = TransportTiming.reconnectMinDelay
    private var lastReceived = Date.distantPast
    private var heartbeatTimer: DispatchSourceTimer?

    /// Called on the transport queue.
    public var onEvent: (@Sendable (TransportEvent) -> Void)?

    public init(host: String, port: UInt16, psk: Data, deviceName: String) {
        self.host = host
        self.port = port
        self.psk = psk
        self.deviceName = deviceName
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
        let connection = NWConnection(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: port)!,
            using: DTLSParameters.make(psk: psk)
        )
        self.connection = connection
        handshakeDone = false

        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            self.queue.async {
                guard connection === self.connection else { return }
                switch state {
                case .ready:
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
                case let .failed(error):
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

    private func handleDatagram(_ data: Data) {
        lastReceived = Date()
        guard let decoded = try? Message.decodeAll(data) else { return }
        var inputMessages: [Message] = []

        for message in decoded {
            switch message {
            case .helloAck:
                if !handshakeDone {
                    handshakeDone = true
                    reconnectDelay = TransportTiming.reconnectMinDelay
                    startHeartbeat()
                    onEvent?(.connected(peerName: ""))
                }
            case .heartbeat:
                break
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
        let wasConnected = handshakeDone
        teardown()
        if wasConnected {
            onEvent?(.disconnected(reason: reason))
        }
        scheduleReconnect()
    }

    private func scheduleReconnect() {
        guard !stopped else { return }
        let delay = reconnectDelay
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
