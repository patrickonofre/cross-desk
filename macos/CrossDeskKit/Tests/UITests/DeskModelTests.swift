import XCTest
import CoreGraphics
@testable import CrossDeskKit

final class DeskModelTests: XCTestCase {
    // MacBook below-left of an external display, like a typical desk (CG
    // global coords, y down).
    private let desk = [
        DisplayInfo(bounds: CGRect(x: 0, y: 0, width: 2560, height: 1440), isBuiltin: false, name: "Studio Display"),
        DisplayInfo(bounds: CGRect(x: 300, y: 1440, width: 1512, height: 982), isBuiltin: true, name: "Built-in")
    ]

    func testGeometryOffsetsMonitorsToUnionOrigin() {
        let geo = DeskModel.geometry(displays: desk, edge: .right)
        XCTAssertEqual(geo.union, CGRect(x: 0, y: 0, width: 2560, height: 2422))
        XCTAssertEqual(geo.monitors[0].rect.origin, .zero)
        XCTAssertEqual(geo.monitors[1].rect, CGRect(x: 300, y: 1440, width: 1512, height: 982))
        XCTAssertTrue(geo.monitors[1].isBuiltin)
    }

    func testGeometryNormalizesNegativeGlobalOrigins() {
        // A display arranged left of the main one has negative global X.
        let displays = [
            DisplayInfo(bounds: CGRect(x: -1920, y: 0, width: 1920, height: 1080), isBuiltin: false, name: "Ext"),
            DisplayInfo(bounds: CGRect(x: 0, y: 0, width: 1512, height: 982), isBuiltin: true, name: "Built-in")
        ]
        let geo = DeskModel.geometry(displays: displays, edge: .left)
        XCTAssertEqual(geo.union.origin, .zero)
        XCTAssertEqual(geo.monitors[0].rect.origin, .zero)
        XCTAssertEqual(geo.monitors[1].rect.origin, CGPoint(x: 1920, y: 0))
    }

    func testPeerSlotSitsOutsideTheChosenEdge() {
        let union = CGRect(x: 0, y: 0, width: 1000, height: 600)
        XCTAssertGreaterThan(DeskModel.peerSlot(edge: .right, union: union).minX, union.maxX)
        XCTAssertLessThan(DeskModel.peerSlot(edge: .left, union: union).maxX, union.minX)
        XCTAssertLessThan(DeskModel.peerSlot(edge: .top, union: union).maxY, union.minY)
        XCTAssertGreaterThan(DeskModel.peerSlot(edge: .bottom, union: union).minY, union.maxY)
    }

    func testPeerSlotIsCenteredAndCanvasContainsEverything() {
        let geo = DeskModel.geometry(displays: desk, edge: .top)
        XCTAssertEqual(geo.peer.midX, geo.union.midX, accuracy: 0.001)
        XCTAssertTrue(geo.canvas.contains(geo.peer))
        for monitor in geo.monitors {
            XCTAssertTrue(geo.canvas.contains(monitor.rect))
        }
    }

    func testDropOutsideEachSidePicksThatEdge() {
        let union = CGRect(x: 0, y: 0, width: 1000, height: 600)
        XCTAssertEqual(DeskModel.edge(fromDrop: CGPoint(x: 1400, y: 300), union: union, current: .left), .right)
        XCTAssertEqual(DeskModel.edge(fromDrop: CGPoint(x: -300, y: 300), union: union, current: .right), .left)
        XCTAssertEqual(DeskModel.edge(fromDrop: CGPoint(x: 500, y: -200), union: union, current: .right), .top)
        XCTAssertEqual(DeskModel.edge(fromDrop: CGPoint(x: 500, y: 900), union: union, current: .right), .bottom)
    }

    func testDropInsideUnionKeepsCurrentEdge() {
        let union = CGRect(x: 0, y: 0, width: 1000, height: 600)
        XCTAssertEqual(DeskModel.edge(fromDrop: CGPoint(x: 500, y: 300), union: union, current: .top), .top)
    }

    func testCornerTieKeepsCurrentEdgeWhenItIsAmongTheMaxima() {
        let union = CGRect(x: 0, y: 0, width: 1000, height: 600)
        // Exactly diagonal from the bottom-right corner: right and bottom tie.
        let corner = CGPoint(x: 1200, y: 800)
        XCTAssertEqual(DeskModel.edge(fromDrop: corner, union: union, current: .bottom), .bottom)
        XCTAssertEqual(DeskModel.edge(fromDrop: corner, union: union, current: .right), .right)
    }

    func testPhaseTable() {
        XCTAssertEqual(DeskModel.phase(sessionState: .stopped, paired: true, focusedHere: true), .empty)
        XCTAssertEqual(DeskModel.phase(sessionState: .waitingPeer, paired: false, focusedHere: true), .pairing)
        XCTAssertEqual(DeskModel.phase(sessionState: .waitingPeer, paired: true, focusedHere: true), .armed)
        XCTAssertEqual(DeskModel.phase(sessionState: .connected(peer: "x"), paired: true, focusedHere: true), .localFocus)
        XCTAssertEqual(DeskModel.phase(sessionState: .connected(peer: "x"), paired: true, focusedHere: false), .remoteFocus)
        XCTAssertEqual(DeskModel.phase(sessionState: .controllingRemote(peer: "x"), paired: true, focusedHere: true), .remoteFocus)
        XCTAssertEqual(DeskModel.phase(sessionState: .error("boom"), paired: false, focusedHere: true), .error("boom"))
    }

    func testCrossingHintOnlyBetweenPairingAndFirstCrossing() {
        XCTAssertEqual(
            DeskModel.crossingHint(phase: .armed, edge: .right, firstCrossingDone: false),
            "Empurre o cursor pela borda direita para atravessar"
        )
        XCTAssertNotNil(DeskModel.crossingHint(phase: .localFocus, edge: .top, firstCrossingDone: false))
        XCTAssertNil(DeskModel.crossingHint(phase: .pairing, edge: .right, firstCrossingDone: false))
        XCTAssertNil(DeskModel.crossingHint(phase: .remoteFocus, edge: .right, firstCrossingDone: false))
        XCTAssertNil(DeskModel.crossingHint(phase: .armed, edge: .right, firstCrossingDone: true))
    }

    func testCrossingHintNamesEachSide() {
        for (edge, word) in [(EdgeSide.left, "esquerda"), (.right, "direita"), (.top, "de cima"), (.bottom, "de baixo")] {
            let hint = DeskModel.crossingHint(phase: .armed, edge: edge, firstCrossingDone: false)
            XCTAssertEqual(hint?.contains(word), true, "hint for \(edge) should name '\(word)'")
        }
    }
}

final class DisplaysInfoTests: XCTestCase {
    func testInfosMatchesActiveBounds() {
        // Headless CI has zero displays — the invariant (same list, same
        // bounds, non-empty names) must hold for whatever count exists.
        let infos = Displays.infos()
        let bounds = Displays.activeBounds()
        XCTAssertEqual(infos.count, bounds.count)
        for (info, rect) in zip(infos, bounds) {
            XCTAssertEqual(info.bounds, rect)
            XCTAssertFalse(info.name.isEmpty)
        }
    }
}
