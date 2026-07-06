import XCTest
@testable import CrossDeskKit

final class LogStreamerTests: XCTestCase {
    /// Real integration test (no mocking `log stream`) — matches this project's
    /// existing style of exercising real OS/network paths (TransportLoopbackTests).
    func testStreamsOwnAppLogLinesLive() {
        let marker = "logstreamer-test-\(UUID().uuidString)"
        let buffer = DebugLogBuffer()
        let streamer = LogStreamer(buffer: buffer)
        let found = expectation(description: "marker line arrives via log stream")
        found.assertForOverFulfill = false

        buffer.onUpdate = { lines in
            if lines.contains(where: { $0.contains(marker) }) {
                found.fulfill()
            }
        }

        streamer.start()
        // `log stream` needs a moment to attach before its predicate is live —
        // emitting immediately can race the subprocess startup.
        Thread.sleep(forTimeInterval: 1.5)
        Log.app.info("\(marker, privacy: .public)")

        wait(for: [found], timeout: 10)
        streamer.stop()
    }
}
