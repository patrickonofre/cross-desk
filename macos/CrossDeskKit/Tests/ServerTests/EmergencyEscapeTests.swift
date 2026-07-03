import XCTest
@testable import CrossDeskKit

final class EmergencyEscapeTests: XCTestCase {
    func testThreePressesWithinWindowFires() {
        var escape = EmergencyEscape()
        XCTAssertFalse(escape.registerEscapeDown(at: 10.0))
        XCTAssertFalse(escape.registerEscapeDown(at: 10.3))
        XCTAssertTrue(escape.registerEscapeDown(at: 10.6))
    }

    func testSlowPressesNeverFire() {
        var escape = EmergencyEscape()
        XCTAssertFalse(escape.registerEscapeDown(at: 10.0))
        XCTAssertFalse(escape.registerEscapeDown(at: 11.1))
        XCTAssertFalse(escape.registerEscapeDown(at: 12.2))
        XCTAssertFalse(escape.registerEscapeDown(at: 13.3))
    }

    func testOldPressesExpireFromWindow() {
        var escape = EmergencyEscape()
        XCTAssertFalse(escape.registerEscapeDown(at: 10.0))
        XCTAssertFalse(escape.registerEscapeDown(at: 10.2))
        // 11.5: first two are outside the 1 s window now
        XCTAssertFalse(escape.registerEscapeDown(at: 11.5))
        XCTAssertFalse(escape.registerEscapeDown(at: 11.7))
        XCTAssertTrue(escape.registerEscapeDown(at: 11.9))
    }

    func testResetsAfterFiring() {
        var escape = EmergencyEscape()
        _ = escape.registerEscapeDown(at: 1.0)
        _ = escape.registerEscapeDown(at: 1.1)
        XCTAssertTrue(escape.registerEscapeDown(at: 1.2))
        // Sequence consumed — the next press starts from scratch.
        XCTAssertFalse(escape.registerEscapeDown(at: 1.3))
        XCTAssertFalse(escape.registerEscapeDown(at: 1.4))
        XCTAssertTrue(escape.registerEscapeDown(at: 1.5))
    }
}
