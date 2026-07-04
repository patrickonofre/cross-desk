import Foundation
import CoreGraphics

/// Global cursor hide/show for a background (non-focused) process (R17).
///
/// Uses the undocumented `SetsCursorInBackground` WindowServer flag plus
/// `CGDisplayHideCursor` — the same technique Deskflow/Barrier have shipped for
/// a decade, and the only way to hide the cursor from an app that is not
/// frontmost (confirmed by Apple DTS, forums thread 756199). The private
/// symbols are resolved via `dlsym` and never linked; if they ever disappear
/// the concealer reports `isAvailable == false` and every call is a logged
/// no-op — callers degrade to a visible-but-parked cursor (spike T19: warping
/// off-screen clamps back, so there is no private-API-free hide).
///
/// Known limitation: the WindowServer reclaims the cursor when the Dock is the
/// active cursor target — accepted and documented (spec.md, out of scope).
///
/// Hide/show are idempotent and balanced against the system's hide counter:
/// the concealer only calls into CG on an actual state transition, keeping the
/// counter at 0 or 1 regardless of how often the session toggles.
public final class CursorConcealer: @unchecked Sendable {
    private let backend: CursorConcealBackend
    private let lock = NSLock()
    private var hidden = false

    public init(backend: CursorConcealBackend = .live) {
        self.backend = backend
    }

    /// True when the private symbols resolved — hiding will actually take effect.
    public var isAvailable: Bool { backend.isAvailable }

    /// Hides the cursor globally. Idempotent; no-op (logged once) when the
    /// private API is unavailable.
    public func hide() {
        lock.lock(); defer { lock.unlock() }
        guard backend.isAvailable else {
            Log.session.info("concealer: hide requested but private API unavailable — no-op")
            return
        }
        guard !hidden else { return }
        hidden = true
        backend.setBackgroundFlag(true)
        backend.hide()
        Log.session.info("concealer: cursor hidden")
    }

    /// Shows the cursor globally. Idempotent and always safe to call — the
    /// unlock path invokes it unconditionally to undo any hide.
    public func show() {
        lock.lock(); defer { lock.unlock() }
        guard hidden else { return }
        hidden = false
        backend.show()
        backend.setBackgroundFlag(false)
        Log.session.info("concealer: cursor shown")
    }

    /// Re-applies the current target state (R19). After a wake/screensaver the
    /// WindowServer may have dropped the hidden state; if we believe the cursor
    /// should be hidden, force the CG calls again without disturbing the counter.
    public func reassert() {
        lock.lock(); defer { lock.unlock() }
        guard hidden, backend.isAvailable else { return }
        backend.setBackgroundFlag(true)
        backend.hide()
        Log.session.info("concealer: re-hidden after system transition")
    }
}

/// CG/WindowServer side effects behind `CursorConcealer`, injectable for tests.
public struct CursorConcealBackend: Sendable {
    public let isAvailable: Bool
    public let setBackgroundFlag: @Sendable (Bool) -> Void
    public let hide: @Sendable () -> Void
    public let show: @Sendable () -> Void

    public init(
        isAvailable: Bool,
        setBackgroundFlag: @escaping @Sendable (Bool) -> Void,
        hide: @escaping @Sendable () -> Void,
        show: @escaping @Sendable () -> Void
    ) {
        self.isAvailable = isAvailable
        self.setBackgroundFlag = setBackgroundFlag
        self.hide = hide
        self.show = show
    }

    /// Real backend: resolves the private symbols once and drives CoreGraphics.
    public static let live: CursorConcealBackend = {
        guard let api = PrivateCursorSymbols() else {
            return CursorConcealBackend(
                isAvailable: false,
                setBackgroundFlag: { _ in }, hide: {}, show: {}
            )
        }
        return CursorConcealBackend(
            isAvailable: true,
            setBackgroundFlag: { enabled in api.setCursorInBackground(enabled) },
            hide: { CGDisplayHideCursor(CGMainDisplayID()) },
            show: { CGDisplayShowCursor(CGMainDisplayID()) }
        )
    }()
}

/// Dynamically resolved WindowServer cursor symbols (never linked). Proven on
/// macOS 26 by the T19 spike.
private struct PrivateCursorSymbols {
    typealias DefaultConnectionFn = @convention(c) () -> Int32
    typealias SetConnectionPropertyFn =
        @convention(c) (Int32, Int32, CFString, CFTypeRef) -> Int32

    let defaultConnection: DefaultConnectionFn
    let setConnectionProperty: SetConnectionPropertyFn

    init?() {
        guard let cn = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "_CGSDefaultConnection"),
              let sp = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGSSetConnectionProperty")
        else {
            Log.session.error("concealer: private cursor symbols not found via dlsym")
            return nil
        }
        defaultConnection = unsafeBitCast(cn, to: DefaultConnectionFn.self)
        setConnectionProperty = unsafeBitCast(sp, to: SetConnectionPropertyFn.self)
    }

    func setCursorInBackground(_ enabled: Bool) {
        let cid = defaultConnection()
        let key = "SetsCursorInBackground" as CFString
        _ = setConnectionProperty(cid, cid, key, enabled ? kCFBooleanTrue : kCFBooleanFalse)
    }
}
