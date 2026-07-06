import Foundation

/// FIFO line buffer for the debug console (debug-console R47) — caps memory/UI
/// growth during a long session. Confined to `queue`; snapshots delivered via
/// `onUpdate` (mirrors DTLSClient/ServerSession's callback-over-queue pattern).
public final class DebugLogBuffer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "crossdesk.debug.logbuffer")
    private var lines: [String] = []
    private let capacity: Int

    /// Called on `queue` with the full current snapshot after every mutation.
    public var onUpdate: (@Sendable ([String]) -> Void)?

    public init(capacity: Int = 2000) {
        self.capacity = capacity
    }

    public func append(_ line: String) {
        queue.async { [self] in
            lines.append(line)
            if lines.count > capacity {
                lines.removeFirst(lines.count - capacity)
            }
            onUpdate?(lines)
        }
    }

    public func clear() {
        queue.async { [self] in
            lines.removeAll()
            onUpdate?(lines)
        }
    }

    public func snapshot() -> [String] {
        queue.sync { lines }
    }
}
