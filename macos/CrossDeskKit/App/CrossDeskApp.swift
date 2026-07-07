import SwiftUI
import CrossDeskKit

@main
struct CrossDeskApp: App {
    @NSApplicationDelegateAdaptor(AppTerminationLogger.self) private var terminationLogger
    @StateObject private var appState = AppState()
    // The menu bar icon is this app's ONLY UI (LSUIElement — no Dock, no
    // windows). macOS lets the user drag status items off the bar (⌘-drag,
    // or plain drag on newer releases) and persists the removal in
    // "NSStatusItem Visible Item-0" — the app then keeps running with no way
    // to reach it, ever, even across relaunches. Pin the item: heal the
    // persisted flag before the scene materializes and snap the binding back
    // if the system flips it mid-session.
    @State private var menuBarInserted = true

    init() {
        Self.healStatusItemVisibility()
        // A windowless, backgrounded LSUIElement app is exactly what AppKit's
        // Automatic Termination targets for a silent reap (confirmed live via
        // `com.apple.AppKit:AutomaticTermination` in the unified log while
        // testing debug-console below — no Sair, no ⌘Q, the OS just asked
        // applicationShouldTerminate: and got the default NSTerminateNow).
        // This app has no "done, nothing to do" state — it's a server/client
        // relay — so it must never be an auto-termination candidate.
        ProcessInfo.processInfo.disableAutomaticTermination("CrossDesk runs as a background menu bar relay")
        // Hidden debug console (debug-console R43) — no menu entry, see
        // DebugConsoleWindow.swift. Cmd+Shift+D, works regardless of role or
        // TCC state (RegisterEventHotKey needs no permission).
        DebugHotKey.register {
            DebugConsoleWindowController.shared.toggle()
        }
    }

    var body: some Scene {
        MenuBarExtra(isInserted: $menuBarInserted) {
            MenuBarView()
                .environmentObject(appState)
        } label: {
            // R41: the icon tells where the input goes even with the panel
            // closed (cursor-with-motion-lines while controlling the peer).
            Image(systemName: appState.menuBarSymbol)
                .symbolVariant(appState.menuBarSymbolFilled ? .fill : .none)
        }
        .menuBarExtraStyle(.window)
        .onChange(of: menuBarInserted) {
            if !menuBarInserted {
                Log.app.info("menubar: status item removed by system/user — re-inserting")
                menuBarInserted = true
            }
        }
        .commands {
            // SwiftUI wires a default "Quit CrossDesk" command (⌘Q key
            // equivalent) even for an LSUIElement app with no visible menu
            // bar — it bypasses MenuBarView's "Sair" button entirely, so it
            // never logs (confirmed live: a UAT session closed with a clean
            // `terminate:` while focusing the pairing-token TextField, but
            // neither "quit requested via Sair button" nor "relaunch
            // requested" appeared beforehand). The "Sair" button is the only
            // intended way to quit this relay — replace the default with
            // nothing so a stray ⌘Q can't silently kill an in-progress
            // pairing/session.
            CommandGroup(replacing: .appTermination) {}
        }

        // Desk editor (layout-ux R36). LSUIElement stays: the window only
        // exists while the user keeps it open.
        Window("Telas", id: "desk") {
            DeskWindowView()
                .environmentObject(appState)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 600, height: 460)
    }

    private static func healStatusItemVisibility() {
        let defaults = UserDefaults.standard
        let domain = Bundle.main.bundleIdentifier
            .flatMap { defaults.persistentDomain(forName: $0) } ?? [:]
        for (key, value) in domain
        where key.hasPrefix("NSStatusItem Visible") && (value as? Bool) == false {
            defaults.set(true, forKey: key)
            Log.app.info("menubar: healed persisted removal (\(key, privacy: .public) was false)")
        }
    }
}

/// Gatekeeper for every app shutdown path. This is a background relay with
/// no "done, nothing to do" state — it must NEVER quit except through the two
/// deliberate call sites ("Sair" in MenuBarView, `AppState.relaunch()`), both
/// of which set `deliberateQuitRequested` immediately before calling
/// `terminate()`. Everything else that reaches `applicationShouldTerminate`
/// gets cancelled, including:
/// - SwiftUI's default ⌘Q "Quit" command (also stripped in `CrossDeskApp`'s
///   `.commands`, but that only removes the menu item — this is the actual
///   enforcement point).
/// - A confirmed SwiftUI Scene bug (Apple FB11447959, reproduced live in the
///   2026-07-07 UAT: clicking the menu bar icon to collapse the popover
///   terminated the whole app) where an app combining `Window` +
///   `MenuBarExtra` can have AppKit decide "no scenes left" and call
///   `terminate()` directly — with neither of our own call sites involved,
///   so it never used to log anything either.
/// `applicationWillTerminate` still logs so a legitimate quit is
/// diagnosable from `log show` alone. Debugging aid only — no cleanup logic
/// belongs here (`stop()` already tears down sessions on the explicit
/// quit/relaunch paths).
final class AppTerminationLogger: NSObject, NSApplicationDelegate {
    /// Set immediately before the ONLY two deliberate quit paths call
    /// `terminate()`. Read (and reset) once by `applicationShouldTerminate`.
    @MainActor static var deliberateQuitRequested = false

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard Self.deliberateQuitRequested else {
            Log.app.error("applicationShouldTerminate blocked — not a deliberate quit (neither Sair nor relaunch requested it); likely the SwiftUI Window+MenuBarExtra scene bug (FB11447959)")
            return .terminateCancel
        }
        Self.deliberateQuitRequested = false
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        Log.app.info("applicationWillTerminate — process exiting")
    }
}
