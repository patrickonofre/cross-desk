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

    // MARK: - Short pairing token (R28)

    func testShortTokenFormat() {
        let token = PairingKey.generateShortToken()
        XCTAssertEqual(token.count, 7)
        let groups = token.split(separator: "-")
        XCTAssertEqual(groups.count, 2)
        XCTAssertTrue(groups.allSatisfy { $0.count == 3 })
        let alphabet = Set(PairingKey.tokenAlphabet)
        XCTAssertTrue(token.replacingOccurrences(of: "-", with: "").allSatisfy(alphabet.contains))
    }

    func testIsShortTokenAcceptsGeneratedTokensInAnyCaseOrSpacing() {
        let token = PairingKey.generateShortToken()
        XCTAssertTrue(PairingKey.isShortToken(token))
        XCTAssertTrue(PairingKey.isShortToken(token.lowercased()))
        XCTAssertTrue(PairingKey.isShortToken(token.replacingOccurrences(of: "-", with: "")))
    }

    func testIsShortTokenRejectsStaleLongFormCode() {
        // The old 32-hex manual code (pre-short-token flow) is never empty,
        // so a config left over from back then must be caught here or it
        // survives forever instead of being regenerated (R28 migration bug).
        XCTAssertFalse(PairingKey.isShortToken("773f920d090ab979d7fc970454ba1342"))
        XCTAssertFalse(PairingKey.isShortToken(""))
        XCTAssertFalse(PairingKey.isShortToken("ABC-DEFG"))
    }

    func testShortTokenAlphabetHasNoAmbiguousCharacters() {
        let ambiguous: Set<Character> = ["0", "O", "1", "I", "L", "U"]
        XCTAssertTrue(ambiguous.isDisjoint(with: PairingKey.tokenAlphabet))
    }

    func testShortTokensAreUnique() {
        // 100 draws from a 29-bit space colliding would point at broken RNG
        // plumbing, not bad luck.
        let tokens = (0..<100).map { _ in PairingKey.generateShortToken() }
        XCTAssertEqual(Set(tokens).count, tokens.count)
    }

    func testShortTokenPSKIgnoresDashAndCase() {
        // The dash is display-only and users retype tokens in any case: every
        // spelling of the same token must derive the same PSK (R28).
        let canonical = PairingKey.psk(fromCode: "abcdefgh")
        XCTAssertEqual(PairingKey.psk(fromCode: "ABCD-EFGH"), canonical)
        XCTAssertEqual(PairingKey.psk(fromCode: "abcd-efgh"), canonical)
        XCTAssertEqual(PairingKey.psk(fromCode: " ABCDEFGH\n"), canonical)
    }

    func testNormalizeStripsSeparatorsAndLowercases() {
        XCTAssertEqual(PairingKey.normalize("ABCD-EFGH"), "abcdefgh")
        XCTAssertEqual(PairingKey.normalize(" ab cd-ef.gh\t"), "abcdefgh")
        XCTAssertEqual(PairingKey.normalize("0123456789abcdef"), "0123456789abcdef")
    }
}
