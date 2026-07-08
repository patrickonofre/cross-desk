import XCTest
@testable import CrossDeskKit

final class UpdateCheckerTests: XCTestCase {
    // MARK: - isNewer

    func testIsNewer_greaterPatch() {
        XCTAssertTrue(UpdateChecker.isNewer("v1.0.1", than: "1.0.0"))
    }

    func testIsNewer_equalIsNotNewer() {
        XCTAssertFalse(UpdateChecker.isNewer("1.0.0", than: "1.0.0"))
    }

    func testIsNewer_lesserIsNotNewer() {
        XCTAssertFalse(UpdateChecker.isNewer("0.9.0", than: "1.0.0"))
    }

    func testIsNewer_vPrefixIgnored() {
        XCTAssertTrue(UpdateChecker.isNewer("v2.0.0", than: "1.9.9"))
    }

    func testIsNewer_prereleaseSuffixStripped() {
        // Tag has "-beta.3" but the numeric part ties the installed version —
        // must not read as newer just because the string differs.
        XCTAssertFalse(UpdateChecker.isNewer("1.0.0-beta.3", than: "1.0.0"))
    }

    func testIsNewer_malformedTagIsNeverNewer() {
        XCTAssertFalse(UpdateChecker.isNewer("not-a-version", than: "1.0.0"))
        XCTAssertFalse(UpdateChecker.isNewer("", than: "1.0.0"))
    }

    func testIsNewer_differentComponentCountsPadWithZero() {
        XCTAssertFalse(UpdateChecker.isNewer("1.2", than: "1.2.0"))
        XCTAssertTrue(UpdateChecker.isNewer("1.2.1", than: "1.2"))
    }

    func testIsNewer_numericCompareNotLexicographic() {
        // A string compare would rank "1.10.0" below "1.9.0" — this is the
        // exact bug class Sparkle's own comparator avoids.
        XCTAssertTrue(UpdateChecker.isNewer("1.10.0", than: "1.9.0"))
    }
}
