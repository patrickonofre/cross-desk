import AppKit

/// Seam over NSPasteboard so the watcher and coordinator are testable without
/// touching the real (global, shared) pasteboard.
public protocol PasteboardFacade: Sendable {
    var changeCount: Int { get }
    func readFileURLs() -> [URL]
    /// True when the board carries our private marker type — i.e. WE wrote it.
    func hasOwnMarker() -> Bool
    /// Writes file URLs plus the marker type (anti-loop, design D2.3).
    func writeFileURLs(_ urls: [URL])
}

/// NSPasteboard.general adapter. The read path only ever looks at
/// `types`/`changeCount` cheaply; file contents are never read here.
public struct SystemPasteboard: PasteboardFacade {
    public static let markerType = NSPasteboard.PasteboardType("dev.crossdesk.transfer-id")

    public init() {}

    public var changeCount: Int { NSPasteboard.general.changeCount }

    public func readFileURLs() -> [URL] {
        let board = NSPasteboard.general
        guard board.types?.contains(.fileURL) == true else { return [] }
        let objects = board.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        )
        return (objects as? [URL]) ?? []
    }

    public func hasOwnMarker() -> Bool {
        NSPasteboard.general.types?.contains(Self.markerType) == true
    }

    public func writeFileURLs(_ urls: [URL]) {
        let board = NSPasteboard.general
        board.clearContents()
        board.writeObjects(urls as [NSURL])
        board.setString("crossdesk", forType: Self.markerType)
    }
}

/// Polls the pasteboard for newly copied files (design D2.1): changeCount at
/// 0.5 s — never the contents. Own writes are filtered by the marker type,
/// otherwise the two machines would announce each other's clipboards forever
/// (anti-loop, D2.3).
public final class PasteboardWatcher: @unchecked Sendable {
    private let pasteboard: PasteboardFacade
    private let queue: DispatchQueue
    private let interval: TimeInterval
    private var timer: DispatchSourceTimer?
    private var lastChangeCount: Int

    /// Fired on the watcher queue with the copied file URLs.
    public var onFilesCopied: (@Sendable ([URL]) -> Void)?

    public init(
        pasteboard: PasteboardFacade = SystemPasteboard(),
        queue: DispatchQueue = DispatchQueue(label: "crossdesk.pasteboard.watcher"),
        interval: TimeInterval = 0.5
    ) {
        self.pasteboard = pasteboard
        self.queue = queue
        self.interval = interval
        // Whatever is on the board when we start is history, not a new copy.
        self.lastChangeCount = pasteboard.changeCount
    }

    public func start() {
        queue.async { [self] in
            guard timer == nil else { return }
            let source = DispatchSource.makeTimerSource(queue: queue)
            source.schedule(deadline: .now() + interval, repeating: interval)
            source.setEventHandler { [weak self] in self?.checkNow() }
            source.resume()
            timer = source
        }
    }

    public func stop() {
        queue.async { [self] in
            timer?.cancel()
            timer = nil
        }
    }

    /// One poll tick — internal so tests can tick without timer waits.
    func checkNow() {
        let count = pasteboard.changeCount
        guard count != lastChangeCount else { return }
        lastChangeCount = count
        guard !pasteboard.hasOwnMarker() else { return } // our own write (D2.3)
        let urls = pasteboard.readFileURLs()
        guard !urls.isEmpty else { return }
        onFilesCopied?(urls)
    }
}
