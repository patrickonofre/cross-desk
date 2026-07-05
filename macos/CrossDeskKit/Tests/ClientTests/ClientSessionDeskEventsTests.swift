import XCTest
import CoreGraphics
@testable import CrossDeskKit

/// Desk-UI events published by the client session (layout-ux T52): ENTER
/// exposes the return edge, LEAVE flips focus back. Synthetic transport
/// events go through `handle` — no network, no real cursor effects (the
/// sentinel gets no-op effects; `apply` no-ops without Accessibility).
final class ClientSessionDeskEventsTests: XCTestCase {
    private final class Box<T>: @unchecked Sendable {
        private let lock = NSLock()
        private var _value: T
        init(_ value: T) { _value = value }
        var value: T {
            get { lock.withLock { _value } }
            set { lock.withLock { _value = newValue } }
        }
    }

    private func makeSession() -> ClientSession {
        ClientSession(
            endpoint: .hostPort(host: "127.0.0.1", port: 65000),
            pairedSecret: "",
            pairingToken: "TEST-TOKEN",
            deviceName: "TestMac",
            conceal: false,
            injector: InputInjector(screens: { [CGRect(x: 0, y: 0, width: 1000, height: 800)] }),
            sentinelEffects: SentinelEffects(
                warp: { _ in },
                setDissociated: { _ in },
                location: { .zero },
                onLock: {},
                onUnlock: {}
            )
        )
    }

    func testEnterPublishesItsEdge() {
        let session = makeSession()
        let edges = Box<[EdgeSide]>([])
        session.onEnter = { edges.value.append($0) }

        session.handle(.messages([.enter(x: 0.5, y: 0.5, edge: .top)]))

        XCTAssertEqual(edges.value, [.top])
    }

    func testLeaveFiresAfterEnterAndLastEdgeStands() {
        let session = makeSession()
        let edges = Box<[EdgeSide]>([])
        let leaves = Box(0)
        session.onEnter = { edges.value.append($0) }
        session.onLeave = { leaves.value += 1 }

        session.handle(.messages([.enter(x: 0.1, y: 0.5, edge: .left)]))
        session.handle(.messages([.leave]))
        session.handle(.messages([.enter(x: 0.9, y: 0.5, edge: .right)]))

        XCTAssertEqual(edges.value, [.left, .right], "each ENTER republishes; LEAVE never erases the edge")
        XCTAssertEqual(leaves.value, 1)
    }

    func testInputMessagesDoNotTouchDeskCallbacks() {
        let session = makeSession()
        let touched = Box(false)
        session.onEnter = { _ in touched.value = true }
        session.onLeave = { touched.value = true }

        session.handle(.messages([.mouseMove(dx: 3, dy: 4), .key(hidUsage: 4, pressed: true), .key(hidUsage: 4, pressed: false)]))

        XCTAssertFalse(touched.value)
    }
}
