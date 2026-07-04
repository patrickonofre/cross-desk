import Foundation
import CoreGraphics
import AppKit

// T19 — Spike: cursor concealment + lock resilience on macOS 26.
//
// Answers three design uncertainties for input-polish (R17/R18):
//   1. Does the private SetsCursorInBackground + CGDisplayHideCursor trick still
//      hide the cursor from a background (non-focused) process?
//   2. Does CGWarpMouseCursorPosition to a point outside all displays clamp back
//      inside, or move off-screen (fallback concealment without private API)?
//   3. Does CGAssociateMouseAndMouseCursorPosition(0) survive a display sleep?
//
// Run measurable parts:   swift run conceal-spike
// Sleep-survival probe:    swift run conceal-spike --sleep-test   (blanks display!)

// MARK: - Private WindowServer symbols, resolved dynamically (never linked).

typealias CGSDefaultConnectionFn = @convention(c) () -> Int32
typealias CGSSetConnectionPropertyFn =
    @convention(c) (Int32, Int32, CFString, CFTypeRef) -> Int32

struct PrivateCursorAPI {
    let defaultConnection: CGSDefaultConnectionFn
    let setConnectionProperty: CGSSetConnectionPropertyFn

    init?() {
        guard let cn = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "_CGSDefaultConnection"),
              let sp = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGSSetConnectionProperty")
        else { return nil }
        defaultConnection = unsafeBitCast(cn, to: CGSDefaultConnectionFn.self)
        setConnectionProperty = unsafeBitCast(sp, to: CGSSetConnectionPropertyFn.self)
    }

    /// Sets the undocumented "SetsCursorInBackground" flag so CGDisplayHideCursor
    /// works while this process is not frontmost (Deskflow/Barrier technique).
    func setCursorInBackground(_ enabled: Bool) -> Int32 {
        let cid = defaultConnection()
        let key = "SetsCursorInBackground" as CFString
        return setConnectionProperty(cid, cid, key, enabled ? kCFBooleanTrue : kCFBooleanFalse)
    }
}

func cursorLocation() -> CGPoint {
    CGEvent(source: nil)?.location ?? .zero
}

func displayBounds() -> [CGRect] {
    var count: UInt32 = 0
    CGGetActiveDisplayList(0, nil, &count)
    var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
    CGGetActiveDisplayList(count, &ids, &count)
    return ids.map(CGDisplayBounds)
}

// MARK: - Experiments

func experimentDlsym() -> PrivateCursorAPI? {
    print("── EXP 1: private symbol resolution")
    guard let api = PrivateCursorAPI() else {
        print("   dlsym FAILED — _CGSDefaultConnection / CGSSetConnectionProperty gone.")
        print("   → R17 hide unavailable on this OS; fall back to park-visible.")
        return nil
    }
    print("   dlsym OK — connection id = \(api.defaultConnection())")
    return api
}

func experimentHide(_ api: PrivateCursorAPI) {
    print("── EXP 2: background hide (SetsCursorInBackground + CGDisplayHideCursor)")
    let setErr = api.setCursorInBackground(true)
    let hideErr = CGDisplayHideCursor(CGMainDisplayID())
    print("   CGSSetConnectionProperty -> \(setErr) (0 == success)")
    print("   CGDisplayHideCursor      -> \(hideErr.rawValue) (0 == success)")
    print("   VISUAL CHECK: cursor should now be hidden for ~4 s even unfocused.")
    print("   (Dock as active cursor target may reclaim it — documented limit.)")
    Thread.sleep(forTimeInterval: 4)
    CGDisplayShowCursor(CGMainDisplayID())
    _ = api.setCursorInBackground(false)
    print("   restored (CGDisplayShowCursor).")
}

func experimentWarpOffscreen() {
    print("── EXP 3: warp offscreen (private-API-free concealment fallback)")
    let before = cursorLocation()
    let union = displayBounds().reduce(CGRect.null) { $0.union($1) }
    let target = CGPoint(x: union.maxX + 5000, y: union.maxY + 5000)
    CGWarpMouseCursorPosition(target)
    // Warp does not emit an event; read back the actual landing spot.
    Thread.sleep(forTimeInterval: 0.05)
    let after = cursorLocation()
    print("   union = \(union)")
    print("   warped to \(target), landed at \(after)")
    if union.contains(after) {
        print("   → CLAMPED inside displays. Warp-offscreen NOT viable as hide.")
    } else {
        print("   → LANDED OUTSIDE. Warp-offscreen viable as a no-private-API hide.")
    }
    CGWarpMouseCursorPosition(before) // restore
}

func experimentSleepSurvival() {
    print("── EXP 4: dissociation survival across display sleep")
    print("   associating(0) then forcing display sleep in 2 s…")
    CGAssociateMouseAndMouseCursorPosition(0)
    Thread.sleep(forTimeInterval: 2)
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
    task.arguments = ["displaysleepnow"]
    try? task.run()
    task.waitUntilExit()
    print("   display asleep. Move the physical mouse to wake, then observe:")
    print("   does the arrow move freely (dissociation LOST) or stay pinned?")
    print("   watching cursor position for 20 s (move mouse now)…")
    let start = cursorLocation()
    var maxDrift = 0.0
    let deadline = Date().addingTimeInterval(20)
    while Date() < deadline {
        let p = cursorLocation()
        maxDrift = max(maxDrift, hypot(p.x - start.x, p.y - start.y))
        Thread.sleep(forTimeInterval: 0.1)
    }
    CGAssociateMouseAndMouseCursorPosition(1)
    print("   max drift after wake = \(String(format: "%.1f", maxDrift)) px")
    print(maxDrift > 20
        ? "   → dissociation LOST on wake — R19 reassert is REQUIRED."
        : "   → dissociation held (or mouse not moved). Re-run and move the mouse.")
}

// MARK: - Main

print("conceal-spike — macOS \(ProcessInfo.processInfo.operatingSystemVersionString)\n")
let api = experimentDlsym()
print("")
experimentWarpOffscreen()
print("")
if CommandLine.arguments.contains("--sleep-test") {
    experimentSleepSurvival()
} else if let api {
    experimentHide(api)
    print("\n(skipping EXP 4 — pass --sleep-test to probe sleep survival; it blanks the display.)")
} else {
    print("(private API unavailable; skipping hide experiment.)")
}
print("\ndone.")
