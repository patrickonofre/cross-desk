import SwiftUI
import CrossDeskKit

struct MenuBarView: View {
    @EnvironmentObject private var appState: AppState
    /// Discovered server the user tapped to pair with (token field open).
    @State private var pairingWith: DiscoveredServer?
    @State private var tokenInput = ""
    @State private var manualHost = ""
    @State private var manualToken = ""
    @State private var manualExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            MiniMapView()
            Divider()
            rolePicker
            roleFields
            if appState.transferState != .idle {
                Divider()
                transferSection
            }
            Divider()
            optionsSection
            Divider()
            permissionsSection
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 320)
        .onAppear {
            appState.refreshPermissions()
            appState.updateBrowsing()
            manualHost = appState.config.serverHost
        }
        // TCC grants happen outside the app (System Settings); poll while the
        // panel is open so the ⚠️ flips to ✓ without user interaction.
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            appState.refreshPermissions()
        }
    }

    private var header: some View {
        HStack {
            Circle()
                .fill(appState.statusColor)
                .frame(width: 9, height: 9)
            Text(appState.statusText)
                .font(.callout.weight(.medium))
                .lineLimit(2)
            Spacer()
        }
    }

    private var rolePicker: some View {
        Picker("Papel", selection: $appState.config.role) {
            Text("Servidor").tag(Role.server)
            Text("Cliente").tag(Role.client)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .disabled(appState.running)
        .onChange(of: appState.config.role) {
            if appState.config.role == .server && appState.config.pairingCode.isEmpty {
                appState.regeneratePairingToken()
            }
            appState.saveConfig()
            appState.updateBrowsing()
        }
    }

    @ViewBuilder
    private var roleFields: some View {
        if appState.config.role == .server {
            serverFields
        } else {
            clientFields
        }
    }

    // MARK: - Server role

    @ViewBuilder
    private var serverFields: some View {
        LabeledContent("Borda") {
            Picker("", selection: $appState.config.edgeSide) {
                Text("Direita").tag(EdgeSide.right)
                Text("Esquerda").tag(EdgeSide.left)
                Text("Cima").tag(EdgeSide.top)
                Text("Baixo").tag(EdgeSide.bottom)
            }
            .labelsHidden()
            .frame(width: 130)
        }
        .disabled(appState.running)

        if appState.paired {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                Text("Pareado")
                    .font(.callout)
                Spacer()
                Button("Esquecer pareamento") {
                    appState.forgetPairing()
                }
                .font(.caption)
            }
        } else {
            // The token IS the pairing UX (R28): big, legible, one glance to
            // read it from this screen and type it on the client.
            VStack(alignment: .leading, spacing: 4) {
                Text("Token de pareamento (digite no cliente)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Text(appState.config.pairingCode)
                        .font(.system(.title2, design: .monospaced).weight(.bold))
                        .textSelection(.enabled)
                    Button {
                        appState.copyPairingToken()
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .help("Copiar token")
                    Button {
                        appState.regeneratePairingToken()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .disabled(appState.running)
                    .help("Gerar novo token")
                }
            }
        }

        DisclosureGroup("Conexão manual (endereços deste servidor)") {
            VStack(alignment: .leading, spacing: 4) {
                addressRow(NetworkInfo.localHostname())
                ForEach(NetworkInfo.localIPv4Addresses().prefix(3), id: \.ip) { entry in
                    addressRow(entry.ip, label: entry.interface)
                }
            }
            .padding(.top, 4)
        }
        .font(.caption)
    }

    private func addressRow(_ address: String, label: String? = nil) -> some View {
        HStack(spacing: 6) {
            Text(address)
                .font(.system(.caption2, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
            if let label {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(address, forType: .string)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .help("Copiar")
        }
    }

    // MARK: - Client role

    @ViewBuilder
    private var clientFields: some View {
        if appState.running {
            if appState.paired || !appState.config.pairedServerName.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(appState.paired ? .green : .secondary)
                    Text(appState.config.pairedServerName.isEmpty
                         ? "Conectado" : appState.config.pairedServerName)
                        .font(.callout)
                        .lineLimit(1)
                    Spacer()
                    if appState.paired {
                        Button("Esquecer") { appState.forgetPairing() }
                            .font(.caption)
                    }
                }
            }
        } else {
            discoveryList
            manualConnectSection
            if appState.paired {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                    Text("Pareado com \(appState.config.pairedServerName)")
                        .font(.caption)
                        .lineLimit(1)
                    Spacer()
                    Button("Esquecer") { appState.forgetPairing() }
                        .font(.caption)
                }
            }
        }
    }

    @ViewBuilder
    private var discoveryList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Servidores na rede")
                .font(.caption)
                .foregroundStyle(.secondary)

            if appState.discoveredServers.isEmpty {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Procurando servidores…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if appState.localNetworkDenied {
                    Text("Sem acesso à Rede Local. Conceda em Ajustes → Privacidade e Segurança → Rede Local, ou use a conexão por IP abaixo.")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            ForEach(appState.discoveredServers) { server in
                serverRow(server)
            }
        }
    }

    @ViewBuilder
    private func serverRow(_ server: DiscoveredServer) -> some View {
        let isPaired = appState.paired && server.name == appState.config.pairedServerName
        HStack(spacing: 6) {
            Image(systemName: isPaired ? "checkmark.seal.fill" : "desktopcomputer")
                .foregroundStyle(isPaired ? .green : .secondary)
            Text(server.name)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Button(isPaired ? "Conectar" : "Parear…") {
                if isPaired {
                    appState.connect(to: server)
                } else {
                    pairingWith = pairingWith?.name == server.name ? nil : server
                    tokenInput = ""
                }
            }
            .font(.caption)
        }

        if pairingWith?.name == server.name {
            HStack(spacing: 6) {
                TextField("Token do servidor (XXXX-XXXX)", text: $tokenInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .onSubmit { pairAndConnect(server) }
                Button("Conectar") { pairAndConnect(server) }
                    .disabled(tokenInput.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.leading, 20)
        }
    }

    private func pairAndConnect(_ server: DiscoveredServer) {
        let token = tokenInput.trimmingCharacters(in: .whitespaces)
        guard !token.isEmpty else { return }
        pairingWith = nil
        appState.connect(to: server, token: token)
    }

    private var manualConnectSection: some View {
        DisclosureGroup("Conectar por IP…", isExpanded: $manualExpanded) {
            VStack(alignment: .leading, spacing: 6) {
                TextField("Servidor (IP ou hostname)", text: $manualHost)
                    .textFieldStyle(.roundedBorder)
                TextField("Token de pareamento", text: $manualToken)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                Button("Conectar") {
                    appState.connectManual(
                        host: manualHost.trimmingCharacters(in: .whitespaces),
                        token: manualToken.trimmingCharacters(in: .whitespaces)
                    )
                }
                .disabled(manualHost.trimmingCharacters(in: .whitespaces).isEmpty
                          || (manualToken.trimmingCharacters(in: .whitespaces).isEmpty && !appState.paired))
            }
            .padding(.top, 4)
        }
        .font(.caption)
    }

    // MARK: - File transfer (file-transfer T46)

    @ViewBuilder
    private var transferSection: some View {
        switch appState.transferState {
        case .idle:
            EmptyView()

        case let .pendingOffer(_, items, totalBytes):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "tray.and.arrow.down")
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(items) \(items == 1 ? "arquivo" : "arquivos") (\(Self.bytesText(totalBytes)))")
                        .font(.caption)
                    Text("do outro Mac — receber em Downloads/CrossDesk")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Receber") { appState.transferReceiveNow() }
                    .font(.caption)
                dismissButton
            }

        case let .receiving(_, receivedBytes, totalBytes):
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("Recebendo arquivos…")
                        .font(.caption)
                    Spacer()
                    Text("\(Self.bytesText(receivedBytes)) / \(Self.bytesText(totalBytes))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Button("Cancelar") { appState.transferCancel() }
                        .font(.caption)
                }
                if totalBytes > 0 {
                    ProgressView(value: Double(receivedBytes), total: Double(totalBytes))
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
            }

        case .sending:
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text("Enviando arquivos…")
                    .font(.caption)
                Spacer()
                Button("Cancelar") { appState.transferCancel() }
                    .font(.caption)
            }

        case let .done(_, urls, movedToDownloads):
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text(movedToDownloads
                     ? "Recebido em Downloads/CrossDesk"
                     : (urls.isEmpty ? "Envio concluído" : "Arquivos prontos — ⌘V para colar"))
                    .font(.caption)
                Spacer()
                dismissButton
            }

        case let .failed(_, reason):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text("Transferência falhou: \(reason)")
                    .font(.caption)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                dismissButton
            }
        }
    }

    private var dismissButton: some View {
        Button {
            appState.transferDismiss()
        } label: {
            Image(systemName: "xmark")
        }
        .buttonStyle(.borderless)
        .help("Dispensar")
    }

    private static func bytesText(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    // MARK: - Shared sections

    private var optionsSection: some View {
        Toggle(isOn: $appState.config.concealCursor) {
            Text("Esconder o cursor na máquina sem foco")
                .font(.caption)
        }
        .toggleStyle(.checkbox)
        .disabled(appState.running)
        .onChange(of: appState.config.concealCursor) {
            appState.saveConfig()
        }
    }

    private var permissionsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            if appState.config.role == .server {
                permissionRow(
                    granted: appState.inputMonitoringGranted,
                    title: "Monitoramento de Entrada",
                    request: { InputCapture.requestPermission() },
                    openSettings: Permissions.openInputMonitoringSettings
                )
            } else {
                permissionRow(
                    granted: appState.accessibilityGranted,
                    title: "Acessibilidade",
                    request: { InputInjector.requestPermission() },
                    openSettings: Permissions.openAccessibilitySettings
                )
            }
            if appState.permissionNeededForCurrentRole {
                Text("Ao conceder, o macOS pode fechar e reabrir o CrossDesk sozinho — é normal. Se não reabrir ou continuar ⚠️:")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Reiniciar app") {
                    appState.relaunch()
                }
                .font(.caption)
            }
        }
    }

    private func permissionRow(
        granted: Bool,
        title: String,
        request: @escaping () -> Void,
        openSettings: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 6) {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(granted ? .green : .orange)
            Text(title)
                .font(.caption)
            Spacer()
            if !granted {
                Button("Conceder") {
                    request()
                    openSettings()
                    // TCC state only refreshes after the user acts in Settings.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        appState.refreshPermissions()
                    }
                }
                .font(.caption)
            }
        }
    }

    private var footer: some View {
        HStack {
            if appState.config.role == .server {
                Button(appState.running ? "Parar" : "Iniciar") {
                    appState.toggleServer()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!appState.running && appState.permissionNeededForCurrentRole)
            } else if appState.running {
                Button("Parar") {
                    appState.stop()
                }
                .keyboardShortcut(.defaultAction)
            }

            Spacer()

            Button("Sair") {
                Log.app.info("quit requested via Sair button")
                NSApplication.shared.terminate(nil)
            }
        }
    }
}
