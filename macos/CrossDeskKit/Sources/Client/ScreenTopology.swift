import Foundation
import CoreGraphics

/// Client-side cursor geometry across ALL local displays (R6). The client is
/// the sole owner of its topology: ENTER positions are mapped locally, the
/// cursor is contained to real display areas (sliding along edges, crossing
/// into adjacent monitors), and the return edge is detected here — the server
/// never learns this machine's resolution or layout (PROTOCOL.md §5).
public struct ScreenTopology: Sendable {
    public let screens: [CGRect]
    /// Union bounding box of all displays.
    public let union: CGRect

    /// Distance (px) the cursor is kept inside edges after entry/clamping.
    private static let inset: CGFloat = 1.0

    public init(screens: [CGRect]) {
        self.screens = screens.isEmpty ? [CGRect(x: 0, y: 0, width: 1, height: 1)] : screens
        self.union = self.screens.dropFirst().reduce(self.screens[0]) { $0.union($1) }
    }

    // MARK: - Entry

    /// Maps a normalized ENTER position (0...1 over the union bounding box)
    /// onto a concrete point just inside the entry edge. Landing in a gap of a
    /// non-rectangular layout snaps to the nearest display.
    public func entryPoint(edge: EdgeSide, x: CGFloat, y: CGFloat) -> CGPoint {
        var point: CGPoint
        switch edge {
        case .left:
            point = CGPoint(x: union.minX + Self.inset, y: union.minY + y.clamped01 * union.height)
        case .right:
            point = CGPoint(x: union.maxX - Self.inset, y: union.minY + y.clamped01 * union.height)
        case .top:
            point = CGPoint(x: union.minX + x.clamped01 * union.width, y: union.minY + Self.inset)
        case .bottom:
            point = CGPoint(x: union.minX + x.clamped01 * union.width, y: union.maxY - Self.inset)
        }
        if let screen = screens.first(where: { $0.contains(point) }) {
            return clamp(point, into: screen)
        }
        return clamp(point, into: nearestScreen(to: point))
    }

    // MARK: - Movement

    /// Applies a delta to `position`. The cursor stays inside real displays:
    /// free movement when the target lands on any display, edge sliding and
    /// per-axis clamping otherwise. When the *raw* target escapes through the
    /// outer edge on `returnEdge`, `exit` carries the position normalized on
    /// the exited display (the exiting axis pinned to 0/1) for LEAVE_REQUEST.
    /// Repeated outward moves at the edge keep reporting the exit — that is
    /// the retry mechanism for a lost LEAVE_REQUEST datagram.
    public func move(
        from position: CGPoint, dx: CGFloat, dy: CGFloat, returnEdge: EdgeSide?
    ) -> (position: CGPoint, exit: CGPoint?) {
        let raw = CGPoint(x: position.x + dx, y: position.y + dy)
        if let screen = screens.first(where: { $0.contains(raw) }) {
            return (clamp(raw, into: screen), nil)
        }

        let current = screens.first(where: { $0.contains(position) }) ?? nearestScreen(to: position)

        // Escaped through the return edge? Only an *outer* edge counts — if
        // another display continues past it, the cursor just changes monitor.
        if let returnEdge, let exit = exitPosition(raw: raw, edge: returnEdge, of: current) {
            return (clamp(raw, into: current), exit)
        }

        // Slide: keep the axis that still lands on some display, clamp the other.
        let clamped = clamp(raw, into: current)
        let slideX = CGPoint(x: raw.x, y: clamped.y)
        if let screen = screens.first(where: { $0.contains(slideX) }) {
            return (clamp(slideX, into: screen), nil)
        }
        let slideY = CGPoint(x: clamped.x, y: raw.y)
        if let screen = screens.first(where: { $0.contains(slideY) }) {
            return (clamp(slideY, into: screen), nil)
        }
        return (clamped, nil)
    }

    // MARK: - Internals

    /// Non-nil when `raw` is strictly beyond `edge` of `screen` and no other
    /// display continues past that edge at the crossing point.
    private func exitPosition(raw: CGPoint, edge: EdgeSide, of screen: CGRect) -> CGPoint? {
        let beyond: Bool
        var probe = raw
        switch edge {
        case .left:
            beyond = raw.x < screen.minX
            probe.x = screen.minX - Self.inset
        case .right:
            beyond = raw.x >= screen.maxX
            probe.x = screen.maxX + Self.inset
        case .top:
            beyond = raw.y < screen.minY
            probe.y = screen.minY - Self.inset
        case .bottom:
            beyond = raw.y >= screen.maxY
            probe.y = screen.maxY + Self.inset
        }
        guard beyond else { return nil }
        probe.x = min(max(probe.x, screen.minX - Self.inset), screen.maxX + Self.inset)
        probe.y = min(max(probe.y, screen.minY - Self.inset), screen.maxY + Self.inset)
        if screens.contains(where: { $0 != screen && $0.contains(probe) }) { return nil }

        let nx = ((raw.x - screen.minX) / screen.width).clamped01
        let ny = ((raw.y - screen.minY) / screen.height).clamped01
        switch edge {
        case .left: return CGPoint(x: 0.0, y: ny)
        case .right: return CGPoint(x: 1.0, y: ny)
        case .top: return CGPoint(x: nx, y: 0.0)
        case .bottom: return CGPoint(x: nx, y: 1.0)
        }
    }

    private func clamp(_ point: CGPoint, into screen: CGRect) -> CGPoint {
        CGPoint(
            x: min(max(point.x, screen.minX), screen.maxX - Self.inset),
            y: min(max(point.y, screen.minY), screen.maxY - Self.inset)
        )
    }

    private func nearestScreen(to point: CGPoint) -> CGRect {
        screens.min(by: { distanceSquared(point, to: $0) < distanceSquared(point, to: $1) })!
    }

    private func distanceSquared(_ point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return dx * dx + dy * dy
    }
}
