import Carbon

/// Global system-wide hotkey via Carbon's `RegisterEventHotKey` — the only
/// public macOS API for this that doesn't require Accessibility permission
/// (verified 2026-07-06 for debug-console R43). `NSEvent.addGlobalMonitorForEvents`
/// would force the server role to request Accessibility just for this debug
/// shortcut, breaking the per-role permission model in PROJECT.md. Single fixed
/// combo — no multi-hotkey registry, unlike general-purpose hotkey libraries.
@MainActor
public enum DebugHotKey {
    private static var eventHandler: EventHandlerRef?
    private static var hotKeyRef: EventHotKeyRef?
    private static var onPress: (() -> Void)?

    /// Cmd+Shift+\ by default (debug-console R43's combo — moved off Cmd+Shift+\
    /// 2026-07-07, which collided with dev-tool shortcuts).
    public static func register(
        keyCode: UInt32 = UInt32(kVK_ANSI_Backslash),
        modifiers: UInt32 = UInt32(cmdKey | shiftKey),
        onPress: @escaping () -> Void
    ) {
        guard hotKeyRef == nil else { return }
        Self.onPress = onPress

        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetEventDispatcherTarget(), debugHotKeyEventHandler, 1, &eventSpec, nil, &eventHandler)

        let hotKeyID = EventHotKeyID(signature: fourCharCode("CrDb"), id: 1)
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetEventDispatcherTarget(), 0, &hotKeyRef)
        // Silent by default (like every other outcome of this hidden shortcut —
        // R45), but a failure here means the combo is already claimed by
        // another app (Rectangle/Alfred/Karabiner/BTT...) and Cmd+Shift+\ will
        // never fire; log so that failure mode isn't undiagnosable.
        if status != noErr {
            Log.app.error("debug hotkey registration FAILED (OSStatus \(status, privacy: .public)) — Cmd+Shift+\\ likely already claimed by another app")
        }
    }

    fileprivate static func fire() {
        onPress?()
    }

    private static func fourCharCode(_ string: String) -> FourCharCode {
        string.utf16.reduce(0) { ($0 << 8) + FourCharCode($1) }
    }
}

/// Carbon delivers `kEventHotKeyPressed` on the main run loop — `assumeIsolated`
/// asserts that instead of hopping async, matching the synchronous, immediate
/// dispatch every other global-hotkey implementation of this API relies on.
private func debugHotKeyEventHandler(_ call: EventHandlerCallRef?, _ event: EventRef?, _ userData: UnsafeMutableRawPointer?) -> OSStatus {
    MainActor.assumeIsolated {
        DebugHotKey.fire()
    }
    return noErr
}
