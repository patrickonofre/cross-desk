import Foundation
import CoreGraphics

/// Local display topology (CG global coordinates). Shared by server (edge
/// detection) and client (cursor containment) — each machine only ever reads
/// its own; topology never crosses the wire.
public enum Displays {
    public static func activeBounds() -> [CGRect] {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &displays, &count)
        return displays.map(CGDisplayBounds)
    }
}
