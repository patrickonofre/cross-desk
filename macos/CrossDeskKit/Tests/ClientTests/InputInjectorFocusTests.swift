import XCTest
import CoreGraphics
@testable import CrossDeskKit

/// The focus callbacks that drive the cursor lock (R18). `apply` posts CGEvents
/// (no-ops without Accessibility, never crashes), so the callbacks are the
/// observable behavior here.
final class InputInjectorFocusTests: XCTestCase {
    /// Sendable recorder — the injector's callbacks are `@Sendable`.
    private final class Box<T>: @unchecked Sendable {
        private let lock = NSLock()
        private var _value: T
        init(_ value: T) { _value = value }
        var value: T {
            get { lock.withLock { _value } }
            set { lock.withLock { _value = newValue } }
        }
    }

    private func injector() -> InputInjector {
        InputInjector(screens: { [CGRect(x: 0, y: 0, width: 1000, height: 800)] })
    }

    func testEnterFiresFocusGained() {
        let inj = injector()
        let gained = Box(0)
        let lost = Box(false)
        inj.onFocusGained = { gained.value += 1 }
        inj.onFocusLost = { _ in lost.value = true }

        inj.apply(.enter(x: 0.5, y: 0.5, edge: .left))

        XCTAssertEqual(gained.value, 1)
        XCTAssertFalse(lost.value, "no focus loss on ENTER")
    }

    func testLeaveFiresFocusLostWithParkOnReturnEdge() {
        let inj = injector()
        inj.apply(.enter(x: 0.5, y: 0.5, edge: .left)) // establishes returnEdge = .left

        let park = Box<CGPoint?>(nil)
        inj.onFocusLost = { park.value = $0 }
        inj.apply(.leave)

        let unwrapped = park.value
        XCTAssertNotNil(unwrapped)
        // Parked on the left return edge → x pinned to the display's left border.
        XCTAssertEqual(unwrapped?.x ?? .nan, 0, accuracy: 1.5)
    }

    func testLeaveWithoutEnterStillFiresFocusLost() {
        let inj = injector()
        let fired = Box(false)
        inj.onFocusLost = { _ in fired.value = true }

        inj.apply(.leave) // no prior ENTER — must still hand control back to lock

        XCTAssertTrue(fired.value)
    }
}
