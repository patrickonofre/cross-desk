import Foundation
import CryptoKit
import Security

/// Pairing-code based PSK derivation (PROTOCOL.md §1).
///
/// The server generates the code (128 bits, hex) and shows it in the UI; the
/// user enters it once on the client. Both sides derive the same DTLS PSK.
public enum PairingKey {
    static let salt = Data("crossdesk-v1".utf8)
    static let info = Data("dtls-psk".utf8)
    public static let pskIdentity = "crossdesk"

    /// 32 lowercase hex chars = 128 bits of entropy. Always generated, never
    /// user-invented: a PSK cipher without (EC)DHE is brute-forceable offline
    /// if the code is weak (PROTOCOL.md §1 security note).
    public static func generateCode() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed: \(status)")
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    /// HKDF-SHA256(code) → 32-byte PSK.
    public static func psk(fromCode code: String) -> Data {
        let key = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: Data(code.utf8)),
            salt: salt,
            info: info,
            outputByteCount: 32
        )
        return key.withUnsafeBytes { Data($0) }
    }
}
