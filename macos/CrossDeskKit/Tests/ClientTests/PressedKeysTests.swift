import XCTest
@testable import CrossDeskKit

final class PressedKeysTests: XCTestCase {
    func testDrainReleasesNonModifiersBeforeModifiers() {
        var keys = PressedKeys()
        keys.handle(hidUsage: 0xE3, isDown: true) // Command
        keys.handle(hidUsage: 0x19, isDown: true) // V
        keys.handle(hidUsage: 0xE1, isDown: true) // Shift

        let releases = keys.drainReleases()
        XCTAssertEqual(releases, [0x19, 0xE1, 0xE3])
        XCTAssertTrue(keys.currentlyPressed.isEmpty)
    }

    func testKeyUpRemovesFromTracking() {
        var keys = PressedKeys()
        keys.handle(hidUsage: 0x04, isDown: true)
        keys.handle(hidUsage: 0x04, isDown: false)
        XCTAssertEqual(keys.drainReleases(), [])
    }

    func testRepeatedKeyDownIsIdempotent() {
        var keys = PressedKeys()
        keys.handle(hidUsage: 0x04, isDown: true)
        keys.handle(hidUsage: 0x04, isDown: true) // key-repeat
        XCTAssertEqual(keys.drainReleases(), [0x04])
    }

    func testDrainOnEmptyStateIsEmpty() {
        var keys = PressedKeys()
        XCTAssertEqual(keys.drainReleases(), [])
    }
}
