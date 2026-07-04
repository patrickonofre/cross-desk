import XCTest
@testable import CrossDeskKit

/// Loopback integration tests: real DTLS-PSK handshake + datagrams on 127.0.0.1.
final class TransportLoopbackTests: XCTestCase {
    private let psk = PairingKey.psk(fromCode: "0123456789abcdef0123456789abcdef")
    // Distinct ports per test — UDP sockets may linger between runs.
    // nonisolated(unsafe): XCTest runs these test methods serially in-process.
    private nonisolated(unsafe) static var nextPort: UInt16 = 24870
    private var port: UInt16 = 0
    private var server: DTLSServer!
    private var client: DTLSClient!

    override func setUp() {
        super.setUp()
        port = Self.nextPort
        Self.nextPort += 1
    }

    private var client2: DTLSClient?

    override func tearDown() {
        client?.stop()
        client2?.stop()
        server?.stop()
        client = nil
        client2 = nil
        server = nil
        super.tearDown()
    }

    func testHandshakeAndConnectedEvents() throws {
        let serverConnected = expectation(description: "server connected")
        let clientConnected = expectation(description: "client connected")

        server = DTLSServer(port: port, psk: psk)
        server.onEvent = { event in
            if case let .connected(peerName) = event {
                XCTAssertEqual(peerName, "test-client")
                serverConnected.fulfill()
            }
        }
        try server.start()

        client = DTLSClient(host: "127.0.0.1", port: port, psk: psk, deviceName: "test-client")
        client.onEvent = { event in
            if case .connected = event {
                clientConnected.fulfill()
            }
        }
        client.start()

        wait(for: [serverConnected, clientConnected], timeout: 10)
    }

    func testServerToClientMessages() throws {
        let received = expectation(description: "client received input messages")
        let sent: [Message] = [
            .enter(x: 0.0, y: 0.5, edge: .left),
            .mouseMove(dx: 12, dy: -4),
            .key(hidUsage: 0x04, pressed: true),
        ]

        server = DTLSServer(port: port, psk: psk)
        let serverBox = server!
        server.onEvent = { event in
            if case .connected = event {
                serverBox.send(sent)
            }
        }
        try server.start()

        client = DTLSClient(host: "127.0.0.1", port: port, psk: psk, deviceName: "c")
        client.onEvent = { event in
            if case let .messages(messages) = event {
                XCTAssertEqual(messages, sent)
                received.fulfill()
            }
        }
        client.start()

        wait(for: [received], timeout: 10)
    }

    func testWrongPSKNeverCompletesHandshake() throws {
        let connected = expectation(description: "connected must not happen")
        connected.isInverted = true

        server = DTLSServer(port: port, psk: psk)
        try server.start()

        client = DTLSClient(
            host: "127.0.0.1", port: port,
            psk: PairingKey.psk(fromCode: "ffffffffffffffffffffffffffffffff"),
            deviceName: "intruder"
        )
        client.onEvent = { event in
            if case .connected = event {
                connected.fulfill()
            }
        }
        client.start()

        wait(for: [connected], timeout: 3)
    }

    func testClientReconnectsAfterServerRestart() throws {
        let firstConnect = expectation(description: "first connect")
        let reconnect = expectation(description: "reconnect after server restart")

        server = DTLSServer(port: port, psk: psk)
        try server.start()

        client = DTLSClient(host: "127.0.0.1", port: port, psk: psk, deviceName: "c")
        let connectCount = OSAllocatedUnfairLockBox(0)
        client.onEvent = { event in
            if case .connected = event {
                let count = connectCount.increment()
                if count == 1 { firstConnect.fulfill() }
                if count == 2 { reconnect.fulfill() }
            }
        }
        client.start()
        wait(for: [firstConnect], timeout: 10)

        // Kill and restart the server on the same port; client must come back
        // by itself (R10). Timeout must exceed peerTimeout (6 s) + backoff.
        server.stop()
        Thread.sleep(forTimeInterval: 0.5)
        server = DTLSServer(port: port, psk: psk)
        try server.start()

        wait(for: [reconnect], timeout: 20)
    }

    // MARK: - Pairing rotation (R29, R30 — PROTOCOL.md §6)

    func testPairingRotatesToSecretAndListenerAcceptsOnlySecretAfterwards() throws {
        let tokenPSK = PairingKey.psk(fromCode: "ABCD-EFGH")
        let serverSecret = LockedValue<String?>(nil)
        let clientSecret = LockedValue<String?>(nil)
        let paired = expectation(description: "server got PAIR_ACK")
        let pairSet = expectation(description: "client got PAIR_SET")
        pairSet.assertForOverFulfill = false // resend before the ACK lands is legal

        server = DTLSServer(port: port, psk: tokenPSK, pairing: true)
        server.onPaired = { secret in
            serverSecret.set(secret)
            paired.fulfill()
        }
        try server.start()

        client = DTLSClient(host: "127.0.0.1", port: port, psk: tokenPSK, deviceName: "c")
        client.onPairSet = { secret in
            if clientSecret.get() == nil {
                clientSecret.set(secret)
                pairSet.fulfill()
            }
        }
        client.start()

        wait(for: [pairSet, paired], timeout: 10)
        XCTAssertEqual(serverSecret.get(), clientSecret.get())
        let secret = try XCTUnwrap(serverSecret.get())
        XCTAssertEqual(secret.count, 32) // 128-bit hex — never the short token

        // The paired session must survive the listener rotation.
        let survived = expectation(description: "input flows after rotation")
        survived.assertForOverFulfill = false
        client.onEvent = { event in
            if case .messages = event { survived.fulfill() }
        }
        server.send([.mouseMove(dx: 1, dy: 1)])
        wait(for: [survived], timeout: 5)

        // New handshakes must require the secret (listener rotated).
        client.stop() // frees the single client slot (BYE → immediate drop)
        let reconnected = expectation(description: "second client connects with the secret")
        client2 = DTLSClient(
            host: "127.0.0.1", port: port,
            psk: PairingKey.psk(fromCode: secret), deviceName: "c2"
        )
        client2?.onEvent = { event in
            if case .connected = event { reconnected.fulfill() }
        }
        client2?.start()
        wait(for: [reconnected], timeout: 15)
    }

    func testClientFallsBackToTokenWhenSecretHandshakeTimesOut() throws {
        // "Server forgot the pairing" (R30): client leads with a stale secret,
        // must recover through the token on a later attempt, and the server
        // re-runs the rotation.
        let tokenPSK = PairingKey.psk(fromCode: "QQQQ-WWWW")
        let staleSecret = PairingKey.psk(fromCode: PairingKey.generateCode())
        let connected = expectation(description: "connected via fallback token")
        let repaired = expectation(description: "rotation re-ran after fallback")
        repaired.assertForOverFulfill = false

        server = DTLSServer(port: port, psk: tokenPSK, pairing: true)
        try server.start()

        client = DTLSClient(
            host: "127.0.0.1", port: port,
            psk: staleSecret, fallbackPSK: tokenPSK, deviceName: "c"
        )
        client.onEvent = { event in
            if case .connected = event { connected.fulfill() }
        }
        client.onPairSet = { _ in repaired.fulfill() }
        client.start()

        // Stale-secret attempt burns a full handshake timeout (5 s) + backoff
        // before the token attempt can run.
        wait(for: [connected, repaired], timeout: 25)
    }

    func testDuplicatePairSetPersistsSameSecretAndDoesNotCrash() {
        // ACK lost → server resends PAIR_SET; the client must persist the same
        // value again (harmless) rather than treat it as an error.
        let received = LockedValue<[String]>([])
        let offline = DTLSClient(host: "127.0.0.1", port: 1, psk: Data(count: 32), deviceName: "c")
        offline.onPairSet = { code in received.mutate { $0.append(code) } }

        let datagram = Message.pairSet(code: "0123456789abcdef0123456789abcdef").encoded()
        offline.handleDatagram(datagram)
        offline.handleDatagram(datagram)

        XCTAssertEqual(received.get(), Array(repeating: "0123456789abcdef0123456789abcdef", count: 2))
    }

    func testDatagramSplittingRespectsMaxSize() {
        let moves = (0..<200).map { Message.mouseMove(dx: Float($0), dy: 1) }
        let datagrams = DTLSServer.datagrams(from: moves)
        XCTAssertGreaterThan(datagrams.count, 1)
        for datagram in datagrams {
            XCTAssertLessThanOrEqual(datagram.count, ProtocolConstants.maxDatagramSize)
        }
        let rejoined = try? Message.decodeAll(datagrams.reduce(into: Data()) { $0.append($1) })
        XCTAssertEqual(rejoined, moves)
    }
}

/// Tiny thread-safe counter for test callbacks (Swift 6 strict concurrency).
private final class OSAllocatedUnfairLockBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Int
    init(_ value: Int) { self.value = value }
    func increment() -> Int {
        lock.lock()
        defer { lock.unlock() }
        value += 1
        return value
    }
}

/// Thread-safe value box for capturing callback payloads in tests.
final class LockedValue<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: T
    init(_ value: T) { self.value = value }
    func get() -> T {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
    func set(_ newValue: T) {
        lock.lock()
        defer { lock.unlock() }
        value = newValue
    }
    func mutate(_ body: (inout T) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        body(&value)
    }
}
