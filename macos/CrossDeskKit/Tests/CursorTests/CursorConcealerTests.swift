import XCTest
@testable import CrossDeskKit

final class CursorConcealerTests: XCTestCase {
    /// Records backend calls so the pure state machine can be asserted without
    /// touching the real WindowServer.
    private final class Recorder: @unchecked Sendable {
        let lock = NSLock()
        private(set) var hideCount = 0
        private(set) var showCount = 0
        private(set) var flag: [Bool] = []

        func backend(available: Bool) -> CursorConcealBackend {
            CursorConcealBackend(
                isAvailable: available,
                setBackgroundFlag: { [self] v in lock.lock(); flag.append(v); lock.unlock() },
                hide: { [self] in lock.lock(); hideCount += 1; lock.unlock() },
                show: { [self] in lock.lock(); showCount += 1; lock.unlock() }
            )
        }
    }

    func testHideShowBalanced() {
        let rec = Recorder()
        let concealer = CursorConcealer(backend: rec.backend(available: true))

        concealer.hide()
        concealer.show()

        XCTAssertEqual(rec.hideCount, 1)
        XCTAssertEqual(rec.showCount, 1)
        XCTAssertEqual(rec.flag, [true, false])
    }

    func testHideIsIdempotent() {
        let rec = Recorder()
        let concealer = CursorConcealer(backend: rec.backend(available: true))

        concealer.hide()
        concealer.hide()
        concealer.hide()

        XCTAssertEqual(rec.hideCount, 1, "repeat hide must not stack the system hide counter")
    }

    func testShowWithoutHideIsNoop() {
        let rec = Recorder()
        let concealer = CursorConcealer(backend: rec.backend(available: true))

        concealer.show()

        XCTAssertEqual(rec.showCount, 0)
    }

    func testUnavailableBackendNeverCallsCG() {
        let rec = Recorder()
        let concealer = CursorConcealer(backend: rec.backend(available: false))

        XCTAssertFalse(concealer.isAvailable)
        concealer.hide()
        concealer.reassert()

        XCTAssertEqual(rec.hideCount, 0)
        XCTAssertEqual(rec.flag, [])
    }

    func testReassertReappliesOnlyWhenHidden() {
        let rec = Recorder()
        let concealer = CursorConcealer(backend: rec.backend(available: true))

        concealer.reassert() // not hidden yet — no-op
        XCTAssertEqual(rec.hideCount, 0)

        concealer.hide()      // hideCount 1
        concealer.reassert()  // re-applies CG without touching the counter logic
        XCTAssertEqual(rec.hideCount, 2)

        concealer.show()
        concealer.reassert()  // shown again — no-op
        XCTAssertEqual(rec.hideCount, 2)
    }
}
