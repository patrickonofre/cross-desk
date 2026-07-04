import XCTest
import CoreGraphics
@testable import CrossDeskKit

final class SentinelPolicyTests: XCTestCase {
    func testWithinEpsilonNoRecovery() {
        let policy = SentinelPolicy(epsilon: 2)
        XCTAssertFalse(policy.needsRecovery(location: CGPoint(x: 100, y: 100),
                                            park: CGPoint(x: 101, y: 101)))
    }

    func testBeyondEpsilonNeedsRecovery() {
        let policy = SentinelPolicy(epsilon: 2)
        XCTAssertTrue(policy.needsRecovery(location: CGPoint(x: 100, y: 100),
                                           park: CGPoint(x: 100, y: 105)))
    }
}

final class CursorSentinelTests: XCTestCase {
    /// Mock effects: scriptable cursor position, recorded warp/dissociate/hooks.
    private final class Effects: @unchecked Sendable {
        let lock = NSLock()
        var location = CGPoint.zero
        private(set) var warps: [CGPoint] = []
        private(set) var dissociations: [Bool] = []
        private(set) var lockCalls = 0
        private(set) var unlockCalls = 0

        func make() -> SentinelEffects {
            SentinelEffects(
                warp: { [self] p in lock.withLock { warps.append(p) } },
                setDissociated: { [self] v in lock.withLock { dissociations.append(v) } },
                location: { [self] in lock.withLock { location } },
                onLock: { [self] in lock.withLock { lockCalls += 1 } },
                onUnlock: { [self] in lock.withLock { unlockCalls += 1 } }
            )
        }
    }

    /// Long interval so the real timer never fires — tick() is driven manually.
    private func sentinel(_ effects: Effects) -> CursorSentinel {
        CursorSentinel(effects: effects.make(), policy: SentinelPolicy(epsilon: 2), interval: 3600)
    }

    func testEngageWarpsDissociatesAndLocks() {
        let fx = Effects()
        let s = sentinel(fx)
        let park = CGPoint(x: 200, y: 300)

        s.engage(park: park)

        XCTAssertEqual(fx.warps, [park])
        XCTAssertEqual(fx.dissociations, [true])
        XCTAssertEqual(fx.lockCalls, 1)
    }

    func testTickRecoversOnDrift() {
        let fx = Effects()
        let s = sentinel(fx)
        let park = CGPoint(x: 200, y: 300)
        s.engage(park: park)

        fx.location = CGPoint(x: 260, y: 300) // brushed trackpad drifted the arrow
        s.tick()

        XCTAssertEqual(fx.warps, [park, park], "drift must re-warp to park")
        XCTAssertEqual(s.warpsRecovered, 1)
    }

    func testTickNoDriftDoesNothing() {
        let fx = Effects()
        let s = sentinel(fx)
        let park = CGPoint(x: 200, y: 300)
        s.engage(park: park)

        fx.location = CGPoint(x: 201, y: 301) // within ε
        s.tick()

        XCTAssertEqual(fx.warps, [park], "no re-warp within tolerance")
        XCTAssertEqual(s.warpsRecovered, 0)
    }

    func testReleaseReassociatesAndUnlocks() {
        let fx = Effects()
        let s = sentinel(fx)
        s.engage(park: CGPoint(x: 10, y: 10))

        s.release()

        XCTAssertEqual(fx.dissociations, [true, false])
        XCTAssertEqual(fx.unlockCalls, 1)
    }

    func testReleaseIsIdempotent() {
        let fx = Effects()
        let s = sentinel(fx)
        s.engage(park: .zero)

        s.release()
        s.release()
        s.release()

        XCTAssertEqual(fx.unlockCalls, 1, "release on an unlocked sentinel is a no-op")
    }

    func testTickAfterReleaseIsInert() {
        let fx = Effects()
        let s = sentinel(fx)
        s.engage(park: CGPoint(x: 5, y: 5))
        s.release()

        fx.location = CGPoint(x: 500, y: 500)
        s.tick()

        XCTAssertEqual(s.warpsRecovered, 0)
        XCTAssertEqual(fx.warps, [CGPoint(x: 5, y: 5)], "unlocked sentinel must not warp")
    }

    func testReassertWhenLockedReapplies() {
        let fx = Effects()
        let s = sentinel(fx)
        let park = CGPoint(x: 7, y: 8)
        s.engage(park: park)

        s.reassert()

        XCTAssertEqual(fx.warps, [park, park])
        XCTAssertEqual(fx.dissociations, [true, true])
        XCTAssertEqual(fx.lockCalls, 2)
    }

    func testReassertWhenUnlockedIsNoop() {
        let fx = Effects()
        let s = sentinel(fx)

        s.reassert()

        XCTAssertEqual(fx.warps, [])
        XCTAssertEqual(fx.lockCalls, 0)
    }

    func testEngageUpdatesParkWithoutDoubleTimer() {
        let fx = Effects()
        let s = sentinel(fx)
        s.engage(park: CGPoint(x: 1, y: 1))
        s.engage(park: CGPoint(x: 2, y: 2)) // re-engage updates park

        fx.location = CGPoint(x: 100, y: 100)
        s.tick()

        XCTAssertEqual(fx.warps.last, CGPoint(x: 2, y: 2))
        XCTAssertEqual(s.warpsRecovered, 1)
    }
}
