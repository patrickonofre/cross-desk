import XCTest
import Network
@testable import CrossDeskKit

final class FileChannelLoopbackTests: XCTestCase {

    // Distinct ports per test — TCP sockets may linger (TIME_WAIT) between runs.
    // Range starts above the DTLS loopback tests' range to never collide.
    private nonisolated(unsafe) static var nextPort: UInt16 = 24920
    private var port: UInt16 = 0
    private var listener: FileChannelListener?

    private static let psk = PairingKey.filePSK(fromCode: "0123456789abcdef0123456789abcdef")

    override func setUp() {
        super.setUp()
        port = Self.nextPort
        Self.nextPort += 1
    }

    override func tearDown() {
        listener?.stop()
        listener = nil
        super.tearDown()
    }

    func testHelloRoundTripAndCleanClose() throws {
        let serverGotHello = expectation(description: "server got FILE_HELLO")
        let clientGotDone = expectation(description: "client got TRANSFER_DONE")
        let serverSawClose = expectation(description: "server saw peer close")

        let listener = FileChannelListener(port: port, psk: Self.psk)
        self.listener = listener
        listener.onConnection = { conn in
            conn.onEvent = { event in
                switch event {
                case let .messages(messages):
                    if messages.contains(.fileHello(protoVersion: 1, transferId: 9, mode: .push)) {
                        serverGotHello.fulfill()
                        conn.send(.transferDone)
                    }
                case .closed:
                    serverSawClose.fulfill()
                default:
                    break
                }
            }
            conn.start()
        }
        try listener.start()

        let client = FileChannelConnection(host: "127.0.0.1", port: port, psk: Self.psk)
        client.onEvent = { event in
            switch event {
            case .ready:
                client.send(.fileHello(protoVersion: 1, transferId: 9, mode: .push))
            case let .messages(messages):
                if messages.contains(.transferDone) {
                    clientGotDone.fulfill()
                    client.close()
                }
            default:
                break
            }
        }
        client.start()

        wait(for: [serverGotHello, clientGotDone, serverSawClose], timeout: 10)
    }

    func testLargeDataFrameCrossesChannelIntact() throws {
        let payload = Data(repeating: 0xCD, count: FileChannelConstants.maxChunkSize)
        let serverGotData = expectation(description: "server got 64 KiB DATA intact")

        let listener = FileChannelListener(port: port, psk: Self.psk)
        self.listener = listener
        // The listener does not retain accepted connections — the test must.
        nonisolated(unsafe) var serverConn: FileChannelConnection?
        listener.onConnection = { conn in
            serverConn = conn
            conn.onEvent = { event in
                guard case let .messages(messages) = event else { return }
                for message in messages {
                    if case let .data(bytes) = message, bytes == payload {
                        serverGotData.fulfill()
                    }
                }
            }
            conn.start()
        }
        try listener.start()

        let client = FileChannelConnection(host: "127.0.0.1", port: port, psk: Self.psk)
        client.onEvent = { event in
            if case .ready = event {
                client.send(.data(payload))
            }
        }
        client.start()

        wait(for: [serverGotData], timeout: 10)
        withExtendedLifetime(serverConn) {}
    }

    func testWrongPSKClosesWithoutReady() throws {
        let closed = expectation(description: "client closed")

        let listener = FileChannelListener(port: port, psk: Self.psk)
        self.listener = listener
        listener.onConnection = { conn in
            conn.onEvent = { _ in }
            conn.start()
        }
        try listener.start()

        nonisolated(unsafe) var sawReady = false
        let client = FileChannelConnection(
            host: "127.0.0.1", port: port,
            psk: PairingKey.filePSK(fromCode: "another-code-entirely")
        )
        client.onEvent = { event in
            switch event {
            case .ready:
                sawReady = true
            case .closed:
                closed.fulfill()
            default:
                break
            }
        }
        client.start()

        // Covered either by a TLS alert (.failed) or by the handshake timeout (5 s).
        wait(for: [closed], timeout: 10)
        XCTAssertFalse(sawReady, "a PSK mismatch must never produce a ready channel")
    }

    func testConnectWithNoListenerCloses() throws {
        let closed = expectation(description: "client closed")

        let client = FileChannelConnection(host: "127.0.0.1", port: port, psk: Self.psk)
        client.onEvent = { event in
            if case .closed = event {
                closed.fulfill()
            }
        }
        client.start()

        wait(for: [closed], timeout: 10)
    }

    func testMalformedStreamClosesConnectionAsProtocolError() throws {
        let serverClosed = expectation(description: "server conn closed on protocol error")

        let listener = FileChannelListener(port: port, psk: Self.psk)
        self.listener = listener
        // The listener does not retain accepted connections — the test must.
        nonisolated(unsafe) var serverConn: FileChannelConnection?
        listener.onConnection = { conn in
            serverConn = conn
            conn.onEvent = { event in
                if case let .closed(reason) = event {
                    XCTAssertTrue(
                        reason.hasPrefix("protocol error"),
                        "expected protocol error close, got: \(reason)"
                    )
                    serverClosed.fulfill()
                }
            }
            conn.start()
        }
        try listener.start()

        // Raw TLS client (bypasses FileChannelConnection) sending an unknown
        // frame type — the server side must treat it as fatal (§8).
        let queue = DispatchQueue(label: "test.raw-client")
        let raw = NWConnection(
            host: "127.0.0.1",
            port: NWEndpoint.Port(rawValue: port)!,
            using: FileChannelParameters.make(psk: Self.psk)
        )
        raw.stateUpdateHandler = { state in
            if case .ready = state {
                raw.send(content: Data([0xFF, 0x00, 0x00, 0x00, 0x00]), completion: .idempotent)
            }
        }
        raw.start(queue: queue)

        wait(for: [serverClosed], timeout: 10)
        raw.cancel()
        withExtendedLifetime(serverConn) {}
    }
}
