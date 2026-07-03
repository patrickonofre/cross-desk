import XCTest
@testable import CrossDeskKit

final class EdgeDetectorTests: XCTestCase {
    let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)

    func testRightEdgeCrossing() {
        let detector = EdgeDetector(side: .right)
        let entry = detector.crossing(at: CGPoint(x: 1440, y: 450), in: [screen])
        XCTAssertEqual(entry, CGPoint(x: 0.0, y: 0.5))
    }

    func testLeftEdgeCrossing() {
        let detector = EdgeDetector(side: .left)
        let entry = detector.crossing(at: CGPoint(x: 0, y: 225), in: [screen])
        XCTAssertEqual(entry, CGPoint(x: 1.0, y: 0.25))
    }

    func testTopEdgeCrossing() {
        let detector = EdgeDetector(side: .top)
        let entry = detector.crossing(at: CGPoint(x: 720, y: 0), in: [screen])
        XCTAssertEqual(entry, CGPoint(x: 0.5, y: 1.0))
    }

    func testBottomEdgeCrossing() {
        let detector = EdgeDetector(side: .bottom)
        let entry = detector.crossing(at: CGPoint(x: 360, y: 900), in: [screen])
        XCTAssertEqual(entry, CGPoint(x: 0.25, y: 0.0))
    }

    func testNoCrossingAwayFromEdge() {
        let detector = EdgeDetector(side: .right)
        XCTAssertNil(detector.crossing(at: CGPoint(x: 700, y: 450), in: [screen]))
    }

    func testInnerEdgeBetweenTwoMonitorsDoesNotTrigger() {
        let secondary = CGRect(x: 1440, y: 0, width: 1920, height: 1080)
        let detector = EdgeDetector(side: .right)
        // Right edge of the first display continues into the secondary — no crossing.
        XCTAssertNil(detector.crossing(at: CGPoint(x: 1440, y: 450), in: [screen, secondary]))
        // Right edge of the secondary is the outer edge — crossing.
        let entry = detector.crossing(at: CGPoint(x: 3360, y: 540), in: [screen, secondary])
        XCTAssertEqual(entry, CGPoint(x: 0.0, y: 0.5))
    }

    func testCornerIsClamped() {
        let detector = EdgeDetector(side: .right)
        let entry = detector.crossing(at: CGPoint(x: 1440, y: 900), in: [screen])
        XCTAssertEqual(entry, CGPoint(x: 0.0, y: 1.0))
    }

    func testPointOutsideAnyScreenReturnsNil() {
        let detector = EdgeDetector(side: .right)
        XCTAssertNil(detector.crossing(at: CGPoint(x: 5000, y: 5000), in: [screen]))
    }
}

