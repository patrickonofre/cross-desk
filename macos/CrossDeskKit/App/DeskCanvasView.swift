import SwiftUI
import CrossDeskKit

/// "Telas" window (layout-ux R36–R38): the user's desk in miniature — real
/// local monitors, the peer Mac as an abstract tile (its geometry never
/// crosses the wire, PROTOCOL.md §5), live focus/session state. On the
/// server, dragging the tile to a side of the desk picks the hand-off edge.
struct DeskWindowView: View {
    @EnvironmentObject private var appState: AppState
    @State private var displays: [DisplayInfo] = Displays.infos()
    /// Tile displacement while the user drags (view points).
    @State private var dragTranslation: CGSize = .zero
    @State private var dragging = false
    /// Edge the tile would snap to if dropped now.
    @State private var previewEdge: EdgeSide?

    private var isServer: Bool { appState.config.role == .server }
    /// Client before the first ENTER has no detected edge yet (R37).
    private var clientEdgeKnown: Bool { appState.clientReturnEdge != nil }
    private var edge: EdgeSide {
        if isServer { return appState.config.edgeSide }
        return appState.clientReturnEdge ?? appState.config.edgeSide.opposite
    }
    private var phase: DeskPhase { appState.deskPhase }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if displays.isEmpty {
                ContentUnavailableView(
                    "Nenhuma tela detectada",
                    systemImage: "display.trianglebadge.exclamationmark"
                )
                .frame(maxWidth: .infinity, minHeight: 320)
            } else {
                canvas
                    .frame(minHeight: 320)
            }
            footer
        }
        .padding(16)
        .frame(minWidth: 560, minHeight: 430)
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didChangeScreenParametersNotification
        )) { _ in
            displays = Displays.infos()
        }
    }

    // MARK: - Canvas

    private var canvas: some View {
        GeometryReader { proxy in
            let geo = DeskModel.geometry(displays: displays, edge: previewEdge ?? edge)
            let pad: CGFloat = 24
            let scale = min(
                (proxy.size.width - pad * 2) / geo.canvas.width,
                (proxy.size.height - pad * 2) / geo.canvas.height
            )
            let origin = CGPoint(
                x: (proxy.size.width - geo.canvas.width * scale) / 2 - geo.canvas.minX * scale,
                y: (proxy.size.height - geo.canvas.height * scale) / 2 - geo.canvas.minY * scale
            )

            ZStack(alignment: .topLeading) {
                ForEach(Array(geo.monitors.enumerated()), id: \.offset) { _, monitor in
                    monitorView(monitor, scale: scale, origin: origin)
                }
                if phase != .empty {
                    edgeHighlight(geo: geo, scale: scale, origin: origin)
                    peerTile(geo: geo, scale: scale, origin: origin)
                }
                if phase == .localFocus || phase == .remoteFocus {
                    focusDot(geo: geo, scale: scale, origin: origin)
                }
                if phase == .empty {
                    emptyOverlay(size: proxy.size)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilitySummary)
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.quaternary.opacity(0.4))
        )
    }

    private func monitorView(_ monitor: MonitorTile, scale: CGFloat, origin: CGPoint) -> some View {
        let rect = scaled(monitor.rect, scale: scale, origin: origin)
        return ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 6)
                .fill(.background)
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(.tertiary, lineWidth: 1)
            // Laptop silhouette: a thicker "deck" along the bottom.
            if monitor.isBuiltin {
                UnevenRoundedRectangle(bottomLeadingRadius: 6, bottomTrailingRadius: 6)
                    .fill(.tertiary)
                    .frame(height: max(4, rect.height * 0.06))
            }
            Text(monitor.name)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.bottom, monitor.isBuiltin ? 8 : 4)
        }
        .frame(width: rect.width, height: rect.height)
        .offset(x: rect.minX, y: rect.minY)
        .opacity(phase == .remoteFocus ? 0.55 : 1)
        .animation(.easeInOut(duration: 0.3), value: phase)
    }

    private func peerTile(geo: DeskGeometry, scale: CGFloat, origin: CGPoint) -> some View {
        let rect = scaled(geo.peer, scale: scale, origin: origin)
        let dashed = phase == .pairing || (!isServer && !clientEdgeKnown)
        return VStack(spacing: 3) {
            Image(systemName: "laptopcomputer")
                .font(.title3)
            Text(appState.peerName)
                .font(.caption.weight(.medium))
                .lineLimit(1)
            Text(peerSubtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .padding(6)
        .frame(width: rect.width, height: max(rect.height, 56))
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.accentColor.opacity(phase == .armed || dashed ? 0.08 : 0.15))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    Color.accentColor.opacity(dashed ? 0.5 : 1),
                    style: StrokeStyle(lineWidth: phase == .remoteFocus ? 2 : 1, dash: dashed ? [5, 4] : [])
                )
        )
        .offset(x: rect.minX + dragTranslation.width, y: rect.minY + dragTranslation.height)
        .animation(dragging ? nil : .easeInOut(duration: 0.3), value: previewEdge ?? edge)
        .gesture(isServer ? dragGesture(geo: geo, scale: scale, origin: origin) : nil)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(appState.peerName), \(edgeDescription(edge))")
    }

    private func dragGesture(geo: DeskGeometry, scale: CGFloat, origin: CGPoint) -> some Gesture {
        DragGesture()
            .onChanged { value in
                dragging = true
                dragTranslation = value.translation
                // Tile center in desk space decides the snap side (R37).
                let viewCenter = CGPoint(
                    x: scaled(geo.peer, scale: scale, origin: origin).midX + value.translation.width,
                    y: scaled(geo.peer, scale: scale, origin: origin).midY + value.translation.height
                )
                let deskPoint = CGPoint(
                    x: (viewCenter.x - origin.x) / scale,
                    y: (viewCenter.y - origin.y) / scale
                )
                previewEdge = DeskModel.edge(
                    fromDrop: deskPoint,
                    union: geo.union,
                    current: appState.config.edgeSide
                )
            }
            .onEnded { _ in
                dragging = false
                dragTranslation = .zero
                if let previewEdge, previewEdge != appState.config.edgeSide {
                    appState.config.edgeSide = previewEdge
                    appState.saveConfig()
                }
                previewEdge = nil
            }
    }

    private func edgeHighlight(geo: DeskGeometry, scale: CGFloat, origin: CGPoint) -> some View {
        let active = previewEdge ?? edge
        let u = geo.union
        let thickness = max(u.width, u.height) * 0.014
        let inset = 0.08
        let deskRect: CGRect = switch active {
        case .right:
            CGRect(x: u.maxX + thickness, y: u.minY + u.height * inset,
                   width: thickness, height: u.height * (1 - inset * 2))
        case .left:
            CGRect(x: u.minX - thickness * 2, y: u.minY + u.height * inset,
                   width: thickness, height: u.height * (1 - inset * 2))
        case .top:
            CGRect(x: u.minX + u.width * inset, y: u.minY - thickness * 2,
                   width: u.width * (1 - inset * 2), height: thickness)
        case .bottom:
            CGRect(x: u.minX + u.width * inset, y: u.maxY + thickness,
                   width: u.width * (1 - inset * 2), height: thickness)
        }
        let rect = scaled(deskRect, scale: scale, origin: origin)
        return Capsule()
            .fill(Color.accentColor)
            .frame(width: max(rect.width, 3), height: max(rect.height, 3))
            .offset(x: rect.minX, y: rect.minY)
            .opacity(phase == .pairing || phase == .armed ? 0.35 : 0.9)
            .animation(.easeInOut(duration: 0.3), value: active)
    }

    private func focusDot(geo: DeskGeometry, scale: CGFloat, origin: CGPoint) -> some View {
        let local = geo.monitors.first(where: \.isBuiltin) ?? geo.monitors[0]
        let target = phase == .remoteFocus ? geo.peer : local.rect
        let center = scaled(target, scale: scale, origin: origin)
        return Circle()
            .fill(Color.accentColor)
            .frame(width: 11, height: 11)
            .overlay(Circle().strokeBorder(.background, lineWidth: 2))
            .position(x: center.midX, y: center.midY)
            .animation(.easeInOut(duration: 0.4), value: phase)
            .allowsHitTesting(false)
    }

    private func emptyOverlay(size: CGSize) -> some View {
        Text(isServer
             ? "Inicie o servidor para ver o outro Mac aqui"
             : "Conecte a um servidor para ver a mesa completa")
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(width: size.width, height: size.height)
    }

    // MARK: - Footer

    @ViewBuilder
    private var footer: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(appState.statusColor)
                .frame(width: 8, height: 8)
            Text(appState.statusText)
                .font(.callout)
                .lineLimit(1)
            Spacer()
            if isServer {
                // Keyboard/VoiceOver path for the same choice the drag makes (R40).
                Picker("Borda", selection: $appState.config.edgeSide) {
                    Text("Esquerda").tag(EdgeSide.left)
                    Text("Direita").tag(EdgeSide.right)
                    Text("Cima").tag(EdgeSide.top)
                    Text("Baixo").tag(EdgeSide.bottom)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 260)
                .onChange(of: appState.config.edgeSide) {
                    appState.saveConfig()
                }
            } else {
                Text("Borda de retorno definida pelo servidor")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        if let hint = appState.crossingHint {
            Label(hint, systemImage: "hand.point.right")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        if isServer && appState.running {
            Text("Mudanças de borda valem ao reiniciar a sessão")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        if case let .error(message) = phase {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    // MARK: - Helpers

    private func scaled(_ rect: CGRect, scale: CGFloat, origin: CGPoint) -> CGRect {
        CGRect(
            x: origin.x + rect.minX * scale,
            y: origin.y + rect.minY * scale,
            width: rect.width * scale,
            height: rect.height * scale
        )
    }

    private var peerSubtitle: String {
        switch phase {
        case .pairing: "aguardando token…"
        case .remoteFocus: "o cursor está aqui"
        default:
            (!isServer && !clientEdgeKnown)
                ? "posição aparece após a primeira travessia"
                : "telas organizadas lá"
        }
    }

    private func edgeDescription(_ edge: EdgeSide) -> String {
        switch edge {
        case .left: "à esquerda das suas telas"
        case .right: "à direita das suas telas"
        case .top: "acima das suas telas"
        case .bottom: "abaixo das suas telas"
        }
    }

    private var accessibilitySummary: String {
        let names = displays.map(\.name).joined(separator: ", ")
        let focus = switch phase {
        case .localFocus: "o foco está neste Mac"
        case .remoteFocus: "controlando \(appState.peerName)"
        case .pairing: "aguardando pareamento"
        case .armed: "aguardando conexão"
        case .empty: "sessão parada"
        case .error: "erro na sessão"
        }
        return "Suas telas: \(names). \(appState.peerName) \(edgeDescription(edge)). Estado: \(focus)."
    }
}
