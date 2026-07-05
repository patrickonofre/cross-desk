import XCTest
@testable import CrossDeskKit

final class FileChannelMessageTests: XCTestCase {

    // MARK: - Golden vectors (PROTOCOL.md §8 — fc_* in vectors/v0_1.txt)

    /// File-channel framing is its OWN: type u8 · length u32 LE · payload.
    static let goldenVectors: [(name: String, message: FileChannelMessage, hex: String)] = [
        ("fc_hello",
         .fileHello(protoVersion: 1, transferId: 1, mode: .push),
         "010700000001000100000000"),
        ("fc_item_meta",
         .itemMeta(kind: .file, size: 11, path: "docs/a.txt", symlinkTarget: nil),
         "0215000000000b000000000000000a00646f63732f612e747874"),
        ("fc_item_meta_link",
         .itemMeta(kind: .symlink, size: 0, path: "ln", symlinkTarget: "a.txt"),
         "021400000002000000000000000002006c6e0500612e747874"),
        ("fc_data",
         .data(Data("hello".utf8)),
         "030500000068656c6c6f"),
        ("fc_item_done",
         .itemDone(sha256: Data(hexString: "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")!),
         "04200000002cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"),
        ("fc_item_done_empty", .itemDone(sha256: nil), "0400000000"),
        ("fc_transfer_done", .transferDone, "0500000000"),
        ("fc_cancel", .cancel(origin: .sender), "060100000000"),
        ("fc_error",
         .error(code: 1, message: "disk full"),
         "070c0000000109006469736b2066756c6c"),
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
            var decoder = FileChannelDecoder()
            let decoded = try decoder.feed(Data(hexString: vector.hex)!)
            XCTAssertEqual(decoded, [vector.message], "decode mismatch for \(vector.name)")
        }
    }

    // MARK: - Round-trip

    func testRoundTripAllMessageTypes() throws {
        let messages: [FileChannelMessage] = [
            .fileHello(protoVersion: 7, transferId: 0xDEAD_BEEF, mode: .request),
            .itemMeta(kind: .directory, size: 0, path: "Fotos de férias", symlinkTarget: nil),
            .itemMeta(kind: .file, size: UInt64.max, path: "a/b/c/€.bin", symlinkTarget: nil),
            .itemMeta(kind: .symlink, size: 0, path: "ln", symlinkTarget: "../fora"),
            .data(Data(repeating: 0xAB, count: FileChannelConstants.maxChunkSize)),
            .data(Data()),
            .itemDone(sha256: Data(repeating: 0x11, count: 32)),
            .itemDone(sha256: nil),
            .transferDone,
            .cancel(origin: .receiver),
            .error(code: 255, message: ""),
        ]
        var decoder = FileChannelDecoder()
        let stream = messages.reduce(into: Data()) { $0.append($1.encoded()) }
        XCTAssertEqual(try decoder.feed(stream), messages)
    }

    // MARK: - Streaming (TCP delivers arbitrary fragments)

    func testByteByByteFeedDecodesSameMessages() throws {
        let messages: [FileChannelMessage] = [
            .fileHello(protoVersion: 1, transferId: 3, mode: .push),
            .itemMeta(kind: .file, size: 5, path: "x", symlinkTarget: nil),
            .data(Data("hello".utf8)),
            .itemDone(sha256: Data(repeating: 0x22, count: 32)),
            .transferDone,
        ]
        let stream = messages.reduce(into: Data()) { $0.append($1.encoded()) }
        var decoder = FileChannelDecoder()
        var decoded: [FileChannelMessage] = []
        for byte in stream {
            decoded.append(contentsOf: try decoder.feed(Data([byte])))
        }
        XCTAssertEqual(decoded, messages)
    }

    func testPartialFrameEmitsNothingUntilComplete() throws {
        let frame = FileChannelMessage.transferDone.encoded()
        var decoder = FileChannelDecoder()
        XCTAssertEqual(try decoder.feed(frame.prefix(4)), [])
        XCTAssertEqual(try decoder.feed(frame.suffix(from: 4)), [.transferDone])
    }

    // MARK: - Robustness (any throw is fatal for the channel, §8)

    func testUnknownTypeThrows() {
        var decoder = FileChannelDecoder()
        // Type 0x7F does not exist on the file channel — unlike §2, this throws.
        XCTAssertThrowsError(try decoder.feed(Data(hexString: "7f00000000")!)) { error in
            XCTAssertEqual(error as? FileChannelError, .unknownType(0x7F))
        }
    }

    func testFrameTooLargeThrows() {
        var decoder = FileChannelDecoder()
        // DATA frame claiming 2 MiB (above the 1 MiB sanity cap).
        XCTAssertThrowsError(try decoder.feed(Data(hexString: "0300002000")!)) { error in
            XCTAssertEqual(error as? FileChannelError, .frameTooLarge(declared: 1 << 21))
        }
    }

    func testDataChunkAboveLimitThrows() {
        var decoder = FileChannelDecoder()
        // 64 KiB + 1 declared and delivered — one byte over the §8 chunk limit.
        let size = FileChannelConstants.maxChunkSize + 1
        var frame = Data([0x03])
        frame.appendLE(UInt32(size))
        frame.append(Data(repeating: 0, count: size))
        XCTAssertThrowsError(try decoder.feed(frame)) { error in
            XCTAssertEqual(error as? FileChannelError, .invalidPayload(type: 0x03))
        }
    }

    func testItemDoneWithWrongHashSizeThrows() {
        var decoder = FileChannelDecoder()
        // 5-byte payload: neither empty (dir/symlink) nor 32 (sha256).
        XCTAssertThrowsError(try decoder.feed(Data(hexString: "04050000000102030405")!)) { error in
            XCTAssertEqual(error as? FileChannelError, .invalidPayload(type: 0x04))
        }
    }

    func testItemMetaMalformedUTF8PathThrows() {
        var decoder = FileChannelDecoder()
        // kind=file, size=0, path_len=2, path bytes 0xFF 0xFE (invalid UTF-8).
        let hex = "020d000000" + "00" + "0000000000000000" + "0200" + "fffe"
        XCTAssertThrowsError(try decoder.feed(Data(hexString: hex)!)) { error in
            XCTAssertEqual(error as? FileChannelError, .invalidPayload(type: 0x02))
        }
    }

    func testItemMetaSymlinkMissingTargetThrows() {
        var decoder = FileChannelDecoder()
        // kind=symlink but payload ends right after the path — target fields missing.
        let hex = "020d000000" + "02" + "0000000000000000" + "0200" + "6c6e"
        XCTAssertThrowsError(try decoder.feed(Data(hexString: hex)!)) { error in
            XCTAssertEqual(error as? FileChannelError, .invalidPayload(type: 0x02))
        }
    }

    func testFileHelloUnknownModeThrows() {
        var decoder = FileChannelDecoder()
        // mode byte 0x07 — only 0 (push) and 1 (request) exist.
        let hex = "0107000000" + "0100" + "01000000" + "07"
        XCTAssertThrowsError(try decoder.feed(Data(hexString: hex)!)) { error in
            XCTAssertEqual(error as? FileChannelError, .invalidPayload(type: 0x01))
        }
    }
}
