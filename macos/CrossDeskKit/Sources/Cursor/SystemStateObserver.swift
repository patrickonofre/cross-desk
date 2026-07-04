import Foundation
import CoreGraphics
import AppKit

/// Watches for the system transitions that silently drop the cursor lock / hide
/// state (R19) and asks the owner to re-assert it. Waking from sleep, ending a
/// screensaver, reactivating the session, and reconfiguring displays all reset
/// volatile WindowServer state; none of them may require restarting the app to
/// restore correct behavior.
///
/// A wake emits a burst of notifications, so triggers are debounced onto a
/// single `onReassert` per settle window. Re-asserting twice is harmless
/// (idempotent), so the debounce only trades needless work for calm.
public final class SystemStateObserver: @unchecked Sendable {
    public enum Reason: String, Sendable {
        case wake, screensWake, sessionActive, displayReconfig
    }

    /// Fired (debounced) on the observer's queue after a system transition.
    public var onReassert: (@Sendable (Reason) -> Void)?

    private let center: NotificationCenter
    private let debounce: TimeInterval
    private let queue = DispatchQueue(label: "crossdesk.system-observer", qos: .utility)
    private let lock = NSLock()
    private var generation = 0
    private var observers: [NSObjectProtocol] = []
    private var displayCallbackRegistered = false

    /// `center` defaults to the workspace center where wake/session notifications
    /// are actually delivered (NOT `.default`); injected for tests.
    public init(
        center: NotificationCenter = NSWorkspace.shared.notificationCenter,
        debounce: TimeInterval = 1.0
    ) {
        self.center = center
        self.debounce = debounce
    }

    public func start() {
        subscribe(NSWorkspace.didWakeNotification, .wake)
        subscribe(NSWorkspace.screensDidWakeNotification, .screensWake)
        subscribe(NSWorkspace.sessionDidBecomeActiveNotification, .sessionActive)

        let ptr = Unmanaged.passUnretained(self).toOpaque()
        if CGDisplayRegisterReconfigurationCallback(Self.displayCallback, ptr) == .success {
            displayCallbackRegistered = true
        } else {
            Log.session.error("system-observer: display reconfiguration callback registration failed")
        }
        Log.session.info("system-observer: started")
    }

    public func stop() {
        observers.forEach(center.removeObserver)
        observers.removeAll()
        if displayCallbackRegistered {
            let ptr = Unmanaged.passUnretained(self).toOpaque()
            CGDisplayRemoveReconfigurationCallback(Self.displayCallback, ptr)
            displayCallbackRegistered = false
        }
    }

    private func subscribe(_ name: Notification.Name, _ reason: Reason) {
        let token = center.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
            self?.trigger(reason)
        }
        observers.append(token)
    }

    /// Coalesces a burst into one delayed `onReassert`: each trigger bumps the
    /// generation; only the latest survives the debounce window.
    func trigger(_ reason: Reason) {
        let mine: Int = lock.withLock {
            generation += 1
            return generation
        }
        queue.asyncAfter(deadline: .now() + debounce) { [weak self] in
            guard let self else { return }
            let current = self.lock.withLock { self.generation }
            guard mine == current else { return }
            Log.session.info("system-observer: reassert (\(reason.rawValue, privacy: .public))")
            self.onReassert?(reason)
        }
    }

    private static let displayCallback: CGDisplayReconfigurationCallBack = { _, flags, userInfo in
        guard let userInfo else { return }
        // Ignore the paired "begin" phase; the "changed" phase carries the new
        // layout. Over-triggering is harmless (debounced + idempotent).
        guard !flags.contains(.beginConfigurationFlag) else { return }
        let observer = Unmanaged<SystemStateObserver>.fromOpaque(userInfo).takeUnretainedValue()
        observer.trigger(.displayReconfig)
    }
}
