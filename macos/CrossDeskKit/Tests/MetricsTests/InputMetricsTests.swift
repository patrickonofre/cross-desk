import XCTest
@testable import CrossDeskKit

final class InputMetricsTests: XCTestCase {
    func testBumpAccumulates() {
        let m = InputMetrics()
        m.bump(.capturedMouseMove)
        m.bump(.capturedMouseMove, by: 4)
        m.bump(.datagramsSent)
        XCTAssertEqual(m.value(.capturedMouseMove), 5)
        XCTAssertEqual(m.value(.datagramsSent), 1)
        XCTAssertEqual(m.value(.reasserts), 0)
    }

    func testResetClears() {
        let m = InputMetrics()
        m.bump(.injectedMessages, by: 10)
        m.reset()
        XCTAssertEqual(m.value(.injectedMessages), 0)
    }
}

final class MoveCoalescerTests: XCTestCase {
    func testConsecutiveMovesFuseWithSummedDeltas() {
        let (out, merges) = MoveCoalescer.coalesce([
            .mouseMove(dx: 1, dy: 2),
            .mouseMove(dx: 3, dy: -1),
            .mouseMove(dx: 0, dy: 4),
        ])
        XCTAssertEqual(out, [.mouseMove(dx: 4, dy: 5)])
        XCTAssertEqual(merges, 2, "3 moves → 1 message = 2 merges")
    }

    func testNonMovesSplitRunsAndArePreserved() {
        let (out, merges) = MoveCoalescer.coalesce([
            .mouseMove(dx: 1, dy: 0),
            .mouseMove(dx: 1, dy: 0),
            .mouseButton(button: 1, pressed: true),
            .mouseMove(dx: 5, dy: 5),
            .key(hidUsage: 0x04, pressed: true),
        ])
        XCTAssertEqual(out, [
            .mouseMove(dx: 2, dy: 0),
            .mouseButton(button: 1, pressed: true),
            .mouseMove(dx: 5, dy: 5),
            .key(hidUsage: 0x04, pressed: true),
        ])
        XCTAssertEqual(merges, 1, "first run collapses 2→1; the lone move is unchanged")
    }

    func testNoMovesIsIdentity() {
        let input: [Message] = [.heartbeat, .key(hidUsage: 0x04, pressed: true)]
        let (out, merges) = MoveCoalescer.coalesce(input)
        XCTAssertEqual(out, input)
        XCTAssertEqual(merges, 0)
    }

    func testEmptyIsEmpty() {
        let (out, merges) = MoveCoalescer.coalesce([])
        XCTAssertTrue(out.isEmpty)
        XCTAssertEqual(merges, 0)
    }
}
