import XCTest
@testable import CrossDeskKit

final class PairingKeyTests: XCTestCase {
    func testGeneratedCodeFormat() {
        let code = PairingKey.generateCode()
        XCTAssertEqual(code.count, 32)
        XCTAssertTrue(code.allSatisfy { $0.isHexDigit && ($0.isNumber || $0.isLowercase) })
    }

    func testGeneratedCodesAreUnique() {
        XCTAssertNotEqual(PairingKey.generateCode(), PairingKey.generateCode())
    }

    func testPSKIsDeterministic() {
        let code = "0123456789abcdef0123456789abcdef"
        XCTAssertEqual(PairingKey.psk(fromCode: code), PairingKey.psk(fromCode: code))
        XCTAssertEqual(PairingKey.psk(fromCode: code).count, 32)
    }

    func testDifferentCodesYieldDifferentPSKs() {
        XCTAssertNotEqual(
            PairingKey.psk(fromCode: "0123456789abcdef0123456789abcdef"),
            PairingKey.psk(fromCode: "fedcba9876543210fedcba9876543210")
        )
    }

    func testCodeIsNormalizedBeforeDerivation() {
        // Codes travel between machines via chat/notes and pick up whitespace
        // and case changes — none of that may change the PSK.
        let canonical = PairingKey.psk(fromCode: "0123456789abcdef0123456789abcdef")
        XCTAssertEqual(PairingKey.psk(fromCode: " 0123456789abcdef0123456789abcdef\n"), canonical)
        XCTAssertEqual(PairingKey.psk(fromCode: "0123456789ABCDEF0123456789abcdef"), canonical)
        XCTAssertEqual(PairingKey.psk(fromCode: "\t0123456789ABCDEF0123456789ABCDEF "), canonical)
    }
}
