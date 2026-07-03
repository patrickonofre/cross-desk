import SwiftUI
import CrossDeskKit

@main
struct CrossDeskApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
        } label: {
            Image(systemName: appState.running ? "display.2.fill" : "display.2")
        }
        .menuBarExtraStyle(.window)
    }
}
