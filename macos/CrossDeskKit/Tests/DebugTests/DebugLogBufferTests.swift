import XCTest
@testable import CrossDeskKit

final class DebugLogBufferTests: XCTestCase {
    func testAppendPreservesOrder() {
        let buf = DebugLogBuffer(capacity: 10)
        buf.append("a")
        buf.append("b")
        buf.append("c")
        XCTAssertEqual(buf.snapshot(), ["a", "b", "c"])
    }

    func testCapacityDropsOldestFIFO() {
        let buf = DebugLogBuffer(capacity: 3)
        for i in 0..<5 {
            buf.append("line\(i)")
        }
        XCTAssertEqual(buf.snapshot(), ["line2", "line3", "line4"])
    }

    func testClearEmptiesBuffer() {
        let buf = DebugLogBuffer(capacity: 10)
        buf.append("a")
        buf.clear()
        XCTAssertEqual(buf.snapshot(), [])
    }

    func testOnUpdateFiresWithCurrentSnapshot() {
        let buf = DebugLogBuffer(capacity: 10)
        let expectation = expectation(description: "onUpdate fires")
        buf.onUpdate = { snapshot in
            XCTAssertEqual(snapshot, ["only line"])
            expectation.fulfill()
        }
        buf.append("only line")
        wait(for: [expectation], timeout: 1)
    }
}
