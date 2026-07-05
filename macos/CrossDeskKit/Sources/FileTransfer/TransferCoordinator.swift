import Foundation

public struct TransferPolicy: Sendable {
    /// Announces at or below this size materialize automatically (design D2);
    /// above it the UI offers "Receber agora".
    public var eagerLimit: UInt64
    /// Per-transfer staging lives under here (D3).
    public var stagingRoot: URL
    /// Destination for "Receber agora" and drop fallback (R6).
    public var downloadsDir: URL

    public init(
        eagerLimit: UInt64 = 200 * 1024 * 1024,
        stagingRoot: URL,
        downloadsDir: URL
    ) {
        self.eagerLimit = eagerLimit
        self.stagingRoot = stagingRoot
        self.downloadsDir = downloadsDir
    }
}

public enum TransferRole: Sendable {
    case server
    /// The client knows the server's host (it connected to it) — the file
    /// channel always dials that same host (§8).
    case client(serverHost: String)
}

/// Snapshot for the UI (T46). Emitted on the coordinator queue.
public enum TransferUIState: Equatable, Sendable {
    case idle
    /// Announce above the eager limit — waiting for "Receber agora".
    case pendingOffer(transferId: UInt32, items: Int, totalBytes: UInt64)
    case receiving(transferId: UInt32, receivedBytes: UInt64, totalBytes: UInt64)
    case sending(transferId: UInt32)
    /// `urls`: staged (pasteboard flow) or moved (Downloads flow) top-level items.
    case done(transferId: UInt32, urls: [URL], movedToDownloads: Bool)
    case failed(transferId: UInt32, reason: String)
}

/// Ties the pieces together (design D2): pasteboard announces via the control
/// channel (CLIP_FILES/FILE_PULL over DTLS, injected by the app from the
/// session), file bytes via the TCP file channel. One transfer at a time.
///
/// Thread-safety: all state confined to `queue`; public methods hop onto it.
public final class TransferCoordinator: @unchecked Sendable {
    private let role: TransferRole
    private let port: UInt16
    private var filePSK: Data
    private let policy: TransferPolicy
    private let pasteboard: PasteboardFacade
    private let queue = DispatchQueue(label: "crossdesk.filetransfer")

    /// Outbound control messages — the app points this at the session's send.
    public var sendControl: (@Sendable ([Message]) -> Void)?
    public var onUIState: (@Sendable (TransferUIState) -> Void)?

    private var listener: FileChannelListener?
    /// stop() flips this so a pending listener-rebuild retry can't revive the
    /// coordinator afterwards.
    private var stopped = false
    /// Our latest local announce; a new copy replaces it (§3: new announce
    /// invalidates the previous one).
    private var outgoing: (id: UInt32, roots: [URL], items: Int, bytes: UInt64)?
    /// Peer announce above the eager limit, waiting for the user.
    private var pendingOffer: (id: UInt32, items: Int, bytes: UInt64)?
    /// Server side: FILE_PULL sent, waiting for the client's push connection.
    private var awaitingPush: (id: UInt32, bytes: UInt64, toDownloads: Bool)?
    private var awaitingPushTimer: DispatchSourceTimer?
    /// Accepted connections that have not sent FILE_HELLO yet (the listener
    /// does not retain them — we must).
    private var unrouted: [ObjectIdentifier: FileChannelConnection] = [:]

    // State touched exclusively on the coordinator queue.
    private final class ActiveTransfer: @unchecked Sendable {
        let id: UInt32
        let connection: FileChannelConnection
        let totalBytes: UInt64
        let toDownloads: Bool
        var receiver: FileReceiver?   // receiving side
        var sender: FileSender?       // sending side
        var stagingDir: URL?
        var finished = false

        init(id: UInt32, connection: FileChannelConnection, totalBytes: UInt64, toDownloads: Bool) {
            self.id = id
            self.connection = connection
            self.totalBytes = totalBytes
            self.toDownloads = toDownloads
        }
    }
    private var active: ActiveTransfer?

    public init(
        role: TransferRole,
        port: UInt16,
        filePSK: Data,
        policy: TransferPolicy,
        pasteboard: PasteboardFacade = SystemPasteboard()
    ) {
        self.role = role
        self.port = port
        self.filePSK = filePSK
        self.policy = policy
        self.pasteboard = pasteboard
    }

    // MARK: - Lifecycle

    public func start() throws {
        FileReceiver.cleanStaging(root: policy.stagingRoot)
        if case .server = role {
            let listener = makeListener(psk: filePSK)
            try listener.start()
            self.listener = listener
        }
    }

    private func makeListener(psk: Data) -> FileChannelListener {
        let listener = FileChannelListener(port: port, psk: psk)
        listener.onConnection = { [weak self] connection in
            guard let self else { return }
            self.queue.async { self.adopt(connection) }
        }
        listener.onFailed = { reason in
            Log.session.error("filetransfer: listener failed — \(reason, privacy: .public)")
        }
        return listener
    }

    public func stop() {
        queue.async { [self] in
            stopped = true
            listener?.stop()
            listener = nil
            for (_, connection) in unrouted { connection.close() }
            unrouted.removeAll()
            if let active { active.connection.close() }
            cleanupActive()
            outgoing = nil
            pendingOffer = nil
            clearAwaitingPush()
        }
    }

    /// Pairing rotated (PROTOCOL.md §6): the file channel must follow the new
    /// secret — the server listener is rebuilt with the new PSK. The rebuild
    /// can lose the bind race against the just-cancelled socket (same failure
    /// class as the DTLS listener rotation) — retry briefly instead of leaving
    /// the file channel silently dead until the next restart.
    public func updateFilePSK(_ psk: Data) {
        queue.async { [self] in
            filePSK = psk
            guard case .server = role, listener != nil else { return }
            listener?.stop()
            rebuildListener(psk: psk, retriesLeft: 5)
        }
    }

    private func rebuildListener(psk: Data, retriesLeft: Int) {
        guard !stopped else { return }
        guard psk == filePSK else { return } // a newer rotation superseded this one
        let rebuilt = makeListener(psk: psk)
        do {
            try rebuilt.start()
            listener = rebuilt
        } catch {
            Log.session.error("filetransfer: listener rebuild threw \(String(describing: error), privacy: .public) (retries left \(retriesLeft, privacy: .public))")
            guard retriesLeft > 0 else { return }
            queue.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.rebuildListener(psk: psk, retriesLeft: retriesLeft - 1)
            }
        }
    }

    // MARK: - Inputs

    /// Local copy detected (PasteboardWatcher) — announce it (D2.1).
    public func announceLocalCopy(roots: [URL]) {
        queue.async { [self] in
            do {
                let walker = try FileSender(roots: roots)
                let id = UInt32.random(in: 1...UInt32.max)
                outgoing = (id, roots, walker.itemCount, walker.totalBytes)
                sendControl?([.clipFiles(
                    transferId: id,
                    itemCount: UInt32(walker.itemCount),
                    totalBytes: walker.totalBytes
                )])
                Log.session.info("filetransfer: announced copy #\(id, privacy: .public) (\(walker.itemCount, privacy: .public) items, \(walker.totalBytes, privacy: .public) bytes)")
            } catch {
                Log.session.error("filetransfer: announce failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    /// Control messages from the DTLS channel (CLIP_FILES / FILE_PULL) — the
    /// app forwards them from the session's onFileMessage.
    public func handleControl(_ message: Message) {
        queue.async { [self] in
            switch message {
            case let .clipFiles(id, items, bytes):
                peerAnnounced(id: id, items: Int(items), bytes: bytes)
            case .filePull(let id):
                // We are the client and the server wants our announced files.
                guard case .client(let host) = role, outgoing?.id == id,
                      let outgoing = outgoing else { return }
                connectAndPush(host: host, id: id, roots: outgoing.roots)
            default:
                break
            }
        }
    }

    /// "Receber agora" for a pending (>limit) offer — lands in Downloads (R6).
    /// While another transfer is active the offer stays claimable (consuming
    /// it here would silently drop it — `materialize` refuses when busy).
    public func receiveNow() {
        queue.async { [self] in
            guard let offer = pendingOffer, active == nil else { return }
            pendingOffer = nil
            materialize(id: offer.id, bytes: offer.bytes, toDownloads: true)
        }
    }

    public func dismissPendingOffer() {
        queue.async { [self] in
            pendingOffer = nil
            emit(.idle)
        }
    }

    public func cancelActive() {
        queue.async { [self] in
            guard let active else { return }
            let origin: CancelOrigin = active.receiver != nil ? .receiver : .sender
            active.connection.send(.cancel(origin: origin))
            failActive(reason: "cancelado")
        }
    }

    // MARK: - Announce intake (on queue)

    private func peerAnnounced(id: UInt32, items: Int, bytes: UInt64) {
        pendingOffer = nil
        if bytes <= policy.eagerLimit && active == nil {
            materialize(id: id, bytes: bytes, toDownloads: false)
        } else {
            // Above the limit — or busy: keep it claimable instead of dropping.
            pendingOffer = (id, items, bytes)
            emit(.pendingOffer(transferId: id, items: items, totalBytes: bytes))
        }
    }

    private func materialize(id: UInt32, bytes: UInt64, toDownloads: Bool) {
        guard active == nil else { return }
        switch role {
        case let .client(serverHost):
            // We dial and ask (mode=request).
            let connection = FileChannelConnection(host: serverHost, port: port, psk: filePSK)
            guard let transfer = makeReceivingTransfer(
                id: id, connection: connection, bytes: bytes, toDownloads: toDownloads
            ) else { return }
            connection.onEvent = { [weak self] event in
                guard let self else { return }
                self.queue.async {
                    switch event {
                    case .ready:
                        connection.send(.fileHello(
                            protoVersion: FileChannelConstants.version,
                            transferId: id, mode: .request
                        ))
                    case let .messages(messages):
                        self.handleTransferMessages(messages)
                    case let .closed(reason):
                        self.channelClosed(reason: reason)
                    }
                }
            }
            active = transfer
            emit(.receiving(transferId: id, receivedBytes: 0, totalBytes: bytes))
            connection.start()

        case .server:
            // We cannot dial (§8) — ask the client to push and wait for the
            // incoming connection.
            awaitingPush = (id, bytes, toDownloads)
            sendControl?([.filePull(transferId: id)])
            emit(.receiving(transferId: id, receivedBytes: 0, totalBytes: bytes))
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + TransportTiming.handshakeTimeout + 5)
            timer.setEventHandler { [weak self] in
                guard let self, let waiting = self.awaitingPush, waiting.id == id else { return }
                self.clearAwaitingPush()
                self.emit(.failed(transferId: id, reason: "cliente não conectou o canal de arquivos"))
            }
            timer.resume()
            awaitingPushTimer = timer
        }
    }

    // MARK: - Serving our files (on queue)

    private func connectAndPush(host: String, id: UInt32, roots: [URL]) {
        guard active == nil else { return }
        let connection = FileChannelConnection(host: host, port: port, psk: filePSK)
        let transfer = ActiveTransfer(id: id, connection: connection, totalBytes: 0, toDownloads: false)
        connection.onEvent = { [weak self] event in
            guard let self else { return }
            self.queue.async {
                switch event {
                case .ready:
                    connection.send(.fileHello(
                        protoVersion: FileChannelConstants.version,
                        transferId: id, mode: .push
                    ))
                    self.startSending(roots: roots, over: transfer)
                case let .messages(messages):
                    self.handleTransferMessages(messages)
                case let .closed(reason):
                    self.channelClosed(reason: reason)
                }
            }
        }
        active = transfer
        connection.start()
    }

    private func startSending(roots: [URL], over transfer: ActiveTransfer) {
        do {
            transfer.sender = try FileSender(roots: roots)
            emit(.sending(transferId: transfer.id))
            pumpNext(transfer)
        } catch {
            failActive(reason: "leitura da seleção falhou: \(error)")
        }
    }

    private func pumpNext(_ transfer: ActiveTransfer) {
        guard active === transfer, !transfer.finished, let sender = transfer.sender else { return }
        do {
            guard let message = try sender.nextMessage() else {
                // TRANSFER_DONE went out; TCP delivers buffered data on close.
                transfer.finished = true
                transfer.connection.close()
                active = nil
                emit(.done(transferId: transfer.id, urls: [], movedToDownloads: false))
                return
            }
            transfer.connection.send(message) { [weak self] error in
                guard let self else { return }
                self.queue.async {
                    if let error {
                        self.failActive(reason: "envio falhou: \(error)")
                    } else {
                        self.pumpNext(transfer)
                    }
                }
            }
        } catch {
            transfer.connection.send(.error(code: 1, message: "\(error)"))
            failActive(reason: "leitura falhou: \(error)")
        }
    }

    // MARK: - Incoming connections (server role, on queue)

    private func adopt(_ connection: FileChannelConnection) {
        let key = ObjectIdentifier(connection)
        unrouted[key] = connection
        connection.onEvent = { [weak self] event in
            guard let self else { return }
            self.queue.async {
                switch event {
                case .ready:
                    break // the dialer speaks first (FILE_HELLO)
                case let .messages(messages):
                    if self.unrouted.removeValue(forKey: key) != nil {
                        self.route(connection, messages: messages)
                    } else {
                        self.handleTransferMessages(messages)
                    }
                case let .closed(reason):
                    if self.unrouted.removeValue(forKey: key) == nil {
                        self.channelClosed(reason: reason)
                    }
                }
            }
        }
        connection.start()
    }

    private func route(_ connection: FileChannelConnection, messages: [FileChannelMessage]) {
        guard case let .fileHello(_, id, mode) = messages.first else {
            connection.send(.error(code: 2, message: "FILE_HELLO esperado"))
            connection.close()
            return
        }
        let rest = Array(messages.dropFirst())
        switch mode {
        case .request:
            // Peer wants our announced files.
            guard let outgoing, outgoing.id == id, active == nil else {
                connection.send(.error(code: 3, message: "transferência desconhecida"))
                connection.close()
                return
            }
            let transfer = ActiveTransfer(id: id, connection: connection, totalBytes: 0, toDownloads: false)
            active = transfer
            startSending(roots: outgoing.roots, over: transfer)
        case .push:
            // Client pushing what we FILE_PULLed.
            guard let waiting = awaitingPush, waiting.id == id, active == nil else {
                connection.send(.error(code: 3, message: "push não solicitado"))
                connection.close()
                return
            }
            clearAwaitingPush()
            guard let transfer = makeReceivingTransfer(
                id: id, connection: connection, bytes: waiting.bytes, toDownloads: waiting.toDownloads
            ) else { return }
            active = transfer
            if !rest.isEmpty { handleTransferMessages(rest) }
        }
    }

    // MARK: - Receiving (on queue)

    private func makeReceivingTransfer(
        id: UInt32, connection: FileChannelConnection, bytes: UInt64, toDownloads: Bool
    ) -> ActiveTransfer? {
        let stagingDir = policy.stagingRoot.appendingPathComponent(String(id))
        do {
            let transfer = ActiveTransfer(
                id: id, connection: connection, totalBytes: bytes, toDownloads: toDownloads
            )
            transfer.receiver = try FileReceiver(stagingRoot: stagingDir)
            transfer.stagingDir = stagingDir
            return transfer
        } catch {
            emit(.failed(transferId: id, reason: "staging indisponível: \(error)"))
            connection.close()
            return nil
        }
    }

    private func handleTransferMessages(_ messages: [FileChannelMessage]) {
        guard let transfer = active else { return }
        guard let receiver = transfer.receiver else {
            // Sending side: the only expected inbound frames are CANCEL/ERROR.
            for message in messages {
                switch message {
                case .cancel:
                    failActive(reason: "cancelado pelo outro lado")
                    return
                case let .error(_, text):
                    failActive(reason: "erro do outro lado: \(text)")
                    return
                default:
                    break
                }
            }
            return
        }
        do {
            for message in messages {
                switch message {
                case .cancel:
                    failActive(reason: "cancelado pelo outro lado")
                    return
                case let .error(_, text):
                    failActive(reason: "erro do outro lado: \(text)")
                    return
                default:
                    try receiver.handle(message)
                }
            }
            if receiver.isComplete {
                finishReceive(transfer, receiver: receiver)
            } else {
                emit(.receiving(
                    transferId: transfer.id,
                    receivedBytes: receiver.receivedBytes,
                    totalBytes: transfer.totalBytes
                ))
            }
        } catch {
            transfer.connection.send(.error(code: 1, message: "\(error)"))
            failActive(reason: "recepção falhou: \(error)")
        }
    }

    private func finishReceive(_ transfer: ActiveTransfer, receiver: FileReceiver) {
        transfer.finished = true
        do {
            let urls: [URL]
            if transfer.toDownloads {
                urls = try receiver.materialize(into: policy.downloadsDir)
                if let stagingDir = transfer.stagingDir {
                    try? FileManager.default.removeItem(at: stagingDir)
                }
            } else {
                // Eager flow (D2): real URLs from staging go straight onto the
                // pasteboard — ⌘V is native from here on. The marker keeps our
                // own watcher from re-announcing them (anti-loop).
                urls = try receiver.stagedItemURLs()
                pasteboard.writeFileURLs(urls)
            }
            transfer.connection.close()
            active = nil
            emit(.done(transferId: transfer.id, urls: urls, movedToDownloads: transfer.toDownloads))
        } catch {
            failActive(reason: "materialização falhou: \(error)")
        }
    }

    // MARK: - Teardown helpers (on queue)

    private func channelClosed(reason: String) {
        guard let transfer = active, !transfer.finished else { return }
        // Peer closing before TRANSFER_DONE completed = broken transfer.
        failActive(reason: reason)
    }

    private func failActive(reason: String) {
        guard let transfer = active else { return }
        transfer.finished = true
        transfer.connection.close()
        if let stagingDir = transfer.stagingDir {
            try? FileManager.default.removeItem(at: stagingDir)
        }
        active = nil
        Log.session.error("filetransfer: #\(transfer.id, privacy: .public) failed — \(reason, privacy: .public)")
        emit(.failed(transferId: transfer.id, reason: reason))
    }

    private func cleanupActive() {
        if let transfer = active, let stagingDir = transfer.stagingDir {
            try? FileManager.default.removeItem(at: stagingDir)
        }
        active = nil
    }

    private func clearAwaitingPush() {
        awaitingPush = nil
        awaitingPushTimer?.cancel()
        awaitingPushTimer = nil
    }

    private func emit(_ state: TransferUIState) {
        onUIState?(state)
    }
}
