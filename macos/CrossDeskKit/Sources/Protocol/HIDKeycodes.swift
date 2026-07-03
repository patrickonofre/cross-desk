import Foundation

/// Bidirectional mapping between macOS virtual keycodes (CGKeyCode, Carbon
/// `Events.h` kVK_*) and USB HID Usage IDs, Usage Page 0x07 (Keyboard/Keypad).
/// The wire protocol only carries HID usages (PROTOCOL.md §4).
///
/// Media/consumer keys (volume, brightness, Fn) live on other HID usage pages
/// and are intentionally unmapped in the MVP.
public enum HIDKeycodes {
    /// (macKeycode, hidUsage)
    private static let table: [(mac: UInt16, hid: UInt16)] = [
        // Letters
        (0x00, 0x04), // A
        (0x0B, 0x05), // B
        (0x08, 0x06), // C
        (0x02, 0x07), // D
        (0x0E, 0x08), // E
        (0x03, 0x09), // F
        (0x05, 0x0A), // G
        (0x04, 0x0B), // H
        (0x22, 0x0C), // I
        (0x26, 0x0D), // J
        (0x28, 0x0E), // K
        (0x25, 0x0F), // L
        (0x2E, 0x10), // M
        (0x2D, 0x11), // N
        (0x1F, 0x12), // O
        (0x23, 0x13), // P
        (0x0C, 0x14), // Q
        (0x0F, 0x15), // R
        (0x01, 0x16), // S
        (0x11, 0x17), // T
        (0x20, 0x18), // U
        (0x09, 0x19), // V
        (0x0D, 0x1A), // W
        (0x07, 0x1B), // X
        (0x10, 0x1C), // Y
        (0x06, 0x1D), // Z
        // Number row
        (0x12, 0x1E), // 1
        (0x13, 0x1F), // 2
        (0x14, 0x20), // 3
        (0x15, 0x21), // 4
        (0x17, 0x22), // 5
        (0x16, 0x23), // 6
        (0x1A, 0x24), // 7
        (0x1C, 0x25), // 8
        (0x19, 0x26), // 9
        (0x1D, 0x27), // 0
        // Controls & punctuation
        (0x24, 0x28), // Return
        (0x35, 0x29), // Escape
        (0x33, 0x2A), // Delete (backspace)
        (0x30, 0x2B), // Tab
        (0x31, 0x2C), // Space
        (0x1B, 0x2D), // Minus
        (0x18, 0x2E), // Equal
        (0x21, 0x2F), // LeftBracket
        (0x1E, 0x30), // RightBracket
        (0x2A, 0x31), // Backslash
        (0x29, 0x33), // Semicolon
        (0x27, 0x34), // Quote
        (0x32, 0x35), // Grave
        (0x2B, 0x36), // Comma
        (0x2F, 0x37), // Period
        (0x2C, 0x38), // Slash
        (0x39, 0x39), // CapsLock
        // Function keys
        (0x7A, 0x3A), // F1
        (0x78, 0x3B), // F2
        (0x63, 0x3C), // F3
        (0x76, 0x3D), // F4
        (0x60, 0x3E), // F5
        (0x61, 0x3F), // F6
        (0x62, 0x40), // F7
        (0x64, 0x41), // F8
        (0x65, 0x42), // F9
        (0x6D, 0x43), // F10
        (0x67, 0x44), // F11
        (0x6F, 0x45), // F12
        (0x69, 0x68), // F13
        (0x6B, 0x69), // F14
        (0x71, 0x6A), // F15
        (0x6A, 0x6B), // F16
        (0x40, 0x6C), // F17
        (0x4F, 0x6D), // F18
        (0x50, 0x6E), // F19
        (0x5A, 0x6F), // F20
        // Navigation
        (0x72, 0x49), // Help → Insert (pragmatic cross-OS mapping)
        (0x73, 0x4A), // Home
        (0x74, 0x4B), // PageUp
        (0x75, 0x4C), // ForwardDelete
        (0x77, 0x4D), // End
        (0x79, 0x4E), // PageDown
        (0x7C, 0x4F), // RightArrow
        (0x7B, 0x50), // LeftArrow
        (0x7D, 0x51), // DownArrow
        (0x7E, 0x52), // UpArrow
        // Keypad
        (0x47, 0x53), // KeypadClear → NumLock/Clear
        (0x4B, 0x54), // KeypadDivide
        (0x43, 0x55), // KeypadMultiply
        (0x4E, 0x56), // KeypadMinus
        (0x45, 0x57), // KeypadPlus
        (0x4C, 0x58), // KeypadEnter
        (0x53, 0x59), // Keypad1
        (0x54, 0x5A), // Keypad2
        (0x55, 0x5B), // Keypad3
        (0x56, 0x5C), // Keypad4
        (0x57, 0x5D), // Keypad5
        (0x58, 0x5E), // Keypad6
        (0x59, 0x5F), // Keypad7
        (0x5B, 0x60), // Keypad8
        (0x5C, 0x61), // Keypad9
        (0x52, 0x62), // Keypad0
        (0x41, 0x63), // KeypadDecimal
        (0x51, 0x67), // KeypadEquals
        // International
        (0x0A, 0x64), // ISO_Section (Non-US backslash)
        (0x5E, 0x87), // JIS_Underscore (International1)
        (0x5F, 0x85), // JIS_KeypadComma (Keypad Comma)
        (0x5D, 0x89), // JIS_Yen (International3)
        (0x68, 0x90), // JIS_Kana (LANG1)
        (0x66, 0x91), // JIS_Eisu (LANG2)
        // Misc
        (0x6E, 0x65), // ContextualMenu → Application
        // Modifiers
        (0x3B, 0xE0), // Control
        (0x38, 0xE1), // Shift
        (0x3A, 0xE2), // Option
        (0x37, 0xE3), // Command
        (0x3E, 0xE4), // RightControl
        (0x3C, 0xE5), // RightShift
        (0x3D, 0xE6), // RightOption
        (0x36, 0xE7), // RightCommand
    ]

    private static let macToHID: [UInt16: UInt16] = Dictionary(
        uniqueKeysWithValues: table.map { ($0.mac, $0.hid) }
    )
    private static let hidToMac: [UInt16: UInt16] = Dictionary(
        uniqueKeysWithValues: table.map { ($0.hid, $0.mac) }
    )

    /// HID usages of modifier keys (LeftControl...RightGUI).
    public static let modifierUsages: ClosedRange<UInt16> = 0xE0...0xE7

    public static func hidUsage(forMacKeycode keycode: UInt16) -> UInt16? {
        macToHID[keycode]
    }

    public static func macKeycode(forHIDUsage usage: UInt16) -> UInt16? {
        hidToMac[usage]
    }

    /// Exposed for consistency tests only.
    static var entryCount: Int { table.count }
}
