// Spike T1: DTLS over UDP with Network.framework.
// Tries PSK-based DTLS first (no certificate generation needed).
// Success criteria: encrypted datagram round-trip on localhost.

import Foundation
import Network

let port: NWEndpoint.Port = 24845
let psk = "crossdesk-spike-shared-secret"
let pskIdentity = "crossdesk"

func makeDTLSParameters() -> NWParameters {
    let tlsOptions = NWProtocolTLS.Options()
    let sec = tlsOptions.securityProtocolOptions

    let pskDispatchData = psk.data(using: .utf8)!.withUnsafeBytes { DispatchData(bytes: $0) }
    let identityDispatchData = pskIdentity.data(using: .utf8)!.withUnsafeBytes { DispatchData(bytes: $0) }
    sec_protocol_options_add_pre_shared_key(
        sec,
        pskDispatchData as __DispatchData,
        identityDispatchData as __DispatchData
    )
    // PSK cipher suites are TLS 1.2; pin DTLS 1.2 both ways.
    sec_protocol_options_append_tls_ciphersuite(
        sec, tls_ciphersuite_t(rawValue: UInt16(TLS_PSK_WITH_AES_128_GCM_SHA256))!
    )
    sec_protocol_options_set_min_tls_protocol_version(sec, .DTLSv12)
    sec_protocol_options_set_max_tls_protocol_version(sec, .DTLSv12)

    let udpOptions = NWProtocolUDP.Options()
    let params = NWParameters(dtls: tlsOptions, udp: udpOptions)
    return params
}

let done = DispatchSemaphore(value: 0)
let queue = DispatchQueue(label: "spike")

// ---- Server ----
let listener = try NWListener(using: makeDTLSParameters(), on: port)
listener.stateUpdateHandler = { state in
    print("[server] listener state: \(state)")
}
listener.newConnectionHandler = { conn in
    print("[server] incoming connection")
    conn.stateUpdateHandler = { state in
        print("[server] conn state: \(state)")
    }
    conn.start(queue: queue)
    conn.receiveMessage { data, _, _, error in
        if let data, let text = String(data: data, encoding: .utf8) {
            print("[server] received: \(text)")
            conn.send(content: "pong".data(using: .utf8), completion: .contentProcessed { err in
                if let err { print("[server] send error: \(err)") }
            })
        } else {
            print("[server] receive error: \(String(describing: error))")
        }
    }
}
listener.start(queue: queue)

// ---- Client ----
queue.asyncAfter(deadline: .now() + 0.5) {
    let conn = NWConnection(host: "127.0.0.1", port: port, using: makeDTLSParameters())
    conn.stateUpdateHandler = { state in
        print("[client] conn state: \(state)")
        if case .ready = state {
            print("[client] DTLS handshake OK — sending ping")
            conn.send(content: "ping".data(using: .utf8), completion: .contentProcessed { err in
                if let err { print("[client] send error: \(err)") }
            })
            conn.receiveMessage { data, _, _, error in
                if let data, let text = String(data: data, encoding: .utf8) {
                    print("[client] received: \(text)")
                    print("SPIKE RESULT: SUCCESS — DTLS-PSK round-trip complete")
                    done.signal()
                } else {
                    print("[client] receive error: \(String(describing: error))")
                    print("SPIKE RESULT: FAIL")
                    done.signal()
                }
            }
        }
        if case .failed(let err) = state {
            print("[client] failed: \(err)")
            print("SPIKE RESULT: FAIL")
            done.signal()
        }
    }
    conn.start(queue: queue)
}

if done.wait(timeout: .now() + 10) == .timedOut {
    print("SPIKE RESULT: TIMEOUT (handshake never completed)")
    exit(1)
}
