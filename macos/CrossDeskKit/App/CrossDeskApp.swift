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

/// Logs every app shutdown path (Sair, ⌘Q, Dock quit, System shutdown/logout,
/// `relaunch()`) so a UAT report of "the app just closed" is diagnosable from
/// `log show` alone instead of only from whichever call site remembered to
/// log first. Debugging aid only — no cleanup logic belongs here (`stop()`
/// already tears down sessions on the explicit quit/relaunch paths).
final class AppTerminationLogger: NSObject, NSApplicationDelegate {
    func applicationWillTerminate(_ notification: Notification) {
        Log.app.info("applicationWillTerminate — process exiting")
    }
}
