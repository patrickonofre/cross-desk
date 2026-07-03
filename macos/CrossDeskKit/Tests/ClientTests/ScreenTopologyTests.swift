import XCTest
@testable import CrossDeskKit

final class ScreenTopologyTests: XCTestCase {
    // Single 1920×1080 display at origin.
    let single = ScreenTopology(screens: [CGRect(x: 0, y: 0, width: 1920, height: 1080)])
    // Laptop 1440×900 left of an external 1920×1080 (tops aligned).
    let dual = ScreenTopology(screens: [
        CGRect(x: 0, y: 0, width: 1440, height: 900),
        CGRect(x: 1440, y: 0, width: 1920, height: 1080),
    ])

    // MARK: - Entry

    func testEntryLeftEdgeMapsNormalizedY() {
        let point = single.entryPoint(edge: .left, x: 1.0, y: 0.5)
        XCTAssertEqual(point.x, 1.0) // 1 px inside the left edge
        XCTAssertEqual(point.y, 540.0)
    }

    func testEntryRightEdgeOnDualLandsOnExternal() {
        let point = dual.entryPoint(edge: .right, x: 0.0, y: 0.5)
        XCTAssertEqual(point.x, 3359.0) // union.maxX - 1
        XCTAssertEqual(point.y, 540.0)
    }

    func testEntryIntoGapSnapsToNearestDisplay() {
        // Union spans y 0…1080, but at x≈0 the laptop only covers y 0…900.
        // Entering at the very bottom of the union's left edge falls in the gap.
        let point = dual.entryPoint(edge: .left, x: 1.0, y: 1.0)
        XCTAssertEqual(point.x, 1.0)
        XCTAssertEqual(point.y, 899.0) // clamped into the laptop display
    }

    // MARK: - Movement and containment

    func testFreeMoveInsideDisplay() {
        let moved = single.move(from: CGPoint(x: 100, y: 100), dx: 50, dy: -20, returnEdge: .left)
        XCTAssertEqual(moved.position, CGPoint(x: 150, y: 80))
        XCTAssertNil(moved.exit)
    }

    func testCrossingIntoAdjacentDisplay() {
        let moved = dual.move(from: CGPoint(x: 1430, y: 400), dx: 50, dy: 0, returnEdge: .left)
        XCTAssertEqual(moved.position, CGPoint(x: 1480, y: 400))
        XCTAssertNil(moved.exit)
    }

    func testNonReturnEdgeClampsInsteadOfExiting() {
        // Return edge is left; pushing past the right edge just pins the cursor.
        let moved = single.move(from: CGPoint(x: 1900, y: 500), dx: 500, dy: 0, returnEdge: .left)
        XCTAssertEqual(moved.position.x, 1919.0)
        XCTAssertNil(moved.exit)
    }

    func testDiagonalEscapeSlidesAlongEdge() {
        // dy pushes below the display; dx stays valid — cursor slides.
        let moved = single.move(from: CGPoint(x: 500, y: 1070), dx: 100, dy: 100, returnEdge: .left)
        XCTAssertEqual(moved.position, CGPoint(x: 600, y: 1079))
        XCTAssertNil(moved.exit)
    }

    func testInnerEdgeDoesNotExitEvenWhenItIsTheReturnEdge() {
        // Return edge right, but the laptop's right edge continues into the
        // external display: moving right must cross, not exit.
        let moved = dual.move(from: CGPoint(x: 1435, y: 400), dx: 20, dy: 0, returnEdge: .right)
        XCTAssertEqual(moved.position, CGPoint(x: 1455, y: 400))
        XCTAssertNil(moved.exit)
    }

    // MARK: - Return-edge exit

    func testExitThroughReturnEdgeReportsNormalizedPosition() {
        let moved = single.move(from: CGPoint(x: 3, y: 270), dx: -10, dy: 0, returnEdge: .left)
        XCTAssertNotNil(moved.exit)
        XCTAssertEqual(moved.exit!.x, 0.0)
        XCTAssertEqual(moved.exit!.y, 0.25, accuracy: 0.001)
        // Cursor stays pinned inside while the server decides.
        XCTAssertEqual(moved.position.x, 0.0)
    }

    func testExitFromExternalDisplayNormalizesAgainstThatDisplay() {
        let moved = dual.move(from: CGPoint(x: 3350, y: 540), dx: 30, dy: 0, returnEdge: .right)
        XCTAssertNotNil(moved.exit)
        XCTAssertEqual(moved.exit!.x, 1.0)
        XCTAssertEqual(moved.exit!.y, 0.5, accuracy: 0.001)
    }

    func testRepeatedOutwardMovesKeepReportingExit() {
        // Lost LEAVE_REQUEST retry mechanism: cursor pinned at the edge, user
        // keeps pushing — every outward move must report the exit again.
        var position = CGPoint(x: 2, y: 500)
        for _ in 0..<3 {
            let moved = single.move(from: position, dx: -30, dy: 0, returnEdge: .left)
            XCTAssertNotNil(moved.exit)
            position = moved.position
        }
    }

    func testTouchingTheReturnEdgeWithoutCrossingDoesNotExit() {
        // Landing exactly at the edge (still inside) must not hand control back.
        let moved = single.move(from: CGPoint(x: 10, y: 500), dx: -10, dy: 0, returnEdge: .left)
        XCTAssertNil(moved.exit)
        XCTAssertEqual(moved.position.x, 0.0)
    }

    func testVerticalExitThroughTop() {
        let moved = single.move(from: CGPoint(x: 960, y: 2), dx: 0, dy: -10, returnEdge: .top)
        XCTAssertNotNil(moved.exit)
        XCTAssertEqual(moved.exit!.x, 0.5, accuracy: 0.001)
        XCTAssertEqual(moved.exit!.y, 0.0)
    }

    func testNilReturnEdgeNeverExits() {
        let moved = single.move(from: CGPoint(x: 3, y: 270), dx: -100, dy: 0, returnEdge: nil)
        XCTAssertNil(moved.exit)
        XCTAssertEqual(moved.position.x, 0.0)
    }
}
