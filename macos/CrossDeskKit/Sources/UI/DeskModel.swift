import Foundation
import CoreGraphics

/// One monitor tile in desk space (union-origin points, y down like CG).
public struct MonitorTile: Equatable, Sendable {
    public let rect: CGRect
    public let isBuiltin: Bool
    public let name: String

    public init(rect: CGRect, isBuiltin: Bool, name: String) {
        self.rect = rect
        self.isBuiltin = isBuiltin
        self.name = name
    }
}

/// Visual phase of the desk canvas/mini-map (layout-ux R38). Derived from
/// session state on every render — never stored.
public enum DeskPhase: Equatable, Sendable {
    case empty
    case pairing
    case armed
    case localFocus
    case remoteFocus
    case error(String)
}

/// Everything the desk views draw, in one abstract "desk space": monitors at
/// union origin, peer slot beside the chosen edge. Views only scale-to-fit —
/// all geometry decisions live here (testable without GUI).
public struct DeskGeometry: Equatable, Sendable {
    public let monitors: [MonitorTile]
    /// Union of the local monitors, origin (0,0).
    public let union: CGRect
    /// Abstract peer tile (16:10 — real peer geometry never crosses the wire,
    /// PROTOCOL.md §5).
    public let peer: CGRect
    /// Bounding box of monitors + peer; views fit this rect.
    public let canvas: CGRect
}

public enum DeskModel {
    /// Fraction of the union width the peer tile takes.
    static let peerWidthRatio: CGFloat = 0.42
    static let peerAspect: CGFloat = 0.625
    static let gapRatio: CGFloat = 0.05

    public static func geometry(displays: [DisplayInfo], edge: EdgeSide) -> DeskGeometry {
        let bounds = displays.map(\.bounds)
        let minX = bounds.map(\.minX).min() ?? 0
        let minY = bounds.map(\.minY).min() ?? 0
        let maxX = bounds.map(\.maxX).max() ?? 1
        let maxY = bounds.map(\.maxY).max() ?? 1
        let union = CGRect(x: 0, y: 0, width: max(maxX - minX, 1), height: max(maxY - minY, 1))
        let monitors = displays.map {
            MonitorTile(
                rect: $0.bounds.offsetBy(dx: -minX, dy: -minY),
                isBuiltin: $0.isBuiltin,
                name: $0.name
            )
        }
        let peer = peerSlot(edge: edge, union: union)
        return DeskGeometry(
            monitors: monitors,
            union: union,
            peer: peer,
            canvas: union.union(peer)
        )
    }

    public static func peerSlot(edge: EdgeSide, union: CGRect) -> CGRect {
        let w = union.width * peerWidthRatio
        let h = w * peerAspect
        let gap = max(union.width, union.height) * gapRatio
        switch edge {
        case .right:
            return CGRect(x: union.maxX + gap, y: union.midY - h / 2, width: w, height: h)
        case .left:
            return CGRect(x: union.minX - gap - w, y: union.midY - h / 2, width: w, height: h)
        case .top:
            return CGRect(x: union.midX - w / 2, y: union.minY - gap - h, width: w, height: h)
        case .bottom:
            return CGRect(x: union.midX - w / 2, y: union.maxY + gap, width: w, height: h)
        }
    }

    /// Which edge a dropped peer-tile center lands on. Inside the union (or a
    /// tie with the current edge) keeps the current one — a drop never
    /// produces an invalid state.
    public static func edge(fromDrop point: CGPoint, union: CGRect, current: EdgeSide) -> EdgeSide {
        let distances: [(EdgeSide, CGFloat)] = [
            (.left, union.minX - point.x),
            (.right, point.x - union.maxX),
            (.top, union.minY - point.y),
            (.bottom, point.y - union.maxY)
        ]
        guard let best = distances.map(\.1).max(), best > 0 else { return current }
        if distances.first(where: { $0.0 == current })?.1 == best { return current }
        return distances.first(where: { $0.1 == best })!.0
    }

    /// R38 phase table. `focusedHere` only matters while connected: the server
    /// passes `true` (its `connected` means the cursor is local; REMOTE has its
    /// own state), the client passes its ENTER/LEAVE-derived flag.
    public static func phase(
        sessionState: SessionState,
        paired: Bool,
        focusedHere: Bool
    ) -> DeskPhase {
        switch sessionState {
        case .stopped: .empty
        case .waitingPeer: paired ? .armed : .pairing
        case .connected: focusedHere ? .localFocus : .remoteFocus
        case .controllingRemote: .remoteFocus
        case let .error(message): .error(message)
        }
    }

    /// One-time crossing hint (R39): shown from pairing until the first
    /// handoff, gone forever after.
    public static func crossingHint(
        phase: DeskPhase,
        edge: EdgeSide,
        firstCrossingDone: Bool
    ) -> String? {
        guard !firstCrossingDone else { return nil }
        switch phase {
        case .armed, .localFocus:
            let side = switch edge {
            case .left: "esquerda"
            case .right: "direita"
            case .top: "de cima"
            case .bottom: "de baixo"
            }
            return "Empurre o cursor pela borda \(side) para atravessar"
        default:
            return nil
        }
    }
}
