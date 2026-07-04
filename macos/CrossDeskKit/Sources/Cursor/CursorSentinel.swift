import Foundation
import CoreGraphics

/// Pure decision for the lock watchdog (R18): has the cursor drifted far enough
/// from its park point that we must re-warp it back? Split out so the policy is
/// testable without timers or CoreGraphics.
public struct SentinelPolicy: Sendable {
    /// Tolerance (px). Sub-pixel jitter from the physical mouse is ignored;
    /// anything past this is real drift the dissociation failed to stop.
    public let epsilon: CGFloat

    public init(epsilon: CGFloat = 2) {
        self.epsilon = epsilon
    }

    public func needsRecovery(location: CGPoint, park: CGPoint) -> Bool {
        hypot(location.x - park.x, location.y - park.y) > epsilon
    }
}

/// Keeps this machine's arrow frozen while it is connected but unfocused (R18).
///
/// `CGAssociateMouseAndMouseCursorPosition(0)` alone is a single global write to
/// volatile WindowServer state; it silently lapses across sleep/wake and
/// screensaver (see design.md — neither Deskflow nor lan-mouse trust it alone).
/// The sentinel hardens it with a low-frequency watchdog: while locked it polls
/// the cursor position (no new TCC — `CGEvent(source: nil).location`) and, on
/// drift past ε, re-warps to the park point and re-dissociates. The poll only
/// runs while locked (4 Hz — invisible in Activity Monitor).
///
/// `release()` is unconditional and idempotent: the lock must NEVER outlive the
/// link that created it (mirrors the server's unconditional unsuppress).
public final class CursorSentinel: @unchecked Sendable {
    public enum Target: Equatable, Sendable {
        case unlocked
        case locked(park: CGPoint)
    }

    private let effects: SentinelEffects
    private let policy: SentinelPolicy
    private let interval: TimeInterval
    private let queue = DispatchQueue(label: "crossdesk.cursor.sentinel", qos: .userInitiated)

    private let lock = NSLock()
    private var target: Target = .unlocked
    private var timer: DispatchSourceTimer?
    private var _warpsRecovered = 0

    /// Watchdog recoveries so far — surfaced to InputMetrics (R24).
    public var warpsRecovered: Int { lock.withLock { _warpsRecovered } }

    public init(
        effects: SentinelEffects,
        policy: SentinelPolicy = SentinelPolicy(),
        interval: TimeInterval = 0.25
    ) {
        self.effects = effects
        self.policy = policy
        self.interval = interval
    }

    /// Freezes the arrow at `park`: warp there, dissociate the physical mouse,
    /// signal the conceal layer, and start the watchdog. Re-callable to update
    /// the park point (e.g. after a display-topology change on reassert).
    public func engage(park: CGPoint) {
        lock.withLock {
            let wasLocked = target.isLocked
            target = .locked(park: park)
            effects.warp(park)
            effects.setDissociated(true)
            effects.onLock()
            if !wasLocked { startTimerLocked() }
        }
    }

    /// Restores normal cursor control. Always safe — no-op when already
    /// unlocked, never leaves the machine pinned behind a dead link.
    public func release() {
        lock.withLock {
            guard target.isLocked else { return }
            target = .unlocked
            stopTimerLocked()
            effects.setDissociated(false)
            effects.onUnlock()
        }
    }

    /// Re-applies the lock after a system transition (R19) — the dissociation
    /// and hide may have lapsed on wake. No-op when unlocked.
    public func reassert() {
        lock.withLock {
            guard case let .locked(park) = target else { return }
            effects.warp(park)
            effects.setDissociated(true)
            effects.onLock()
        }
    }

    /// One watchdog step (also the timer body). Exposed for deterministic tests.
    public func tick() {
        lock.withLock {
            guard case let .locked(park) = target else { return }
            if policy.needsRecovery(location: effects.location(), park: park) {
                effects.warp(park)
                effects.setDissociated(true)
                _warpsRecovered += 1
            }
        }
    }

    // MARK: - Timer (caller holds `lock`)

    private func startTimerLocked() {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + interval, repeating: interval)
        t.setEventHandler { [weak self] in self?.tick() }
        timer = t
        t.resume()
    }

    private func stopTimerLocked() {
        timer?.cancel()
        timer = nil
    }
}

private extension CursorSentinel.Target {
    var isLocked: Bool {
        if case .locked = self { return true }
        return false
    }
}

/// Side effects behind `CursorSentinel`, injected for testability. `onLock` /
/// `onUnlock` let the owning session drive the conceal layer (gated by the
/// `concealCursor` config) without the sentinel knowing about it.
public struct SentinelEffects: Sendable {
    public let warp: @Sendable (CGPoint) -> Void
    public let setDissociated: @Sendable (Bool) -> Void
    public let location: @Sendable () -> CGPoint
    public let onLock: @Sendable () -> Void
    public let onUnlock: @Sendable () -> Void

    public init(
        warp: @escaping @Sendable (CGPoint) -> Void,
        setDissociated: @escaping @Sendable (Bool) -> Void,
        location: @escaping @Sendable () -> CGPoint,
        onLock: @escaping @Sendable () -> Void = {},
        onUnlock: @escaping @Sendable () -> Void = {}
    ) {
        self.warp = warp
        self.setDissociated = setDissociated
        self.location = location
        self.onLock = onLock
        self.onUnlock = onUnlock
    }

    /// Live effects: real CoreGraphics warp/dissociation and cursor read.
    public static func live(
        onLock: @escaping @Sendable () -> Void = {},
        onUnlock: @escaping @Sendable () -> Void = {}
    ) -> SentinelEffects {
        SentinelEffects(
            warp: { CGWarpMouseCursorPosition($0) },
            setDissociated: { CGAssociateMouseAndMouseCursorPosition($0 ? 0 : 1) },
            location: { CGEvent(source: nil)?.location ?? .zero },
            onLock: onLock,
            onUnlock: onUnlock
        )
    }
}
