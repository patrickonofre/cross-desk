import SwiftUI
import CrossDeskKit

@main
struct CrossDeskApp: App {
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
    }

    var body: some Scene {
        MenuBarExtra(isInserted: $menuBarInserted) {
            MenuBarView()
                .environmentObject(appState)
        } label: {
            Image(systemName: appState.running ? "display.2.fill" : "display.2")
        }
        .menuBarExtraStyle(.window)
        .onChange(of: menuBarInserted) {
            if !menuBarInserted {
                Log.app.info("menubar: status item removed by system/user — re-inserting")
                menuBarInserted = true
            }
        }
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
