import Foundation

/// Tracks which keys are logically pressed on the client so they can be
/// released synthetically on LEAVE or disconnect (R7 — never leave a stuck
/// modifier behind).
public struct PressedKeys: Equatable, Sendable {
    private var pressed: Set<UInt16> = []

    public init() {}

    /// Records a key event. Repeated key-downs are idempotent.
    public mutating func handle(hidUsage: UInt16, isDown: Bool) {
        if isDown {
            pressed.insert(hidUsage)
        } else {
            pressed.remove(hidUsage)
        }
    }

    public var currentlyPressed: Set<UInt16> { pressed }

    /// Returns every key still held (modifiers last, so releasing e.g. ⌘V
    /// emits V-up before ⌘-up) and clears the state.
    public mutating func drainReleases() -> [UInt16] {
        let keys = pressed.sorted { a, b in
            let aIsModifier = HIDKeycodes.modifierUsages.contains(a)
            let bIsModifier = HIDKeycodes.modifierUsages.contains(b)
            if aIsModifier != bIsModifier { return !aIsModifier }
            return a < b
        }
        pressed.removeAll()
        return keys
    }
}
