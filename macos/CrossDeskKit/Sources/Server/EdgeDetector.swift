import Foundation
import CoreGraphics

/// Which edge of the server's displays hands control to the client.
public enum EdgeSide: String, Codable, Equatable, Sendable, CaseIterable {
    case left, right, top, bottom

    /// The client edge the cursor enters from (server right → client left, etc.).
    public var opposite: EdgeSide {
        switch self {
        case .left: .right
        case .right: .left
        case .top: .bottom
        case .bottom: .top
        }
    }
}

/// Server-side edge crossing detection, pure geometry (testable headless).
///
/// A crossing only triggers on an *outer* edge: if another server display sits
/// beyond the edge being touched, the cursor is just moving between monitors.
public struct EdgeDetector: Sendable {
    public let side: EdgeSide
    /// Cursor must be within this distance (px) of the edge to trigger.
    public let threshold: CGFloat

    public init(side: EdgeSide, threshold: CGFloat = 1.0) {
        self.side = side
        self.threshold = threshold
    }

    /// If `point` (global coordinates) touches the configured outer edge of the
    /// display that contains it, returns the client entry position, normalized
    /// 0...1 along both axes of the client screen (PROTOCOL.md §3, ENTER).
    public func crossing(at point: CGPoint, in screens: [CGRect]) -> CGPoint? {
        guard let screen = screens.first(where: { $0.insetBy(dx: -threshold, dy: -threshold).contains(point) })
        else { return nil }

        let atEdge: Bool
        var probe = point
        switch side {
        case .left:
            atEdge = point.x <= screen.minX + threshold
            probe.x = screen.minX - threshold * 2
        case .right:
            atEdge = point.x >= screen.maxX - threshold
            probe.x = screen.maxX + threshold * 2
        case .top:
            atEdge = point.y <= screen.minY + threshold
            probe.y = screen.minY - threshold * 2
        case .bottom:
            atEdge = point.y >= screen.maxY - threshold
            probe.y = screen.maxY + threshold * 2
        }
        guard atEdge else { return nil }

        // Inner edge? Another display continues past it — no crossing.
        if screens.contains(where: { $0 != screen && $0.contains(probe) }) { return nil }

        // Entry position on the client: same normalized coordinate along the
        // edge, starting at the opposite side.
        let ny = (point.y - screen.minY) / screen.height
        let nx = (point.x - screen.minX) / screen.width
        switch side {
        case .left: return CGPoint(x: 1.0, y: ny.clamped01)
        case .right: return CGPoint(x: 0.0, y: ny.clamped01)
        case .top: return CGPoint(x: nx.clamped01, y: 1.0)
        case .bottom: return CGPoint(x: nx.clamped01, y: 0.0)
        }
    }
}

/// Tracks where the cursor "is" on the client while control is remote.
///
/// The client's real resolution never crosses the wire; deltas are normalized
/// using the *server* screen size as a scale proxy (PROTOCOL.md §5). With
/// dissimilar resolutions the speed mapping distorts slightly — accepted for
/// the MVP (context.md #8).
public struct VirtualCursor: Sendable {
    /// Normalized position on the client screen, 0...1.
    public private(set) var position: CGPoint
    /// The client edge that returns control to the server.
    public let returnSide: EdgeSide

    public init(entry: CGPoint, serverSide: EdgeSide) {
        self.position = entry
        self.returnSide = serverSide.opposite
    }

    /// Applies a pixel delta (scaled by `scale`, the server screen size).
    /// Returns the normalized exit coordinate along the return edge when the
    /// virtual cursor leaves through it; nil while control stays remote.
    public mutating func apply(dx: CGFloat, dy: CGFloat, scale: CGSize) -> CGFloat? {
        position.x += dx / scale.width
        position.y += dy / scale.height

        let exited: Bool
        switch returnSide {
        case .left: exited = position.x < 0
        case .right: exited = position.x > 1
        case .top: exited = position.y < 0
        case .bottom: exited = position.y > 1
        }

        position.x = position.x.clamped01
        position.y = position.y.clamped01

        guard exited else { return nil }
        switch returnSide {
        case .left, .right: return position.y
        case .top, .bottom: return position.x
        }
    }
}

extension CGFloat {
    fileprivate var clamped01: CGFloat { Swift.min(1.0, Swift.max(0.0, self)) }
}
