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

    override func tearDown() {
        client?.stop()
        server?.stop()
        client = nil
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
            .enter(x: 0.0, y: 0.5),
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
