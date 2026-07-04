import Foundation

/// CrossDesk protocol constants. See .specs/protocol/PROTOCOL.md (v0.1).
public enum ProtocolConstants {
    public static let version: UInt16 = 1
    public static let defaultPort: UInt16 = 24800
    /// Application datagrams must stay under this size to avoid IP fragmentation.
    public static let maxDatagramSize = 1200
}

public enum ProtocolError: Error, Equatable {
    case truncated
    case invalidPayload(type: UInt8)
}

/// Wire messages, PROTOCOL.md §3. All multi-byte fields are little-endian.
public enum Message: Equatable, Sendable {
    case hello(protoVersion: UInt16, name: String)
    case helloAck(protoVersion: UInt16)
    case heartbeat
    case bye
    /// `edge` = client edge the cursor enters through (also its return edge).
    case enter(x: Float, y: Float, edge: EdgeSide)
    case leave
    /// C→S: client cursor crossed its return edge; may repeat until LEAVE
    /// arrives (UDP loss) — the server must treat it as idempotent.
    case leaveRequest(x: Float, y: Float)
    case mouseMove(dx: Float, dy: Float)
    case mouseButton(button: UInt8, pressed: Bool)
    case scroll(dx: Float, dy: Float)
    /// High-fidelity trackpad scroll: pixel deltas + gesture/momentum phase (R20).
    case scrollContinuous(dx: Float, dy: Float, phase: ScrollPhase, momentum: MomentumPhase)
    case key(hidUsage: UInt16, pressed: Bool)

    enum WireType: UInt8 {
        case hello = 0x01
        case helloAck = 0x02
        case heartbeat = 0x03
        case bye = 0x04
        case enter = 0x10
        case leave = 0x11
        case leaveRequest = 0x12
        case mouseMove = 0x20
        case mouseButton = 0x21
        case scroll = 0x22
        case scrollContinuous = 0x23
        case key = 0x30
    }
}

// MARK: - Encoding

extension Message {
    public func encoded() -> Data {
        let (type, payload) = typeAndPayload()
        var data = Data(capacity: 3 + payload.count)
        data.append(type.rawValue)
        data.appendLE(UInt16(payload.count))
        data.append(payload)
        return data
    }

    private func typeAndPayload() -> (WireType, Data) {
        var payload = Data()
        switch self {
        case let .hello(protoVersion, name):
            let nameBytes = Data(name.utf8.prefix(255))
            payload.appendLE(protoVersion)
            payload.append(UInt8(nameBytes.count))
            payload.append(nameBytes)
            return (.hello, payload)
        case let .helloAck(protoVersion):
            payload.appendLE(protoVersion)
            return (.helloAck, payload)
        case .heartbeat:
            return (.heartbeat, payload)
        case .bye:
            return (.bye, payload)
        case let .enter(x, y, edge):
            payload.appendLE(x.bitPattern)
            payload.appendLE(y.bitPattern)
            payload.append(edge.wireValue)
            return (.enter, payload)
        case .leave:
            return (.leave, payload)
        case let .leaveRequest(x, y):
            payload.appendLE(x.bitPattern)
            payload.appendLE(y.bitPattern)
            return (.leaveRequest, payload)
        case let .mouseMove(dx, dy):
            payload.appendLE(dx.bitPattern)
            payload.appendLE(dy.bitPattern)
            return (.mouseMove, payload)
        case let .mouseButton(button, pressed):
            payload.append(button)
            payload.append(pressed ? 1 : 0)
            return (.mouseButton, payload)
        case let .scroll(dx, dy):
            payload.appendLE(dx.bitPattern)
            payload.appendLE(dy.bitPattern)
            return (.scroll, payload)
        case let .scrollContinuous(dx, dy, phase, momentum):
            payload.appendLE(dx.bitPattern)
            payload.appendLE(dy.bitPattern)
            payload.append(phase.rawValue)
            payload.append(momentum.rawValue)
            return (.scrollContinuous, payload)
        case let .key(hidUsage, pressed):
            payload.appendLE(hidUsage)
            payload.append(pressed ? 1 : 0)
            return (.key, payload)
        }
    }

    /// Encodes several messages into one datagram payload (PROTOCOL.md §2).
    public static func encodeAll(_ messages: [Message]) -> Data {
        messages.reduce(into: Data()) { $0.append($1.encoded()) }
    }
}

// MARK: - Decoding

extension Message {
    /// Decodes all messages in a datagram. Unknown message types are skipped
    /// (forward compatibility); truncated frames throw.
    public static func decodeAll(_ data: Data) throws -> [Message] {
        var messages: [Message] = []
        var reader = Reader(data)
        while !reader.isAtEnd {
            let type = try reader.u8()
            let length = try reader.u16()
            let payload = try reader.bytes(Int(length))
            guard let wireType = WireType(rawValue: type) else { continue }
            messages.append(try decodePayload(wireType, payload))
        }
        return messages
    }

    private static func decodePayload(_ type: WireType, _ payload: Data) throws -> Message {
        var reader = Reader(payload)
        func invalid() -> ProtocolError { .invalidPayload(type: type.rawValue) }
        switch type {
        case .hello:
            guard let version = try? reader.u16(),
                  let nameLen = try? reader.u8(),
                  let nameBytes = try? reader.bytes(Int(nameLen)),
                  let name = String(data: nameBytes, encoding: .utf8) else { throw invalid() }
            return .hello(protoVersion: version, name: name)
        case .helloAck:
            guard let version = try? reader.u16() else { throw invalid() }
            return .helloAck(protoVersion: version)
        case .heartbeat:
            return .heartbeat
        case .bye:
            return .bye
        case .enter:
            guard let x = try? reader.f32(), let y = try? reader.f32(),
                  let edgeByte = try? reader.u8(),
                  let edge = EdgeSide(wireValue: edgeByte) else { throw invalid() }
            return .enter(x: x, y: y, edge: edge)
        case .leave:
            return .leave
        case .leaveRequest:
            guard let x = try? reader.f32(), let y = try? reader.f32() else { throw invalid() }
            return .leaveRequest(x: x, y: y)
        case .mouseMove:
            guard let dx = try? reader.f32(), let dy = try? reader.f32() else { throw invalid() }
            return .mouseMove(dx: dx, dy: dy)
        case .mouseButton:
            guard let button = try? reader.u8(), let pressed = try? reader.u8() else { throw invalid() }
            return .mouseButton(button: button, pressed: pressed != 0)
        case .scroll:
            guard let dx = try? reader.f32(), let dy = try? reader.f32() else { throw invalid() }
            return .scroll(dx: dx, dy: dy)
        case .scrollContinuous:
            guard let dx = try? reader.f32(), let dy = try? reader.f32(),
                  let phaseByte = try? reader.u8(), let momentumByte = try? reader.u8()
            else { throw invalid() }
            // Unknown phase values decode to .none rather than throwing — a future
            // phase constant must not poison the whole datagram (forward-compat).
            return .scrollContinuous(
                dx: dx, dy: dy,
                phase: ScrollPhase(rawValue: phaseByte) ?? .none,
                momentum: MomentumPhase(rawValue: momentumByte) ?? .none
            )
        case .key:
            guard let usage = try? reader.u16(), let pressed = try? reader.u8() else { throw invalid() }
            return .key(hidUsage: usage, pressed: pressed != 0)
        }
    }
}

// MARK: - Little-endian helpers

private struct Reader {
    private let data: Data
    private var offset: Int

    init(_ data: Data) {
        self.data = data
        self.offset = data.startIndex
    }

    var isAtEnd: Bool { offset >= data.endIndex }

    mutating func u8() throws -> UInt8 {
        guard offset < data.endIndex else { throw ProtocolError.truncated }
        defer { offset += 1 }
        return data[offset]
    }

    mutating func u16() throws -> UInt16 {
        let lo = try u8()
        let hi = try u8()
        return UInt16(lo) | (UInt16(hi) << 8)
    }

    mutating func f32() throws -> Float {
        var bits: UInt32 = 0
        for shift in stride(from: 0, to: 32, by: 8) {
            bits |= UInt32(try u8()) << UInt32(shift)
        }
        return Float(bitPattern: bits)
    }

    mutating func bytes(_ count: Int) throws -> Data {
        guard count >= 0, data.endIndex - offset >= count else { throw ProtocolError.truncated }
        defer { offset += count }
        return data.subdata(in: offset..<(offset + count))
    }
}

extension Data {
    mutating func appendLE(_ value: UInt16) {
        append(UInt8(value & 0xFF))
        append(UInt8(value >> 8))
    }

    mutating func appendLE(_ value: UInt32) {
        for shift in stride(from: 0, to: 32, by: 8) {
            append(UInt8((value >> UInt32(shift)) & 0xFF))
        }
    }
}
