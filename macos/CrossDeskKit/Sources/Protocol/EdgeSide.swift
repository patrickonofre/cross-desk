import Foundation

/// A screen edge. Protocol-level: crosses the wire in ENTER (PROTOCOL.md §3)
/// and drives edge configuration and geometry on both sides.
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

    /// Wire encoding (PROTOCOL.md §3: 0=left, 1=right, 2=top, 3=bottom).
    public var wireValue: UInt8 {
        switch self {
        case .left: 0
        case .right: 1
        case .top: 2
        case .bottom: 3
        }
    }

    public init?(wireValue: UInt8) {
        switch wireValue {
        case 0: self = .left
        case 1: self = .right
        case 2: self = .top
        case 3: self = .bottom
        default: return nil
        }
    }
}
