import XCTest
@testable import CrossDeskKit

final class HIDKeycodesTests: XCTestCase {

    func testNoDuplicateEntries() {
        // Dictionary(uniqueKeysWithValues:) traps on duplicates at first use;
        // this also pins the expected table size.
        XCTAssertEqual(HIDKeycodes.entryCount, 116)
        XCTAssertNotNil(HIDKeycodes.hidUsage(forMacKeycode: 0x00))
    }

    func testRoundTripIdentityForEveryEntry() {
        for mac in UInt16(0)...0x7F {
            guard let hid = HIDKeycodes.hidUsage(forMacKeycode: mac) else { continue }
            XCTAssertEqual(
                HIDKeycodes.macKeycode(forHIDUsage: hid), mac,
                "round-trip broken for mac keycode 0x\(String(mac, radix: 16))"
            )
        }
    }

    func testWellKnownMappings() {
        XCTAssertEqual(HIDKeycodes.hidUsage(forMacKeycode: 0x00), 0x04) // A
        XCTAssertEqual(HIDKeycodes.hidUsage(forMacKeycode: 0x31), 0x2C) // Space
        XCTAssertEqual(HIDKeycodes.hidUsage(forMacKeycode: 0x24), 0x28) // Return
        XCTAssertEqual(HIDKeycodes.hidUsage(forMacKeycode: 0x35), 0x29) // Escape
        XCTAssertEqual(HIDKeycodes.hidUsage(forMacKeycode: 0x7B), 0x50) // LeftArrow
    }

    func testAllEightModifiersMapped() {
        let expected: [(mac: UInt16, hid: UInt16)] = [
            (0x3B, 0xE0), (0x38, 0xE1), (0x3A, 0xE2), (0x37, 0xE3),
            (0x3E, 0xE4), (0x3C, 0xE5), (0x3D, 0xE6), (0x36, 0xE7),
        ]
        for entry in expected {
            XCTAssertEqual(HIDKeycodes.hidUsage(forMacKeycode: entry.mac), entry.hid)
            XCTAssertTrue(HIDKeycodes.modifierUsages.contains(entry.hid))
        }
    }

    func testConsumerPageKeysAreUnmapped() {
        XCTAssertNil(HIDKeycodes.hidUsage(forMacKeycode: 0x3F)) // Fn
        XCTAssertNil(HIDKeycodes.hidUsage(forMacKeycode: 0x48)) // VolumeUp
        XCTAssertNil(HIDKeycodes.hidUsage(forMacKeycode: 0x49)) // VolumeDown
        XCTAssertNil(HIDKeycodes.hidUsage(forMacKeycode: 0x4A)) // Mute
    }
}
