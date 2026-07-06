import SwiftUI
import Network
import CrossDeskKit

@MainActor
final class AppState: ObservableObject {
    @Published var config: AppConfig
    @Published var sessionState: SessionState = .stopped
    @Published var running = false
    @Published var inputMonitoringGranted = false
    @Published var accessibilityGranted = false
    /// Servers visible on the LAN (client role, R26).
    @Published var discoveredServers: [DiscoveredServer] = []
    /// Local Network permission looks denied (browser stuck waiting, R33).
    @Published var localNetworkDenied = false
    /// File transfer status for the panel section (file-transfer T46).
    @Published var transferState: TransferUIState = .idle
    /// Client only (layout-ux R37): return edge from the last ENTER — where
    /// the desk canvas pins the server tile. Nil until the first crossing of
    /// the current session.
    @Published var clientReturnEdge: EdgeSide?
    /// Client only (layout-ux R38): the cursor is currently on this machine.
    @Published var clientFocused = false

    private let store = ConfigStore()
    private let browser = ServerBrowser()
    private var serverSession: ServerSession?
    private var clientSession: ClientSession?
    private var transferCoordinator: TransferCoordinator?
    private var pasteboardWatcher: PasteboardWatcher?
    /// Server the user is pairing with right now. Only committed to
    /// `config.pairedServerName` when PAIR_SET confirms — writing it upfront
    /// would orphan the stored secret if the user taps the wrong server (the
    /// secret stays but no row would ever lead with it again).
    private var pendingServerName: String?

    init() {
        var loaded = (try? store.load()) ?? AppConfig()
        // First run as server: a valid pairing token must exist before the UI
        // shows it (catches empty AND stale/wrong-format values — e.g. a
        // config saved before this token existed, or before its length last
        // changed — which would otherwise survive forever since they're
        // never empty).
        if loaded.role == .server && !PairingKey.isShortToken(loaded.pairingCode) {
            loaded.pairingCode = PairingKey.generateShortToken()
        }
        config = loaded
        saveConfig()
        refreshPermissions()

        browser.onUpdate = { [weak self] servers in
            Task { @MainActor in self?.discoveredServers = servers }
        }
        browser.onPermissionState = { [weak self] denied in
            Task { @MainActor in self?.localNetworkDenied = denied }
        }
        updateBrowsing()

        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        Log.app.info("app launched (build \(build, privacy: .public)), role \(loaded.role.rawValue, privacy: .public)")
    }

    func refreshPermissions() {
        inputMonitoringGranted = InputCapture.hasPermission()
        accessibilityGranted = InputInjector.hasPermission()
    }

    func saveConfig() {
        try? store.save(config)
    }

    // MARK: - Pairing state

    /// Paired = the rotated 128-bit secret is stored (R29).
    var paired: Bool { !config.pairedSecret.isEmpty }

    func regeneratePairingToken() {
        config.pairingCode = PairingKey.generateShortToken()
        saveConfig()
    }

    func copyPairingToken() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(config.pairingCode, forType: .string)
    }

    /// Drops the pairing on this side (R31). Server: fresh token, back to
    /// "waiting for pairing". Client: back to the list, token required again.
    func forgetPairing() {
        if running { stop() }
        config.pairedSecret = ""
        config.pairedServerName = ""
        pendingServerName = nil
        switch config.role {
        case .server: config.pairingCode = PairingKey.generateShortToken()
        case .client: config.pairingCode = ""
        }
        saveConfig()
    }

    // MARK: - Discovery lifecycle

    /// Browse only while the user could actually pick a server: client role,
    /// session stopped (R26 + less mDNS radiation).
    func updateBrowsing() {
        if config.role == .client && !running {
            browser.start()
        } else {
            browser.stop()
            discoveredServers = []
        }
    }

    var permissionNeededForCurrentRole: Bool {
        switch config.role {
        case .server: !inputMonitoringGranted
        case .client: !accessibilityGranted
        }
    }

    // MARK: - Server role

    func toggleServer() {
        running ? stop() : startServer()
    }

    private func startServer() {
        saveConfig()
        refreshPermissions()
        Log.app.info("start server: inputMonitoring \(self.inputMonitoringGranted, privacy: .public), paired \(self.paired, privacy: .public)")
        guard inputMonitoringGranted else {
            sessionState = .error("Permissão pendente — reinicie o app se acabou de conceder")
            return
        }
        // Paired → listen with the secret; unpaired → token PSK + rotation on
        // the first successful handshake (R29).
        let session = ServerSession(
            port: config.port,
            pairingCode: paired ? config.pairedSecret : config.pairingCode,
            edgeSide: config.edgeSide,
            advertiseName: config.deviceName,
            pairing: !paired,
            conceal: config.concealCursor
        )
        session.onState = { [weak self] state in
            Task { @MainActor in
                guard let self else { return }
                self.sessionState = state
                // First real handoff kills the crossing hint forever (R39).
                if case .controllingRemote = state { self.markFirstCrossing() }
            }
        }
        session.onPaired = { [weak self] secret in
            Task { @MainActor in
                guard let self else { return }
                self.config.pairedSecret = secret
                self.saveConfig()
                // The file channel follows the rotation (PROTOCOL.md §6/§8).
                self.transferCoordinator?.updateFilePSK(PairingKey.filePSK(fromCode: secret))
                Log.app.info("server paired — rotated secret persisted")
            }
        }
        do {
            try session.start()
            serverSession = session
            running = true
            startFileTransfer(role: .server, code: paired ? config.pairedSecret : config.pairingCode)
            updateBrowsing()
        } catch {
            Log.app.error("start failed: capture start threw \(String(describing: error), privacy: .public)")
            sessionState = .error("Falha ao iniciar captura — reinicie o app")
            refreshPermissions()
        }
    }

    // MARK: - Client role

    /// Connect to a discovered server (R27). `token` is what the user just
    /// typed (nil when tapping an already-paired server).
    func connect(to server: DiscoveredServer, token: String? = nil) {
        if let token, !token.isEmpty {
            config.pairingCode = token
        }
        // The stored secret belongs to ONE server — never lead with it against
        // a different one (the token typed for the new server is the credential).
        let secret = server.name == config.pairedServerName ? config.pairedSecret : ""
        pendingServerName = server.name
        startClient(endpoint: server.endpoint, secret: secret, token: config.pairingCode)
    }

    /// Manual fallback for networks without mDNS (R32). Not a discovery row, so
    /// there is no Bonjour name to (re)commit on PAIR_SET — leaves whatever
    /// `pairedServerName` discovery last wrote untouched.
    func connectManual(host: String, token: String) {
        config.serverHost = host
        if !token.isEmpty {
            config.pairingCode = token
        }
        guard let port = NWEndpoint.Port(rawValue: config.port) else { return }
        pendingServerName = nil
        startClient(
            endpoint: .hostPort(host: NWEndpoint.Host(host), port: port),
            secret: config.pairedSecret,
            token: config.pairingCode
        )
    }

    private func startClient(endpoint: NWEndpoint, secret: String, token: String) {
        saveConfig()
        refreshPermissions()
        guard accessibilityGranted else {
            sessionState = .error("Permissão pendente — reinicie o app se acabou de conceder")
            return
        }
        guard !secret.isEmpty || !token.isEmpty else {
            sessionState = .error("Digite o token exibido no servidor")
            return
        }
        let session = ClientSession(
            endpoint: endpoint,
            pairedSecret: secret,
            pairingToken: token,
            deviceName: config.deviceName,
            conceal: config.concealCursor
        )
        session.onState = { [weak self, weak session] state in
            Task { @MainActor in
                guard let self else { return }
                self.sessionState = state
                // The file channel needs the RESOLVED server host (a Bonjour
                // endpoint has none until connected) — start it on first connect.
                if case .connected = state, self.transferCoordinator == nil,
                   let session, let host = session.serverHost() {
                    self.startFileTransfer(
                        role: .client(serverHost: host),
                        code: self.paired ? self.config.pairedSecret : self.config.pairingCode
                    )
                }
            }
        }
        session.onPairSet = { [weak self] secret in
            Task { @MainActor in
                guard let self else { return }
                self.config.pairedSecret = secret
                // Only now — pairing actually succeeded against THIS server —
                // does the discovery row become the remembered one.
                if let pendingServerName = self.pendingServerName {
                    self.config.pairedServerName = pendingServerName
                    self.pendingServerName = nil
                }
                self.saveConfig()
                // The file channel follows the rotation (PROTOCOL.md §6/§8).
                self.transferCoordinator?.updateFilePSK(PairingKey.filePSK(fromCode: secret))
                Log.app.info("client paired — rotated secret persisted")
            }
        }
        // Desk canvas/mini-map feed (layout-ux R37/R38).
        clientReturnEdge = nil
        clientFocused = false
        session.onEnter = { [weak self] edge in
            Task { @MainActor in
                guard let self else { return }
                self.clientReturnEdge = edge
                self.clientFocused = true
                self.markFirstCrossing()
            }
        }
        session.onLeave = { [weak self] in
            Task { @MainActor in self?.clientFocused = false }
        }
        session.start()
        clientSession = session
        running = true
        updateBrowsing()
    }

    // MARK: - File transfer (file-transfer T46)

    private func startFileTransfer(role: TransferRole, code: String) {
        let fm = FileManager.default
        guard let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask).first,
              let downloads = fm.urls(for: .downloadsDirectory, in: .userDomainMask).first
        else { return }
        let coordinator = TransferCoordinator(
            role: role,
            port: config.port,
            filePSK: PairingKey.filePSK(fromCode: code),
            policy: TransferPolicy(
                stagingRoot: caches.appendingPathComponent("CrossDesk/incoming"),
                downloadsDir: downloads.appendingPathComponent("CrossDesk")
            )
        )
        coordinator.onUIState = { [weak self] state in
            Task { @MainActor in
                self?.transferState = state
                if case let .done(_, urls, movedToDownloads) = state,
                   movedToDownloads, !urls.isEmpty {
                    NSWorkspace.shared.activateFileViewerSelecting(urls)
                }
            }
        }
        if let serverSession {
            coordinator.sendControl = { [weak serverSession] in serverSession?.sendControl($0) }
            serverSession.onFileMessage = { [weak coordinator] in coordinator?.handleControl($0) }
        } else if let clientSession {
            coordinator.sendControl = { [weak clientSession] in clientSession?.sendControl($0) }
            clientSession.onFileMessage = { [weak coordinator] in coordinator?.handleControl($0) }
        }
        do {
            try coordinator.start()
        } catch {
            // Input keeps working without the file channel — degrade quietly.
            Log.app.error("file transfer unavailable: \(String(describing: error), privacy: .public)")
            return
        }
        let watcher = PasteboardWatcher()
        watcher.onFilesCopied = { [weak coordinator] urls in
            coordinator?.announceLocalCopy(roots: urls)
        }
        watcher.start()
        transferCoordinator = coordinator
        pasteboardWatcher = watcher
    }

    private func stopFileTransfer() {
        pasteboardWatcher?.stop()
        pasteboardWatcher = nil
        transferCoordinator?.stop()
        transferCoordinator = nil
        transferState = .idle
    }

    func transferReceiveNow() {
        transferCoordinator?.receiveNow()
    }

    func transferCancel() {
        transferCoordinator?.cancelActive()
    }

    func transferDismiss() {
        if case .pendingOffer = transferState {
            transferCoordinator?.dismissPendingOffer()
        }
        transferState = .idle
    }

    // MARK: - Shared

    func stop() {
        stopFileTransfer()
        serverSession?.stop()
        clientSession?.stop()
        serverSession = nil
        clientSession = nil
        running = false
        sessionState = .stopped
        clientFocused = false
        updateBrowsing()
    }

    // MARK: - Desk UI (layout-ux)

    /// R38: visual phase for the desk canvas and mini-map. The server's
    /// `connected` means the cursor is local (REMOTE is its own state); the
    /// client derives focus from ENTER/LEAVE.
    var deskPhase: DeskPhase {
        DeskModel.phase(
            sessionState: sessionState,
            paired: paired,
            focusedHere: config.role == .server ? true : clientFocused
        )
    }

    /// Peer name for the desk tile: the HELLO name when the session has one,
    /// the remembered server otherwise.
    var peerName: String {
        switch sessionState {
        case let .connected(peer), let .controllingRemote(peer):
            if peer != "servidor" { return peer }
        default:
            break
        }
        if config.role == .client && !config.pairedServerName.isEmpty {
            return config.pairedServerName
        }
        return "Outro Mac"
    }

    /// R39: one-time directional hint. Server-side only — pushing the cursor
    /// through the edge is an action on the machine that owns the keyboard.
    var crossingHint: String? {
        guard config.role == .server else { return nil }
        return DeskModel.crossingHint(
            phase: deskPhase,
            edge: config.edgeSide,
            firstCrossingDone: config.firstCrossingDone
        )
    }

    /// R41: menubar icon mirrors where the input goes.
    var menuBarSymbol: String {
        if case .controllingRemote = sessionState { return "cursorarrow.motionlines" }
        return "display.2"
    }

    /// Whether `menuBarSymbol` should render filled. Applied via `.symbolVariant`
    /// (not baked into the name) — a hardcoded "display.2.fill" faults at
    /// runtime on symbol sets that don't ship that variant (SwiftUI logs it as
    /// an Invalid Configuration fault, seen live during the 2026-07-06 UAT).
    var menuBarSymbolFilled: Bool {
        if case .controllingRemote = sessionState { return false }
        return running
    }

    /// R39: the hint dies at the first real handoff, forever (persisted).
    func markFirstCrossing() {
        guard !config.firstCrossingDone else { return }
        config.firstCrossingDone = true
        saveConfig()
    }

    /// Accessibility/Input Monitoring grants only take effect on a fresh
    /// process (per-process TCC cache) — relaunch instead of asking the user
    /// to quit and reopen manually.
    ///
    /// The relauncher must survive this process's death: a bare `open -n`
    /// fired right before terminate() races the exit and the new instance
    /// may never launch. Detached shell + delay reparents to launchd and
    /// starts the new instance after the old one is gone.
    func relaunch() {
        Log.app.info("relaunch requested")
        let path = Bundle.main.bundlePath.replacingOccurrences(of: "'", with: "'\\''")
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 0.7; /usr/bin/open -n '\(path)'"]
        try? task.run()
        NSApplication.shared.terminate(nil)
    }

    var statusText: String {
        switch sessionState {
        case .stopped:
            "Parado"
        case .waitingPeer:
            if config.role == .server {
                paired ? "Aguardando cliente…" : "Aguardando pareamento…"
            } else {
                "Conectando…"
            }
        case let .connected(peer):
            "Conectado: \(peer)"
        case let .controllingRemote(peer):
            "Controlando \(peer)"
        case let .error(message):
            "Erro: \(message)"
        }
    }

    var statusColor: Color {
        switch sessionState {
        case .stopped: .secondary
        case .waitingPeer: .orange
        case .connected, .controllingRemote: .green
        case .error: .red
        }
    }
}
