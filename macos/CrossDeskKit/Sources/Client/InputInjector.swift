import Foundation
import CoreGraphics

/// Applies remote input messages to the local machine via CGEventPost (R6).
/// Requires the Accessibility TCC permission.
///
/// Owns the client-side cursor position (clamped to the local screen), click
/// counting for double-clicks, modifier flags, and the pressed-key registry
/// used for synthetic releases (R7).
public final class InputInjector: @unchecked Sendable {
    private let source = CGEventSource(stateID: .hidSystemState)
    private let screen: () -> CGRect

    private var position = CGPoint.zero
    private var pressedKeys = PressedKeys()
    private var heldButtons: Set<UInt8> = []
    private var flags: CGEventFlags = []
    // Double-click synthesis: consecutive same-button downs close in time/space.
    private var lastClickTime: TimeInterval = 0
    private var lastClickButton: UInt8 = 0
    private var lastClickPosition = CGPoint.zero
    private var clickCount: Int64 = 1
    // Scroll lines arrive as Float; CGEvent wants integer lines — carry remainders.
    private var scrollRemainderX = 0.0
    private var scrollRemainderY = 0.0

    /// True when the post-event (Accessibility) permission is granted.
    public static func hasPermission() -> Bool {
        CGPreflightPostEventAccess()
    }

    @discardableResult
    public static func requestPermission() -> Bool {
        CGRequestPostEventAccess()
    }

    /// `screen` supplies the local main-display bounds (CG global coordinates);
    /// injected as a closure for testability and display reconfiguration.
    public init(screen: @escaping @Sendable () -> CGRect = {
        CGDisplayBounds(CGMainDisplayID())
    }) {
        self.screen = screen
    }

    // MARK: - Message application

    public func apply(_ message: Message) {
        switch message {
        case let .enter(x, y):
            let bounds = screen()
            position = CGPoint(
                x: bounds.minX + CGFloat(x) * bounds.width,
                y: bounds.minY + CGFloat(y) * bounds.height
            )
            postMouseMove()
        case .leave:
            releaseEverything()
        case let .mouseMove(dx, dy):
            let bounds = screen()
            position.x = min(max(position.x + CGFloat(dx), bounds.minX), bounds.maxX - 1)
            position.y = min(max(position.y + CGFloat(dy), bounds.minY), bounds.maxY - 1)
            postMouseMove()
        case let .mouseButton(button, pressed):
            postMouseButton(button: button, isDown: pressed)
        case let .scroll(dx, dy):
            postScroll(dx: Double(dx), dy: Double(dy))
        case let .key(hidUsage, pressed):
            postKey(hidUsage: hidUsage, isDown: pressed)
        case .hello, .helloAck, .heartbeat, .bye:
            break // transport-level, never reaches the injector
        }
    }

    /// Synthetic key-up for everything still held (LEAVE/disconnect — R7).
    public func releaseEverything() {
        for usage in pressedKeys.drainReleases() {
            if let keycode = HIDKeycodes.macKeycode(forHIDUsage: usage) {
                post(keyCode: keycode, isDown: false)
            }
        }
        for button in heldButtons {
            postMouseButton(button: button, isDown: false)
        }
        heldButtons.removeAll()
        flags = []
    }

    // MARK: - Posting

    private func postMouseMove() {
        let type: CGEventType = if heldButtons.contains(1) {
            .leftMouseDragged
        } else if heldButtons.contains(2) {
            .rightMouseDragged
        } else if !heldButtons.isEmpty {
            .otherMouseDragged
        } else {
            .mouseMoved
        }
        let event = CGEvent(
            mouseEventSource: source, mouseType: type,
            mouseCursorPosition: position, mouseButton: cgButton(for: currentDragButton())
        )
        event?.flags = flags
        event?.post(tap: .cghidEventTap)
    }

    private func postMouseButton(button: UInt8, isDown: Bool) {
        let now = ProcessInfo.processInfo.systemUptime
        if isDown {
            let isDoubleClick = button == lastClickButton
                && (now - lastClickTime) < 0.5
                && abs(position.x - lastClickPosition.x) < 5
                && abs(position.y - lastClickPosition.y) < 5
            clickCount = isDoubleClick ? clickCount + 1 : 1
            lastClickTime = now
            lastClickButton = button
            lastClickPosition = position
            heldButtons.insert(button)
        } else {
            heldButtons.remove(button)
        }

        let type: CGEventType = switch (button, isDown) {
        case (1, true): .leftMouseDown
        case (1, false): .leftMouseUp
        case (2, true): .rightMouseDown
        case (2, false): .rightMouseUp
        case (_, true): .otherMouseDown
        case (_, false): .otherMouseUp
        }
        let event = CGEvent(
            mouseEventSource: source, mouseType: type,
            mouseCursorPosition: position, mouseButton: cgButton(for: button)
        )
        event?.setIntegerValueField(.mouseEventClickState, value: clickCount)
        event?.flags = flags
        event?.post(tap: .cghidEventTap)
    }

    private func postScroll(dx: Double, dy: Double) {
        scrollRemainderX += dx
        scrollRemainderY += dy
        let linesX = Int32(scrollRemainderX)
        let linesY = Int32(scrollRemainderY)
        scrollRemainderX -= Double(linesX)
        scrollRemainderY -= Double(linesY)
        guard linesX != 0 || linesY != 0 else { return }

        let event = CGEvent(
            scrollWheelEvent2Source: source, units: .line,
            wheelCount: 2, wheel1: linesY, wheel2: linesX, wheel3: 0
        )
        event?.flags = flags
        event?.post(tap: .cghidEventTap)
    }

    private func postKey(hidUsage: UInt16, isDown: Bool) {
        guard let keycode = HIDKeycodes.macKeycode(forHIDUsage: hidUsage) else { return }
        pressedKeys.handle(hidUsage: hidUsage, isDown: isDown)
        updateFlags(hidUsage: hidUsage, isDown: isDown)
        post(keyCode: keycode, isDown: isDown)
    }

    private func post(keyCode: UInt16, isDown: Bool) {
        let event = CGEvent(
            keyboardEventSource: source, virtualKey: CGKeyCode(keyCode), keyDown: isDown
        )
        // Synthesized events carry their own modifier state; without this,
        // ⌘C arrives as a bare C.
        event?.flags = flags
        event?.post(tap: .cghidEventTap)
    }

    /// Keeps CGEventFlags in sync with which modifiers are held remotely.
    private func updateFlags(hidUsage: UInt16, isDown: Bool) {
        guard let keycode = HIDKeycodes.macKeycode(forHIDUsage: hidUsage),
              let mask = InputCapture.modifierMask(forMacKeycode: keycode) else { return }
        // Both sides of a pair (e.g. left/right shift) share one mask bit; only
        // clear it when neither side remains pressed.
        if isDown {
            flags.insert(mask)
        } else {
            let pairStillHeld = pressedKeys.currentlyPressed.contains { usage in
                HIDKeycodes.macKeycode(forHIDUsage: usage)
                    .flatMap(InputCapture.modifierMask(forMacKeycode:)) == mask
            }
            if !pairStillHeld {
                flags.remove(mask)
            }
        }
    }

    private func currentDragButton() -> UInt8 {
        heldButtons.min() ?? 1
    }

    private func cgButton(for button: UInt8) -> CGMouseButton {
        switch button {
        case 1: .left
        case 2: .right
        default: .center
        }
    }
}
