import Foundation
import CoreGraphics

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

extension CGFloat {
    var clamped01: CGFloat { Swift.min(1.0, Swift.max(0.0, self)) }
}
