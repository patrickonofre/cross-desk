import SwiftUI
import CrossDeskKit

struct MenuBarView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            rolePicker
            roleFields
            Divider()
            permissionsSection
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 320)
        .onAppear { appState.refreshPermissions() }
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
                appState.regeneratePairingCode()
            }
            appState.saveConfig()
        }
    }

    @ViewBuilder
    private var roleFields: some View {
        if appState.config.role == .server {
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

            VStack(alignment: .leading, spacing: 4) {
                Text("Código de pareamento")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    Text(appState.config.pairingCode)
                        .font(.system(.caption2, design: .monospaced))
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button {
                        appState.copyPairingCode()
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .help("Copiar código")
                    Button {
                        appState.regeneratePairingCode()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .disabled(appState.running)
                    .help("Gerar novo código")
                }
            }

            serverAddressSection
        } else {
            TextField("Servidor (IP ou hostname)", text: $appState.config.serverHost)
                .textFieldStyle(.roundedBorder)
                .disabled(appState.running)
            TextField("Código de pareamento", text: $appState.config.pairingCode)
                .textFieldStyle(.roundedBorder)
                .font(.system(.caption, design: .monospaced))
                .disabled(appState.running)
        }
    }

    /// Addresses the user types on the client machine (hostname first —
    /// stable across DHCP renews).
    private var serverAddressSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Endereço deste servidor (digite no cliente)")
                .font(.caption)
                .foregroundStyle(.secondary)
            addressRow(NetworkInfo.localHostname())
            ForEach(NetworkInfo.localIPv4Addresses().prefix(3), id: \.ip) { entry in
                addressRow(entry.ip, label: entry.interface)
            }
        }
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
            Button(appState.running ? "Parar" : "Iniciar") {
                appState.toggle()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!appState.running && appState.permissionNeededForCurrentRole)

            Spacer()

            Button("Sair") {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}
