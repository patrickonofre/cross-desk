import Foundation
import Network

/// DTLS-PSK connection parameters shared by server and client
/// (PROTOCOL.md §1, validated by spike T1).
enum DTLSParameters {
    static func make(psk: Data) -> NWParameters {
        let tlsOptions = NWProtocolTLS.Options()
        let sec = tlsOptions.securityProtocolOptions

        let pskDispatchData = psk.withUnsafeBytes { DispatchData(bytes: $0) }
        let identityDispatchData = Data(PairingKey.pskIdentity.utf8)
            .withUnsafeBytes { DispatchData(bytes: $0) }
        sec_protocol_options_add_pre_shared_key(
            sec,
            pskDispatchData as __DispatchData,
            identityDispatchData as __DispatchData
        )
        // PSK cipher suites are TLS 1.2-only; pin DTLS 1.2 on both ends.
        sec_protocol_options_append_tls_ciphersuite(
            sec, tls_ciphersuite_t(rawValue: UInt16(TLS_PSK_WITH_AES_128_GCM_SHA256))!
        )
        sec_protocol_options_set_min_tls_protocol_version(sec, .DTLSv12)
        sec_protocol_options_set_max_tls_protocol_version(sec, .DTLSv12)

        return NWParameters(dtls: tlsOptions, udp: NWProtocolUDP.Options())
    }
}

/// Events surfaced by the transport layer. Delivered on the transport's
/// internal serial queue.
public enum TransportEvent: Sendable {
    /// Handshake + HELLO/HELLO_ACK completed. `peerName` is the remote device name
    /// (client name on the server; server has no name in v0.1, so clients get "").
    case connected(peerName: String)
    case disconnected(reason: String)
    /// Input/control messages (HELLO/HELLO_ACK/HEARTBEAT are consumed internally).
    case messages([Message])
}

enum TransportTiming {
    static let heartbeatInterval: TimeInterval = 2
    static let peerTimeout: TimeInterval = 6
    static let reconnectMinDelay: TimeInterval = 1
    static let reconnectMaxDelay: TimeInterval = 30
    /// DTLS + HELLO must complete within this window or the attempt is dropped
    /// (a connection stuck in .preparing never reaches .failed on its own).
    static let handshakeTimeout: TimeInterval = 5
    /// PAIR_SET resend cadence until PAIR_ACK arrives (PROTOCOL.md §3).
    static let pairSetResendInterval: TimeInterval = 2
}
