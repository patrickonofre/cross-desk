import Foundation

/// File channel framing and messages (PROTOCOL.md §8).
///
/// The file channel is a separate TCP+TLS-PSK connection with its OWN framing:
/// `type u8 · length u32 LE · payload` — length is u32 because DATA chunks
/// exceed the u16 of the main channel (§2). Unlike §2, an unknown type here is
/// a protocol error (the channel version is negotiated by FILE_HELLO.proto).
public enum FileChannelConstants {
    public static let version: UInt16 = 1
    /// DATA chunks must not exceed this (§8).
    public static let maxChunkSize = 64 * 1024
    /// Sanity cap on any frame's declared length — a stream claiming more is
    /// malformed (keeps a hostile peer from making us allocate GBs).
    static let maxFrameLength = UInt32(1 << 20)
}

public enum FileChannelError: Error, Equatable {
    case unknownType(UInt8)
    case invalidPayload(type: UInt8)
    case frameTooLarge(declared: UInt32)
}

public enum TransferMode: UInt8, Sendable {
    /// The side that connected sends the items.
    case push = 0
    /// The side that connected asks for the items.
    case request = 1
}

public enum FileItemKind: UInt8, Sendable {
    case file = 0
    case directory = 1
    case symlink = 2
}

public enum CancelOrigin: UInt8, Sendable {
    case sender = 0
    case receiver = 1
}

public enum FileChannelMessage: Equatable, Sendable {
    case fileHello(protoVersion: UInt16, transferId: UInt32, mode: TransferMode)
    /// `path` is relative with `/` separators. Receivers MUST reject `..`
    /// components, absolute paths and NUL bytes (§8) — enforced by the
    /// receiver pipeline, not by the decoder.
    case itemMeta(kind: FileItemKind, size: UInt64, path: String, symlinkTarget: String?)
    /// Belongs to the item of the last ITEM_META.
    case data(Data)
    /// Files carry the SHA-256 of their content; dir/symlink carry nothing.
    case itemDone(sha256: Data?)
    case transferDone
    case cancel(origin: CancelOrigin)
    /// Fatal; the connection closes after it (§8).
    case error(code: UInt8, message: String)

    enum WireType: UInt8 {
        case fileHello = 0x01
        case itemMeta = 0x02
        case data = 0x03
        case itemDone = 0x04
        case transferDone = 0x05
        case cancel = 0x06
        case error = 0x07
    }
}

// MARK: - Encoding

extension FileChannelMessage {
    public func encoded() -> Data {
        let (type, payload) = typeAndPayload()
        var data = Data(capacity: 5 + payload.count)
        data.append(type.rawValue)
        data.appendLE(UInt32(payload.count))
        data.append(payload)
        return data
    }

    private func typeAndPayload() -> (WireType, Data) {
        var payload = Data()
        switch self {
        case let .fileHello(protoVersion, transferId, mode):
            payload.appendLE(protoVersion)
            payload.appendLE(transferId)
            payload.append(mode.rawValue)
            return (.fileHello, payload)
        case let .itemMeta(kind, size, path, symlinkTarget):
            let pathBytes = Data(path.utf8)
            precondition(pathBytes.count <= Int(UInt16.max), "path exceeds u16 length")
            payload.append(kind.rawValue)
            payload.appendLE(size)
            payload.appendLE(UInt16(pathBytes.count))
            payload.append(pathBytes)
            if kind == .symlink {
                let targetBytes = Data((symlinkTarget ?? "").utf8)
                precondition(targetBytes.count <= Int(UInt16.max), "symlink target exceeds u16 length")
                payload.appendLE(UInt16(targetBytes.count))
                payload.append(targetBytes)
            }
            return (.itemMeta, payload)
        case let .data(bytes):
            precondition(bytes.count <= FileChannelConstants.maxChunkSize, "DATA chunk exceeds 64 KiB (§8)")
            return (.data, bytes)
        case let .itemDone(sha256):
            if let sha256 {
                precondition(sha256.count == 32, "sha256 must be 32 bytes")
                payload.append(sha256)
            }
            return (.itemDone, payload)
        case .transferDone:
            return (.transferDone, payload)
        case let .cancel(origin):
            payload.append(origin.rawValue)
            return (.cancel, payload)
        case let .error(code, message):
            let messageBytes = WireStrings.utf8Prefix(message, maxBytes: Int(UInt16.max))
            payload.append(code)
            payload.appendLE(UInt16(messageBytes.count))
            payload.append(messageBytes)
            return (.error, payload)
        }
    }
}

// MARK: - Streaming decoder

/// Incremental decoder for the TCP stream: buffers partial frames, emits
/// complete messages. Any throw is fatal for the channel (§8) — the caller
/// must close the connection.
public struct FileChannelDecoder {
    private var buffer = Data()

    public init() {}

    public mutating func feed(_ chunk: Data) throws -> [FileChannelMessage] {
        buffer.append(chunk)
        var messages: [FileChannelMessage] = []
        // Data's startIndex is NOT guaranteed to be 0 (slicing/removal shift
        // it) — every access below is relative to `start`, and consumed bytes
        // are dropped in one pass at the end.
        let start = buffer.startIndex
        var offset = 0
        while buffer.count - offset >= 5 {
            let type = buffer[start + offset]
            let length = UInt32(buffer[start + offset + 1])
                | UInt32(buffer[start + offset + 2]) << 8
                | UInt32(buffer[start + offset + 3]) << 16
                | UInt32(buffer[start + offset + 4]) << 24
            guard length <= FileChannelConstants.maxFrameLength else {
                throw FileChannelError.frameTooLarge(declared: length)
            }
            let frameEnd = offset + 5 + Int(length)
            guard buffer.count >= frameEnd else { break }
            let payload = buffer.subdata(in: (start + offset + 5)..<(start + frameEnd))
            guard let wireType = FileChannelMessage.WireType(rawValue: type) else {
                throw FileChannelError.unknownType(type)
            }
            messages.append(try Self.decodePayload(wireType, payload))
            offset = frameEnd
        }
        if offset > 0 {
            // Data(…) copies the remainder into a fresh buffer (startIndex 0).
            buffer = Data(buffer.dropFirst(offset))
        }
        return messages
    }

    private static func decodePayload(
        _ type: FileChannelMessage.WireType, _ payload: Data
    ) throws -> FileChannelMessage {
        var reader = Reader(payload)
        func invalid() -> FileChannelError { .invalidPayload(type: type.rawValue) }
        switch type {
        case .fileHello:
            guard let version = try? reader.u16(), let transferId = try? reader.u32(),
                  let modeByte = try? reader.u8(), let mode = TransferMode(rawValue: modeByte)
            else { throw invalid() }
            return .fileHello(protoVersion: version, transferId: transferId, mode: mode)
        case .itemMeta:
            guard let kindByte = try? reader.u8(), let kind = FileItemKind(rawValue: kindByte),
                  let size = try? reader.u64(),
                  let pathLen = try? reader.u16(),
                  let pathBytes = try? reader.bytes(Int(pathLen)),
                  let path = String(data: pathBytes, encoding: .utf8) else { throw invalid() }
            var target: String?
            if kind == .symlink {
                guard let targetLen = try? reader.u16(),
                      let targetBytes = try? reader.bytes(Int(targetLen)),
                      let decoded = String(data: targetBytes, encoding: .utf8) else { throw invalid() }
                target = decoded
            }
            return .itemMeta(kind: kind, size: size, path: path, symlinkTarget: target)
        case .data:
            guard payload.count <= FileChannelConstants.maxChunkSize else { throw invalid() }
            return .data(payload)
        case .itemDone:
            if payload.isEmpty { return .itemDone(sha256: nil) }
            guard payload.count == 32 else { throw invalid() }
            return .itemDone(sha256: payload)
        case .transferDone:
            return .transferDone
        case .cancel:
            guard let originByte = try? reader.u8(),
                  let origin = CancelOrigin(rawValue: originByte) else { throw invalid() }
            return .cancel(origin: origin)
        case .error:
            guard let code = try? reader.u8(), let msgLen = try? reader.u16(),
                  let msgBytes = try? reader.bytes(Int(msgLen)),
                  let message = String(data: msgBytes, encoding: .utf8) else { throw invalid() }
            return .error(code: code, message: message)
        }
    }
}
