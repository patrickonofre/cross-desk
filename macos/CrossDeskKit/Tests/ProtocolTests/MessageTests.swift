import XCTest
@testable import CrossDeskKit

final class MessageTests: XCTestCase {

    // MARK: - Golden vectors (PROTOCOL.md v0.1 — the cross-platform contract)

    /// Canonical bytes for every message type. The same vectors live in
    /// .specs/protocol/vectors/v0_1.txt for the Windows/Linux implementations.
    static let goldenVectors: [(name: String, message: Message, hex: String)] = [
        ("hello", .hello(protoVersion: 1, name: "mac"), "0106000100036d6163"),
        ("hello_ack", .helloAck(protoVersion: 1), "0202000100"),
        ("heartbeat", .heartbeat, "030000"),
        ("bye", .bye, "040000"),
        ("enter", .enter(x: 0.5, y: 0.25, edge: .left), "1009000000003f0000803e00"),
        ("leave", .leave, "110000"),
        ("leave_request", .leaveRequest(x: 0.0, y: 0.5), "120800000000000000003f"),
        ("mouse_move", .mouseMove(dx: 10.0, dy: -3.5), "20080000002041000060c0"),
        ("mouse_button", .mouseButton(button: 1, pressed: true), "2102000101"),
        ("scroll", .scroll(dx: 0.0, dy: 1.0), "220800000000000000803f"),
        ("key", .key(hidUsage: 0x0004, pressed: true), "300300040001"),
    ]

    func testGoldenVectorsEncode() {
        for vector in Self.goldenVectors {
            XCTAssertEqual(
                vector.message.encoded().hexString, vector.hex,
                "encode mismatch for \(vector.name)"
            )
        }
    }

    func testGoldenVectorsDecode() throws {
        for vector in Self.goldenVectors {
            let decoded = try Message.decodeAll(Data(hexString: vector.hex)!)
            XCTAssertEqual(decoded, [vector.message], "decode mismatch for \(vector.name)")
        }
    }

    // MARK: - Round-trip

    func testRoundTripAllMessageTypes() throws {
        let messages: [Message] = [
            .hello(protoVersion: 7, name: "Mac do Patrick"),
            .helloAck(protoVersion: 7),
            .heartbeat,
            .bye,
            .enter(x: 0.0, y: 1.0, edge: .bottom),
            .leave,
            .leaveRequest(x: 1.0, y: 0.75),
            .mouseMove(dx: -1024.5, dy: 0.001),
            .mouseButton(button: 4, pressed: false),
            .scroll(dx: -3.0, dy: 42.25),
            .key(hidUsage: 0xE3, pressed: false),
        ]
        for message in messages {
            XCTAssertEqual(try Message.decodeAll(message.encoded()), [message])
        }
    }

    /// Compound datagram vector — also published in vectors/v0_1.txt.
    static let compoundMessages: [Message] = [
        .enter(x: 0.0, y: 0.5, edge: .left),
        .mouseMove(dx: 5, dy: 5),
        .key(hidUsage: 0x04, pressed: true),
        .key(hidUsage: 0x04, pressed: false),
    ]
    static let compoundHex =
        "100900000000000000003f00" + "2008000000a0400000a040" +
        "300300040001" + "300300040000"

    func testCompoundGoldenVector() throws {
        XCTAssertEqual(Message.encodeAll(Self.compoundMessages).hexString, Self.compoundHex)
        XCTAssertEqual(try Message.decodeAll(Data(hexString: Self.compoundHex)!), Self.compoundMessages)
    }

    func testMultipleMessagesInOneDatagram() throws {
        let messages: [Message] = [
            .enter(x: 0.0, y: 0.5, edge: .right),
            .mouseMove(dx: 5, dy: 5),
            .key(hidUsage: 0x04, pressed: true),
            .key(hidUsage: 0x04, pressed: false),
        ]
        let datagram = Message.encodeAll(messages)
        XCTAssertEqual(try Message.decodeAll(datagram), messages)
    }

    func testEnterWithUnknownEdgeValueThrows() {
        // ENTER with edge byte 0x07 (only 0–3 are defined) — invalid payload.
        let data = Data(hexString: "100900" + "00000000" + "00000000" + "07")!
        XCTAssertThrowsError(try Message.decodeAll(data)) { error in
            XCTAssertEqual(error as? ProtocolError, .invalidPayload(type: 0x10))
        }
    }

    // MARK: - Robustness

    func testTruncatedHeaderThrows() {
        XCTAssertThrowsError(try Message.decodeAll(Data([0x20, 0x08]))) { error in
            XCTAssertEqual(error as? ProtocolError, .truncated)
        }
    }

    func testTruncatedPayloadThrows() {
        // mouse_move claims 8 payload bytes, carries 4
        XCTAssertThrowsError(try Message.decodeAll(Data(hexString: "20080000002041")!)) { error in
            XCTAssertEqual(error as? ProtocolError, .truncated)
        }
    }

    func testUnknownTypeIsSkipped() throws {
        // 0x7F is not a known type; the heartbeat after it must still decode.
        let data = Data(hexString: "7f0200abcd030000")!
        XCTAssertEqual(try Message.decodeAll(data), [.heartbeat])
    }

    func testMalformedUTF8InHelloThrows() {
        // name_len 2, bytes 0xFF 0xFE — invalid UTF-8
        let data = Data(hexString: "0105000100" + "02fffe")!
        XCTAssertThrowsError(try Message.decodeAll(data)) { error in
            XCTAssertEqual(error as? ProtocolError, .invalidPayload(type: 0x01))
        }
    }

    func testHelloNameLongerThan255BytesIsTruncatedNotCorrupted() throws {
        let longName = String(repeating: "x", count: 300)
        let decoded = try Message.decodeAll(Message.hello(protoVersion: 1, name: longName).encoded())
        guard case let .hello(_, name) = decoded[0] else {
            return XCTFail("expected hello")
        }
        XCTAssertEqual(name.count, 255)
    }

    func testEmptyDatagramDecodesToNothing() throws {
        XCTAssertEqual(try Message.decodeAll(Data()), [])
    }
}

// MARK: - Hex helpers (test-only)

extension Data {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }

    init?(hexString: String) {
        guard hexString.count.isMultiple(of: 2) else { return nil }
        var data = Data(capacity: hexString.count / 2)
        var index = hexString.startIndex
        while index < hexString.endIndex {
            let next = hexString.index(index, offsetBy: 2)
            guard let byte = UInt8(hexString[index..<next], radix: 16) else { return nil }
            data.append(byte)
            index = next
        }
        self = data
    }
}
