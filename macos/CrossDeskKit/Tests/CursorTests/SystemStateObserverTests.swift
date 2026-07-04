import XCTest
import AppKit
@testable import CrossDeskKit

final class SystemStateObserverTests: XCTestCase {
    private final class Counter: @unchecked Sendable {
        let lock = NSLock()
        private(set) var reasons: [SystemStateObserver.Reason] = []
        func record(_ r: SystemStateObserver.Reason) { lock.withLock { reasons.append(r) } }
        var count: Int { lock.withLock { reasons.count } }
    }

    func testWakeNotificationTriggersReassert() {
        let center = NotificationCenter()
        let observer = SystemStateObserver(center: center, debounce: 0.05)
        let counter = Counter()
        let done = expectation(description: "reassert fired")
        observer.onReassert = { reason in
            counter.record(reason)
            done.fulfill()
        }
        observer.start()
        defer { observer.stop() }

        center.post(name: NSWorkspace.didWakeNotification, object: nil)

        wait(for: [done], timeout: 1)
        XCTAssertEqual(counter.reasons, [.wake])
    }

    func testBurstIsDebouncedToOne() {
        let center = NotificationCenter()
        let observer = SystemStateObserver(center: center, debounce: 0.15)
        let counter = Counter()
        observer.onReassert = { counter.record($0) }
        observer.start()
        defer { observer.stop() }

        // A real wake fires several notifications back to back.
        center.post(name: NSWorkspace.didWakeNotification, object: nil)
        center.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
        center.post(name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)

        let settle = expectation(description: "debounce settled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { settle.fulfill() }
        wait(for: [settle], timeout: 1)

        XCTAssertEqual(counter.count, 1, "a burst within the window collapses to one reassert")
    }

    func testStopSilencesFurtherNotifications() {
        let center = NotificationCenter()
        let observer = SystemStateObserver(center: center, debounce: 0.05)
        let counter = Counter()
        observer.onReassert = { counter.record($0) }
        observer.start()
        observer.stop()

        center.post(name: NSWorkspace.didWakeNotification, object: nil)

        let settle = expectation(description: "settled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { settle.fulfill() }
        wait(for: [settle], timeout: 1)

        XCTAssertEqual(counter.count, 0)
    }
}
