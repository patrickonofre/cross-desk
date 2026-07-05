import Foundation
import CoreGraphics
import AppKit

/// One local display as the desk UI draws it (layout-ux R36).
public struct DisplayInfo: Equatable, Sendable {
    /// CG global coordinates (same space as `Displays.activeBounds()`).
    public let bounds: CGRect
    /// Built-in panel (laptop) — drawn with a base silhouette.
    public let isBuiltin: Bool
    /// User-facing name ("Built-in Retina Display", "Studio Display").
    public let name: String

    public init(bounds: CGRect, isBuiltin: Bool, name: String) {
        self.bounds = bounds
        self.isBuiltin = isBuiltin
        self.name = name
    }
}

/// Local display topology (CG global coordinates). Shared by server (edge
/// detection) and client (cursor containment) — each machine only ever reads
/// its own; topology never crosses the wire.
public enum Displays {
    public static func activeBounds() -> [CGRect] {
        activeIDs().map(CGDisplayBounds)
    }

    /// Per-display info for the desk canvas/mini-map (layout-ux R36). Same CG
    /// list as `activeBounds()`; names resolved via NSScreen when available.
    public static func infos() -> [DisplayInfo] {
        let names = screenNames()
        return activeIDs().map { id in
            DisplayInfo(
                bounds: CGDisplayBounds(id),
                isBuiltin: CGDisplayIsBuiltin(id) != 0,
                name: names[id] ?? "Monitor"
            )
        }
    }

    private static func activeIDs() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &displays, &count)
        return displays
    }

    private static func screenNames() -> [CGDirectDisplayID: String] {
        var result: [CGDirectDisplayID: String] = [:]
        for screen in NSScreen.screens {
            let key = NSDeviceDescriptionKey("NSScreenNumber")
            guard let number = screen.deviceDescription[key] as? NSNumber else { continue }
            result[CGDirectDisplayID(number.uint32Value)] = screen.localizedName
        }
        return result
    }
}
