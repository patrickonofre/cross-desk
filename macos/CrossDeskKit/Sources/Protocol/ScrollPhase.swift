import Foundation

/// Gesture phase of a continuous (trackpad) scroll, PROTOCOL.md §3 (0x23).
/// Neutral wire encoding — each platform maps to/from its native phase constants
/// (macOS `CGScrollPhase`). Unknown wire values decode to `.none` (forward-compat).
public enum ScrollPhase: UInt8, Sendable, Equatable, CaseIterable {
    case none = 0
    case began = 1
    case changed = 2
    case ended = 3
    case cancelled = 4
}

/// Inertial (momentum) phase after the fingers lift, PROTOCOL.md §3 (0x23).
/// Neutral wire encoding — maps to/from macOS `CGMomentumScrollPhase`.
public enum MomentumPhase: UInt8, Sendable, Equatable, CaseIterable {
    case none = 0
    case began = 1
    case changed = 2
    case ended = 3
}
