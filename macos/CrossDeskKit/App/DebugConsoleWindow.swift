import SwiftUI
import CrossDeskKit

/// Publishes `DebugLogBuffer` updates to SwiftUI (debug-console R44) — the
/// library target keeps its usual callback-over-queue style; this is the
/// `@MainActor`/`@Published` bridge, same role `AppState` plays for the rest
/// of the app's session callbacks.
@MainActor
final class DebugConsoleViewModel: ObservableObject {
    @Published var lines: [String] = []

    private let buffer = DebugLogBuffer()
    private lazy var streamer = LogStreamer(buffer: buffer)
    private var started = false

    init() {
        buffer.onUpdate = { [weak self] snapshot in
            Task { @MainActor in self?.lines = snapshot }
        }
    }

    func start() {
        guard !started else { return }
        started = true
        streamer.start()
    }

    func stop() {
        guard started else { return }
        started = false
        streamer.stop()
    }

    func clear() {
        buffer.clear()
    }

    func copyAll() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
    }
}

/// Debug console UI (debug-console R44/R48/R49) — plain list of live log lines,
/// a substring filter, clear and copy-all.
struct DebugConsoleView: View {
    @ObservedObject var viewModel: DebugConsoleViewModel
    @State private var filter = ""

    private var filteredLines: [String] {
        guard !filter.isEmpty else { return viewModel.lines }
        return viewModel.lines.filter { $0.localizedCaseInsensitiveContains(filter) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Filtrar…", text: $filter)
                    .textFieldStyle(.roundedBorder)
                Button("Limpar") { viewModel.clear() }
                Button("Copiar tudo") { viewModel.copyAll() }
                    .disabled(viewModel.lines.isEmpty)
            }
            .padding(8)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(filteredLines.enumerated()), id: \.offset) { index, line in
                            Text(line)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .id(index)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                }
                .onChange(of: filteredLines.count) {
                    if let last = filteredLines.indices.last {
                        proxy.scrollTo(last, anchor: .bottom)
                    }
                }
            }
        }
        .frame(minWidth: 600, minHeight: 300)
    }
}

/// Hosts the hidden debug console (debug-console R43–R48) — no menu entry,
/// reachable only via the global Cmd+Shift+D hotkey registered in
/// `CrossDeskApp.init`.
@MainActor
final class DebugConsoleWindowController: NSObject, NSWindowDelegate {
    static let shared = DebugConsoleWindowController()

    private let viewModel = DebugConsoleViewModel()
    private var window: NSWindow?

    func toggle() {
        if let window, window.isVisible {
            window.close()
        } else {
            show()
        }
    }

    private func show() {
        let win = window ?? makeWindow()
        window = win
        viewModel.start()
        win.center()
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeWindow() -> NSWindow {
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 420),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        win.title = "CrossDesk Debug"
        win.level = .floating
        win.isReleasedWhenClosed = false
        win.delegate = self
        win.contentView = NSHostingView(rootView: DebugConsoleView(viewModel: viewModel))
        return win
    }

    func windowWillClose(_ notification: Notification) {
        viewModel.stop()
    }
}
