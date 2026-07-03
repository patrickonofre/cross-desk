import SwiftUI
import CrossDeskKit

@MainActor
final class AppState: ObservableObject {
    @Published var config: AppConfig
    @Published var sessionState: SessionState = .stopped
    @Published var running = false
    @Published var inputMonitoringGranted = false
    @Published var accessibilityGranted = false

    private let store = ConfigStore()
    private var serverSession: ServerSession?
    private var clientSession: ClientSession?

    init() {
        var loaded = (try? store.load()) ?? AppConfig()
        // First run as server: a pairing code must exist before the UI shows it.
        if loaded.pairingCode.isEmpty && loaded.role == .server {
            loaded.pairingCode = PairingKey.generateCode()
        }
        config = loaded
        saveConfig()
        refreshPermissions()
    }

    func refreshPermissions() {
        inputMonitoringGranted = InputCapture.hasPermission()
        accessibilityGranted = InputInjector.hasPermission()
    }

    func saveConfig() {
        try? store.save(config)
    }

    func regeneratePairingCode() {
        config.pairingCode = PairingKey.generateCode()
        saveConfig()
    }

    func copyPairingCode() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(config.pairingCode, forType: .string)
    }

    var permissionNeededForCurrentRole: Bool {
        switch config.role {
        case .server: !inputMonitoringGranted
        case .client: !accessibilityGranted
        }
    }

    func toggle() {
        running ? stop() : start()
    }

    private func start() {
        saveConfig()
        refreshPermissions()
        guard !permissionNeededForCurrentRole else {
            sessionState = .error("Permissão do sistema pendente")
            return
        }

        let onState: @Sendable (SessionState) -> Void = { [weak self] state in
            Task { @MainActor in self?.sessionState = state }
        }

        switch config.role {
        case .server:
            let session = ServerSession(
                port: config.port,
                pairingCode: config.pairingCode,
                edgeSide: config.edgeSide
            )
            session.onState = onState
            do {
                try session.start()
                serverSession = session
                running = true
            } catch {
                sessionState = .error("Falha ao iniciar captura: \(error)")
                refreshPermissions()
            }
        case .client:
            guard !config.serverHost.isEmpty, !config.pairingCode.isEmpty else {
                sessionState = .error("Preencha servidor e código de pareamento")
                return
            }
            let session = ClientSession(
                host: config.serverHost,
                port: config.port,
                pairingCode: config.pairingCode,
                deviceName: config.deviceName
            )
            session.onState = onState
            session.start()
            clientSession = session
            running = true
        }
    }

    private func stop() {
        serverSession?.stop()
        clientSession?.stop()
        serverSession = nil
        clientSession = nil
        running = false
        sessionState = .stopped
    }

    var statusText: String {
        switch sessionState {
        case .stopped:
            "Parado"
        case .waitingPeer:
            config.role == .server ? "Aguardando cliente…" : "Conectando…"
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
