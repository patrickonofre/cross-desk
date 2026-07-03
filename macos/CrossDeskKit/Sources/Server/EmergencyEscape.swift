import Foundation

/// Emergency escape hatch (R4): pressing Esc 3 times within 1 second always
/// returns control to the server, even with the network gone. Pure logic —
/// the capture layer feeds it Esc key-down timestamps.
public struct EmergencyEscape: Sendable {
    public static let requiredPresses = 3
    public static let window: TimeInterval = 1.0

    private var timestamps: [TimeInterval] = []

    public init() {}

    /// Registers an Esc key-down. Returns true when the sequence fired
    /// (and resets, so holding Esc doesn't re-trigger).
    public mutating func registerEscapeDown(at time: TimeInterval) -> Bool {
        timestamps.append(time)
        timestamps.removeAll { time - $0 > Self.window }
        if timestamps.count >= Self.requiredPresses {
            timestamps.removeAll()
            return true
        }
        return false
    }
}
