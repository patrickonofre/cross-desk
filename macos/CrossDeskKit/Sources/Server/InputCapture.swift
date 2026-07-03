import Foundation
import CoreGraphics

/// Normalized capture event handed to the session layer.
public enum CapturedEvent: Sendable {
    /// Deltas from kCGMouseEventDeltaX/Y (valid even with the cursor pinned)
    /// plus the current global location (CG coordinates, y-down).
    case mouseMoved(dx: Double, dy: Double, location: CGPoint)
    case mouseButton(button: UInt8, isDown: Bool)
    case scroll(dx: Double, dy: Double)
    /// macOS virtual keycode. Modifier transitions arrive here too (derived
    /// from flagsChanged).
    case key(macKeycode: UInt16, isDown: Bool)
}

public enum InputCaptureError: Error {
    /// Tap creation failed — almost always missing Input Monitoring permission.
    case tapCreationFailed
}

/// Global keyboard/mouse capture via CGEventTap (R1). Requires the Input
/// Monitoring TCC permission; with `suppressing == true` events are swallowed
/// (returned nil from the tap callback) after being forwarded to `onEvent`.
///
/// The tap runs on a dedicated thread with its own CFRunLoop.
public final class InputCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var _suppressing = false
    private var previousFlags: CGEventFlags = []
    private var tap: CFMachPort?
    private var runLoop: CFRunLoop?
    private var thread: Thread?

    /// Called synchronously on the tap thread — keep the handler cheap.
    public var onEvent: (@Sendable (CapturedEvent) -> Void)?

    public init() {}

    public var suppressing: Bool {
        get { lock.withLock { _suppressing } }
        set { lock.withLock { _suppressing = newValue } }
    }

    /// True when the Input Monitoring permission is already granted.
    public static func hasPermission() -> Bool {
        CGPreflightListenEventAccess()
    }

    /// Triggers the system permission prompt (first call only).
    @discardableResult
    public static func requestPermission() -> Bool {
        CGRequestListenEventAccess()
    }

    public func start() throws {
        let mask: CGEventMask =
            (1 << CGEventType.mouseMoved.rawValue) |
            (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.leftMouseUp.rawValue) |
            (1 << CGEventType.rightMouseDown.rawValue) |
            (1 << CGEventType.rightMouseUp.rawValue) |
            (1 << CGEventType.otherMouseDown.rawValue) |
            (1 << CGEventType.otherMouseUp.rawValue) |
            (1 << CGEventType.leftMouseDragged.rawValue) |
            (1 << CGEventType.rightMouseDragged.rawValue) |
            (1 << CGEventType.otherMouseDragged.rawValue) |
            (1 << CGEventType.scrollWheel.rawValue) |
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)

        let userInfo = Unmanaged.passRetained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                let capture = Unmanaged<InputCapture>
                    .fromOpaque(userInfo!)
                    .takeUnretainedValue()
                return capture.handle(type: type, event: event)
            },
            userInfo: userInfo
        ) else {
            Unmanaged<InputCapture>.fromOpaque(userInfo).release()
            throw InputCaptureError.tapCreationFailed
        }
        self.tap = tap

        let thread = Thread { [weak self] in
            guard let self, let tap = self.tap else { return }
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            self.runLoop = CFRunLoopGetCurrent()
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            CFRunLoopRun()
        }
        thread.name = "crossdesk.input-capture"
        thread.qualityOfService = .userInteractive
        self.thread = thread
        thread.start()
    }

    public func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let runLoop {
            CFRunLoopStop(runLoop)
        }
        if tap != nil {
            Unmanaged.passUnretained(self).release() // balances passRetained in start()
        }
        tap = nil
        runLoop = nil
        thread = nil
    }

    // MARK: - Tap callback (tap thread)

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // macOS silently disables slow taps; re-enable immediately (design.md).
            if let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        case .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            onEvent?(.mouseMoved(
                dx: event.getDoubleValueField(.mouseEventDeltaX),
                dy: event.getDoubleValueField(.mouseEventDeltaY),
                location: event.location
            ))
        case .leftMouseDown:
            onEvent?(.mouseButton(button: 1, isDown: true))
        case .leftMouseUp:
            onEvent?(.mouseButton(button: 1, isDown: false))
        case .rightMouseDown:
            onEvent?(.mouseButton(button: 2, isDown: true))
        case .rightMouseUp:
            onEvent?(.mouseButton(button: 2, isDown: false))
        case .otherMouseDown:
            onEvent?(.mouseButton(button: buttonNumber(event), isDown: true))
        case .otherMouseUp:
            onEvent?(.mouseButton(button: buttonNumber(event), isDown: false))
        case .scrollWheel:
            onEvent?(.scroll(
                dx: event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2),
                dy: event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
            ))
        case .keyDown, .keyUp:
            onEvent?(.key(
                macKeycode: UInt16(event.getIntegerValueField(.keyboardEventKeycode)),
                isDown: type == .keyDown
            ))
        case .flagsChanged:
            // Modifiers arrive as flag transitions; convert to key down/up by
            // comparing against the previous flag state.
            let keycode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            if let mask = Self.modifierMask(forMacKeycode: keycode) {
                let now = event.flags
                let wasDown = previousFlags.contains(mask)
                let isDown = now.contains(mask)
                previousFlags = now
                // Same-side/other-side modifiers share a mask bit; only emit
                // when the shared bit actually flipped.
                if wasDown != isDown {
                    onEvent?(.key(macKeycode: keycode, isDown: isDown))
                }
            } else {
                previousFlags = event.flags
            }
        default:
            break
        }

        return suppressing ? nil : Unmanaged.passUnretained(event)
    }

    private func buttonNumber(_ event: CGEvent) -> UInt8 {
        // CG button numbers: 0=left 1=right 2=middle...; wire: 1=left 2=right 3=middle
        UInt8(clamping: event.getIntegerValueField(.mouseEventButtonNumber) + 1)
    }

    static func modifierMask(forMacKeycode keycode: UInt16) -> CGEventFlags? {
        switch keycode {
        case 0x38, 0x3C: .maskShift
        case 0x3B, 0x3E: .maskControl
        case 0x3A, 0x3D: .maskAlternate
        case 0x37, 0x36: .maskCommand
        case 0x39: .maskAlphaShift // CapsLock
        default: nil
        }
    }
}

extension NSLock {
    fileprivate func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
