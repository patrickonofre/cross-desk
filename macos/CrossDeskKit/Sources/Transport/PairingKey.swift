import Foundation
import CryptoKit
import Security

/// Pairing-code based PSK derivation (PROTOCOL.md §1).
///
/// Two kinds of code flow through the same HKDF path:
/// - the short pairing token (6 chars, shown on the server, typed once on the
///   client — valid only for the pairing window, R28), and
/// - the long-term secret (32 hex chars, delivered via PAIR_SET inside the
///   DTLS tunnel after the first successful handshake, R29).
public enum PairingKey {
    static let salt = Data("crossdesk-v1".utf8)
    static let info = Data("dtls-psk".utf8)
    /// HKDF info for the file-channel PSK (PROTOCOL.md §8) — domain
    /// separation: the file channel never shares key material with the
    /// input channel, even though both derive from the same code.
    static let fileInfo = Data("tls-psk-file".utf8)
    public static let pskIdentity = "crossdesk"

    /// 32 lowercase hex chars = 128 bits of entropy. Used for the rotated
    /// long-term secret (PAIR_SET): a PSK cipher without (EC)DHE is
    /// brute-forceable offline if the code is weak (PROTOCOL.md §1).
    public static func generateCode() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed: \(status)")
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    /// Alphabet for short tokens: no 0/O, 1/I/L or U (Crockford-style) — every
    /// character survives being read aloud or retyped from a screen.
    static let tokenAlphabet = Array("23456789ABCDEFGHJKMNPQRSTVWXYZ")

    /// Short pairing token, "XXX-XXX" (6 chars ≈ 29 bits). Only valid during
    /// the pairing window: the first successful handshake rotates to a 128-bit
    /// secret (R29), so this never becomes the long-term key.
    public static func generateShortToken() -> String {
        // Rejection sampling — a plain modulo would bias the first 16 alphabet
        // characters (256 % 30 ≠ 0), and this string is security material.
        let limit = UInt8(256 - 256 % tokenAlphabet.count) // 240
        var chars: [Character] = []
        while chars.count < 6 {
            var byte: UInt8 = 0
            let status = SecRandomCopyBytes(kSecRandomDefault, 1, &byte)
            precondition(status == errSecSuccess, "SecRandomCopyBytes failed: \(status)")
            guard byte < limit else { continue }
            chars.append(tokenAlphabet[Int(byte) % tokenAlphabet.count])
        }
        return String(chars[0..<3]) + "-" + String(chars[3..<6])
    }

    /// Whether `code` could have come from `generateShortToken()` — used to
    /// detect a stale value left in a persisted config (e.g. the old 32-hex
    /// manual code from before this token existed, which is never empty and
    /// so would otherwise survive forever instead of being regenerated).
    public static func isShortToken(_ code: String) -> Bool {
        let stripped = code.uppercased().filter { $0 != "-" && !$0.isWhitespace }
        guard stripped.count == 6 else { return false }
        let alphabet = Set(tokenAlphabet)
        return stripped.allSatisfy(alphabet.contains)
    }

    /// Short non-reversible identifier of a PSK, safe to log. Both machines
    /// must show the same fingerprint — a mismatch means the pairing code was
    /// typed differently on each side.
    public static func fingerprint(psk: Data) -> String {
        SHA256.hash(data: psk).prefix(3).map { String(format: "%02x", $0) }.joined()
    }

    /// Canonical form used for derivation: alphanumerics only, lowercased.
    /// Codes travel between machines by hand (screen → keyboard, chat apps,
    /// notes) and pick up whitespace, case changes and the display dash of
    /// short tokens ("ABCD-EFGH" ≡ "abcdefgh") — none of that may change the
    /// PSK. #1 field cause of "handshake timeout".
    public static func normalize(_ code: String) -> String {
        String(code.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
            .lowercased()
    }

    /// HKDF-SHA256(normalized code) → 32-byte PSK.
    public static func psk(fromCode code: String) -> Data {
        derive(code: code, info: info)
    }

    /// PSK for the TCP file channel (PROTOCOL.md §8): same code, different
    /// HKDF info — independent key.
    public static func filePSK(fromCode code: String) -> Data {
        derive(code: code, info: fileInfo)
    }

    private static func derive(code: String, info: Data) -> Data {
        let normalized = normalize(code)
        let key = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: Data(normalized.utf8)),
            salt: salt,
            info: info,
            outputByteCount: 32
        )
        return key.withUnsafeBytes { Data($0) }
    }
}
