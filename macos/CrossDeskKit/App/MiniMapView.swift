import SwiftUI
import CrossDeskKit

/// Live desk-at-a-glance for the menubar panel (layout-ux R35): local
/// monitors + peer tile + focus dot, same projection as the Telas window at
/// postage-stamp scale. Tap opens the full editor.
struct MiniMapView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.openWindow) private var openWindow
    @State private var displays: [DisplayInfo] = Displays.infos()

    private var edge: EdgeSide {
        appState.config.role == .server
            ? appState.config.edgeSide
            : (appState.clientReturnEdge ?? appState.config.edgeSide.opposite)
    }
    private var phase: DeskPhase { appState.deskPhase }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            map
                .frame(height: 84)
                .contentShape(RoundedRectangle(cornerRadius: 8))
                .onTapGesture(perform: openDesk)
            Button("Organizar telas…", action: openDesk)
                .buttonStyle(.link)
                .font(.caption)
            if let hint = appState.crossingHint {
                Label(hint, systemImage: "hand.point.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear { displays = Displays.infos() }
    }

    private var map: some View {
        GeometryReader { proxy in
            if displays.isEmpty {
                EmptyView()
            } else {
                let geo = DeskModel.geometry(displays: displays, edge: edge)
                let pad: CGFloat = 10
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
                        let rect = scaled(monitor.rect, scale: scale, origin: origin)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(.background)
                            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(.tertiary, lineWidth: 0.5))
                            .frame(width: rect.width, height: rect.height)
                            .offset(x: rect.minX, y: rect.minY)
                            .opacity(phase == .remoteFocus ? 0.55 : 1)
                    }
                    if phase != .empty {
                        peerRect(geo: geo, scale: scale, origin: origin)
                    }
                    if phase == .localFocus || phase == .remoteFocus {
                        dot(geo: geo, scale: scale, origin: origin)
                    }
                    if case .idle = appState.transferState {} else {
                        transferBadge(size: proxy.size)
                    }
                }
            }
        }
        .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.4)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Mesa: \(appState.statusText). Toque para organizar as telas.")
        .accessibilityAddTraits(.isButton)
    }

    private func peerRect(geo: DeskGeometry, scale: CGFloat, origin: CGPoint) -> some View {
        let rect = scaled(geo.peer, scale: scale, origin: origin)
        let dashed = phase == .pairing
        return RoundedRectangle(cornerRadius: 3)
            .fill(Color.accentColor.opacity(dashed || phase == .armed ? 0.1 : 0.2))
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(
                        Color.accentColor.opacity(dashed ? 0.5 : 0.9),
                        style: StrokeStyle(lineWidth: phase == .remoteFocus ? 1.5 : 0.5, dash: dashed ? [3, 2] : [])
                    )
            )
            .frame(width: rect.width, height: rect.height)
            .offset(x: rect.minX, y: rect.minY)
            .animation(.easeInOut(duration: 0.3), value: edge)
    }

    private func dot(geo: DeskGeometry, scale: CGFloat, origin: CGPoint) -> some View {
        let local = geo.monitors.first(where: \.isBuiltin) ?? geo.monitors[0]
        let target = phase == .remoteFocus ? geo.peer : local.rect
        let rect = scaled(target, scale: scale, origin: origin)
        return Circle()
            .fill(Color.accentColor)
            .frame(width: 7, height: 7)
            .position(x: rect.midX, y: rect.midY)
            .animation(.easeInOut(duration: 0.4), value: phase)
    }

    private func transferBadge(size: CGSize) -> some View {
        Image(systemName: "arrow.left.arrow.right.circle.fill")
            .font(.caption)
            .foregroundStyle(Color.accentColor)
            .position(x: size.width - 14, y: 14)
            .accessibilityLabel("Transferência de arquivos em andamento")
    }

    private func scaled(_ rect: CGRect, scale: CGFloat, origin: CGPoint) -> CGRect {
        CGRect(
            x: origin.x + rect.minX * scale,
            y: origin.y + rect.minY * scale,
            width: rect.width * scale,
            height: rect.height * scale
        )
    }

    private func openDesk() {
        openWindow(id: "desk")
        // LSUIElement app: without activation the window opens behind
        // whatever is frontmost.
        NSApp.activate()
    }
}
