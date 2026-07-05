import Foundation
import Network

/// TLS-PSK parameters for the file channel (PROTOCOL.md §8, proved by spike
/// T40): same PSK API as the DTLS side, pinned to TLS 1.2 over TCP.
enum FileChannelParameters {
    static func make(psk: Data) -> NWParameters {
        let tlsOptions = NWProtocolTLS.Options()
        let sec = tlsOptions.securityProtocolOptions

        let pskDispatchData = psk.withUnsafeBytes { DispatchData(bytes: $0) }
        let identityDispatchData = Data(PairingKey.pskIdentity.utf8)
            .withUnsafeBytes { DispatchData(bytes: $0) }
        sec_protocol_options_add_pre_shared_key(
            sec,
            pskDispatchData as __DispatchData,
            identityDispatchData as __DispatchData
        )
        // PSK cipher suites are TLS 1.2-only; pin TLS 1.2 on both ends.
        sec_protocol_options_append_tls_ciphersuite(
            sec, tls_ciphersuite_t(rawValue: UInt16(TLS_PSK_WITH_AES_128_GCM_SHA256))!
        )
        sec_protocol_options_set_min_tls_protocol_version(sec, .TLSv12)
        sec_protocol_options_set_max_tls_protocol_version(sec, .TLSv12)

        return NWParameters(tls: tlsOptions, tcp: NWProtocolTCP.Options())
    }
}

public enum FileChannelEvent: Sendable {
    /// TLS handshake completed — the channel can carry frames.
    case ready
    case messages([FileChannelMessage])
    /// Terminal: clean close, failure, timeout or protocol error.
    case closed(reason: String)
}

public enum FileChannelSendError: Error {
    case closed
}

/// One file-channel connection — one transfer (PROTOCOL.md §8). Opened by the
/// client (`init(host:port:psk:)`) or accepted by `FileChannelListener`.
///
/// Thread-safety: all mutable state is confined to `queue`; public methods
/// hop onto it. Marked `@unchecked Sendable` for that reason.
public final class FileChannelConnection: @unchecked Sendable {
    private let connection: NWConnection
    private let queue: DispatchQueue
    private var decoder = FileChannelDecoder()
    private var ready = false
    private var closed = false

    /// Called on the connection queue. Set before `start()`.
    public var onEvent: (@Sendable (FileChannelEvent) -> Void)?

    /// Client side: connect to the server's file channel (TCP, same numeric
    /// port as the UDP listener).
    public convenience init(host: String, port: UInt16, psk: Data) {
        let connection = NWConnection(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: port)!,
            using: FileChannelParameters.make(psk: psk)
        )
        self.init(
            wrapping: connection,
            queue: DispatchQueue(label: "crossdesk.transport.filechannel")
        )
    }

    /// Listener side: wrap an accepted connection.
    init(wrapping connection: NWConnection, queue: DispatchQueue) {
        self.connection = connection
        self.queue = queue
    }

    public func start() {
        queue.async { [self] in startOnQueue() }
    }

    /// Sends one frame. `completion` fires after the frame is handed to the
    /// TCP stack — awaiting it between chunks is the sender's backpressure
    /// (design D5).
    public func send(
        _ message: FileChannelMessage,
        completion: (@Sendable (Error?) -> Void)? = nil
    ) {
        queue.async { [self] in
            guard !closed else {
                completion?(FileChannelSendError.closed)
                return
            }
            connection.send(
                content: message.encoded(),
                completion: .contentProcessed { error in completion?(error) }
            )
        }
    }

    public func close() {
        queue.async { [self] in closeOnQueue(reason: "closed locally", notify: false) }
    }

    // MARK: - Internals (on queue)

    private func startOnQueue() {
        guard !closed else { return }
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            self.queue.async {
                switch state {
                case .ready:
                    guard !self.ready, !self.closed else { return }
                    self.ready = true
                    Log.transport.info("filechannel: TLS handshake OK")
                    self.receiveLoop()
                    self.onEvent?(.ready)
                case let .failed(error):
                    self.closeOnQueue(reason: "connection failed: \(error)")
                case .cancelled:
                    self.closeOnQueue(reason: "connection cancelled")
                default:
                    break
                }
            }
        }
        connection.start(queue: queue)

        // A TCP connection stuck in .preparing (dead port, PSK mismatch
        // hanging the handshake) never fails on its own — same lesson as the
        // DTLS transport.
        queue.asyncAfter(deadline: .now() + TransportTiming.handshakeTimeout) { [weak self] in
            guard let self, !self.ready, !self.closed else { return }
            self.closeOnQueue(reason: "handshake timeout")
        }
    }

    private func receiveLoop() {
        connection.receive(
            minimumIncompleteLength: 1,
            maximumLength: FileChannelConstants.maxChunkSize + 5
        ) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            self.queue.async {
                guard !self.closed else { return }
                if let data, !data.isEmpty {
                    do {
                        let messages = try self.decoder.feed(data)
                        if !messages.isEmpty {
                            self.onEvent?(.messages(messages))
                        }
                    } catch {
                        // Malformed frame is fatal on this channel (§8).
                        self.closeOnQueue(reason: "protocol error: \(error)")
                        return
                    }
                }
                if isComplete {
                    self.closeOnQueue(reason: "peer closed")
                } else if let error {
                    self.closeOnQueue(reason: "receive error: \(error)")
                } else {
                    self.receiveLoop()
                }
            }
        }
    }

    private func closeOnQueue(reason: String, notify: Bool = true) {
        guard !closed else { return }
        closed = true
        Log.transport.info("filechannel: closed — \(reason, privacy: .public)")
        connection.stateUpdateHandler = nil
        connection.cancel()
        if notify {
            onEvent?(.closed(reason: reason))
        }
    }
}

/// Accepts file-channel connections while the server is active (§8: TCP on
/// the same numeric port as the UDP listener). Each accepted connection is
/// handed over NOT yet started — the consumer sets `onEvent`, calls `start()`
/// and MUST keep a strong reference until `.closed` (the listener does not
/// retain accepted connections). Concurrent connections are allowed (a push
/// and a request may overlap), one per transfer.
public final class FileChannelListener: @unchecked Sendable {
    private let port: UInt16
    private let psk: Data
    private let queue = DispatchQueue(label: "crossdesk.transport.filechannel.listener")
    private var listener: NWListener?

    /// Fired on the listener queue.
    public var onConnection: (@Sendable (FileChannelConnection) -> Void)?
    public var onFailed: (@Sendable (String) -> Void)?

    public init(port: UInt16, psk: Data) {
        self.port = port
        self.psk = psk
    }

    public func start() throws {
        let listener = try NWListener(
            using: FileChannelParameters.make(psk: psk),
            on: NWEndpoint.Port(rawValue: port)!
        )
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else {
                connection.cancel()
                return
            }
            let wrapped = FileChannelConnection(
                wrapping: connection,
                queue: DispatchQueue(label: "crossdesk.transport.filechannel.conn")
            )
            self.onConnection?(wrapped)
        }
        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                Log.transport.info("filechannel: listening on tcp/\(self.port, privacy: .public)")
            case let .failed(error):
                Log.transport.error("filechannel: listener FAILED: \(String(describing: error), privacy: .public)")
                self.onFailed?("listener failed: \(error)")
            default:
                break
            }
        }
        self.listener = listener
        listener.start(queue: queue)
        Log.transport.info("filechannel: starting listener, psk fingerprint \(PairingKey.fingerprint(psk: self.psk), privacy: .public)")
    }

    public func stop() {
        queue.async { [self] in
            listener?.stateUpdateHandler = nil
            listener?.newConnectionHandler = nil
            listener?.cancel()
            listener = nil
        }
    }
}
