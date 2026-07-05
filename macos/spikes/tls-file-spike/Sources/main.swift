// Spike T40 (file-transfer, incerteza I1): TLS 1.2 PSK over TCP with Network.framework.
// Mirrors the proven DTLS-PSK setup (spike T1) on a stream connection.
// Success criteria: PSK handshake + round-trip + 1 MiB sustained stream on localhost.

import Foundation
import Network

let port: NWEndpoint.Port = 24846
let psk = "crossdesk-spike-shared-secret"
let pskIdentity = "crossdesk"
let blobSize = 1024 * 1024

func makeTLSParameters() -> NWParameters {
    let tlsOptions = NWProtocolTLS.Options()
    let sec = tlsOptions.securityProtocolOptions

    let pskDispatchData = psk.data(using: .utf8)!.withUnsafeBytes { DispatchData(bytes: $0) }
    let identityDispatchData = pskIdentity.data(using: .utf8)!.withUnsafeBytes { DispatchData(bytes: $0) }
    sec_protocol_options_add_pre_shared_key(
        sec,
        pskDispatchData as __DispatchData,
        identityDispatchData as __DispatchData
    )
    // PSK cipher suites are TLS 1.2; pin TLS 1.2 both ways.
    sec_protocol_options_append_tls_ciphersuite(
        sec, tls_ciphersuite_t(rawValue: UInt16(TLS_PSK_WITH_AES_128_GCM_SHA256))!
    )
    sec_protocol_options_set_min_tls_protocol_version(sec, .TLSv12)
    sec_protocol_options_set_max_tls_protocol_version(sec, .TLSv12)

    return NWParameters(tls: tlsOptions, tcp: NWProtocolTCP.Options())
}

let done = DispatchSemaphore(value: 0)
let queue = DispatchQueue(label: "spike")

/// TCP is a stream: accumulate until exactly `count` bytes arrived.
func receiveExactly(_ conn: NWConnection, _ count: Int, accumulated: Data = Data(),
                    completion: @escaping (Data?) -> Void) {
    conn.receive(minimumIncompleteLength: 1, maximumLength: count - accumulated.count) { data, _, _, error in
        guard let data, !data.isEmpty else {
            print("receive error: \(String(describing: error))")
            completion(nil)
            return
        }
        let total = accumulated + data
        if total.count >= count {
            completion(total)
        } else {
            receiveExactly(conn, count, accumulated: total, completion: completion)
        }
    }
}

// ---- Server ----
let listener = try NWListener(using: makeTLSParameters(), on: port)
listener.stateUpdateHandler = { state in print("[server] listener state: \(state)") }
listener.newConnectionHandler = { conn in
    print("[server] incoming connection")
    conn.stateUpdateHandler = { state in print("[server] conn state: \(state)") }
    conn.start(queue: queue)
    receiveExactly(conn, 4) { data in
        guard let data, String(data: data, encoding: .utf8) == "ping" else {
            print("[server] bad ping")
            return
        }
        print("[server] received: ping")
        conn.send(content: "pong".data(using: .utf8), completion: .contentProcessed { err in
            if let err { print("[server] send error: \(err)") }
        })
        receiveExactly(conn, blobSize) { blob in
            guard let blob else { return }
            print("[server] received blob: \(blob.count) bytes")
            conn.send(content: "ok".data(using: .utf8), completion: .contentProcessed { err in
                if let err { print("[server] send error: \(err)") }
            })
        }
    }
}
listener.start(queue: queue)

// ---- Client ----
queue.asyncAfter(deadline: .now() + 0.5) {
    let conn = NWConnection(host: "127.0.0.1", port: port, using: makeTLSParameters())
    conn.stateUpdateHandler = { state in
        print("[client] conn state: \(state)")
        if case .ready = state {
            print("[client] TLS-PSK handshake OK — sending ping")
            conn.send(content: "ping".data(using: .utf8), completion: .contentProcessed { err in
                if let err { print("[client] send error: \(err)") }
            })
            receiveExactly(conn, 4) { data in
                guard let data, String(data: data, encoding: .utf8) == "pong" else {
                    print("SPIKE RESULT: FAIL (no pong)")
                    done.signal()
                    return
                }
                print("[client] received: pong — streaming \(blobSize) bytes")
                conn.send(content: Data(repeating: 0xAB, count: blobSize),
                          completion: .contentProcessed { err in
                    if let err { print("[client] blob send error: \(err)") }
                })
                receiveExactly(conn, 2) { ok in
                    if let ok, String(data: ok, encoding: .utf8) == "ok" {
                        print("SPIKE RESULT: SUCCESS — TLS-PSK over TCP round-trip + 1 MiB stream complete")
                    } else {
                        print("SPIKE RESULT: FAIL (no ok after blob)")
                    }
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

if done.wait(timeout: .now() + 15) == .timedOut {
    print("SPIKE RESULT: TIMEOUT (handshake never completed)")
    exit(1)
}
