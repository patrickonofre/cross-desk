import Foundation

/// Per-session input counters (R24). Cheap atomic bumps at the capture, inject,
/// and transport points; dumped to the structured log on stop and periodically.
/// Feeds the input-polish UAT and the still-open latency measurement (R14).
public final class InputMetrics: @unchecked Sendable {
    public enum Counter: String, CaseIterable, Sendable {
        case capturedMouseMove, capturedScroll, capturedScrollContinuous
        case capturedButton, capturedKey
        case injectedMessages
        case datagramsSent, datagramsReceived
        case moveMerges     // R23 coalescing
        case warpsRecovered // R18 watchdog
        case reasserts      // R19 system transitions
    }

    private let lock = NSLock()
    private var counts: [Counter: Int] = [:]

    public init() {}

    public func bump(_ counter: Counter, by n: Int = 1) {
        lock.withLock { counts[counter, default: 0] += n }
    }

    public func value(_ counter: Counter) -> Int {
        lock.withLock { counts[counter] ?? 0 }
    }

    public func snapshot() -> [Counter: Int] {
        lock.withLock { counts }
    }

    public func reset() {
        lock.withLock { counts.removeAll() }
    }

    /// Logs the non-zero counters in a stable order.
    public func logSummary(context: String) {
        let snap = snapshot()
        let line = Counter.allCases
            .compactMap { c in snap[c].map { "\(c.rawValue)=\($0)" } }
            .joined(separator: " ")
        Log.session.info("metrics [\(context, privacy: .public)] \(line, privacy: .public)")
    }
}

/// Fuses consecutive `mouseMove` messages into a single summed move (R23).
///
/// Dormant by default: under 90–120 Hz trackpads the send path can build a
/// backlog of moves; collapsing a run into one datagram cuts it without adding
/// latency (an empty queue coalesces to itself). Wired into the hot path only
/// once metrics confirm a real backlog (T28) — kept pure and tested meanwhile.
public enum MoveCoalescer {
    public static func coalesce(_ messages: [Message]) -> (messages: [Message], merges: Int) {
        var out: [Message] = []
        var pendingX: Float = 0
        var pendingY: Float = 0
        var pendingCount = 0
        var movesIn = 0
        var movesOut = 0

        func flush() {
            guard pendingCount > 0 else { return }
            out.append(.mouseMove(dx: pendingX, dy: pendingY))
            movesOut += 1
            pendingX = 0; pendingY = 0; pendingCount = 0
        }

        for message in messages {
            if case let .mouseMove(dx, dy) = message {
                pendingX += dx; pendingY += dy; pendingCount += 1; movesIn += 1
            } else {
                flush()
                out.append(message)
            }
        }
        flush()
        return (out, merges: movesIn - movesOut)
    }
}
