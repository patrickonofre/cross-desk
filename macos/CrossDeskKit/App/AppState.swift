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

    private let store = ConfigStore()
    private let browser = ServerBrowser()
    private var serverSession: ServerSession?
    private var clientSession: ClientSession?

    init() {
        var loaded = (try? store.load()) ?? AppConfig()
        // First run as server: a pairing token must exist before the UI shows it.
        if loaded.pairingCode.isEmpty && loaded.role == .server {
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
            Task { @MainActor in self?.sessionState = state }
        }
        session.onPaired = { [weak self] secret in
            Task { @MainActor in
                guard let self else { return }
                self.config.pairedSecret = secret
                self.saveConfig()
                Log.app.info("server paired — rotated secret persisted")
            }
        }
        do {
            try session.start()
            serverSession = session
            running = true
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
        config.pairedServerName = server.name
        startClient(endpoint: server.endpoint, secret: secret, token: config.pairingCode)
    }

    /// Manual fallback for networks without mDNS (R32).
    func connectManual(host: String, token: String) {
        config.serverHost = host
        if !token.isEmpty {
            config.pairingCode = token
        }
        guard let port = NWEndpoint.Port(rawValue: config.port) else { return }
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
        session.onState = { [weak self] state in
            Task { @MainActor in self?.sessionState = state }
        }
        session.onPairSet = { [weak self] secret in
            Task { @MainActor in
                guard let self else { return }
                self.config.pairedSecret = secret
                self.saveConfig()
                Log.app.info("client paired — rotated secret persisted")
            }
        }
        session.start()
        clientSession = session
        running = true
        updateBrowsing()
    }

    // MARK: - Shared

    func stop() {
        serverSession?.stop()
        clientSession?.stop()
        serverSession = nil
        clientSession = nil
        running = false
        sessionState = .stopped
        updateBrowsing()
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
