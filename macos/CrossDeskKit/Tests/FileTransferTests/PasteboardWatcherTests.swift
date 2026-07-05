import XCTest
@testable import CrossDeskKit

/// Thread-safe fake — tests drive changeCount by hand.
final class FakePasteboard: PasteboardFacade, @unchecked Sendable {
    private let lock = NSLock()
    private var _changeCount = 0
    private var _urls: [URL] = []
    private var _marker = false

    var changeCount: Int {
        lock.lock(); defer { lock.unlock() }
        return _changeCount
    }

    func readFileURLs() -> [URL] {
        lock.lock(); defer { lock.unlock() }
        return _urls
    }

    func hasOwnMarker() -> Bool {
        lock.lock(); defer { lock.unlock() }
        return _marker
    }

    func writeFileURLs(_ urls: [URL]) {
        lock.lock(); defer { lock.unlock() }
        _urls = urls
        _marker = true
        _changeCount += 1
    }

    /// External copy (Finder ⌘C): files land WITHOUT our marker.
    func simulateUserCopy(_ urls: [URL]) {
        lock.lock(); defer { lock.unlock() }
        _urls = urls
        _marker = false
        _changeCount += 1
    }

    /// Non-file clipboard change (plain text).
    func simulateTextCopy() {
        lock.lock(); defer { lock.unlock() }
        _urls = []
        _marker = false
        _changeCount += 1
    }
}

final class PasteboardWatcherTests: XCTestCase {

    private func makeWatcher(_ board: FakePasteboard) -> (PasteboardWatcher, () -> [[URL]]) {
        let watcher = PasteboardWatcher(pasteboard: board)
        nonisolated(unsafe) var fired: [[URL]] = []
        let lock = NSLock()
        watcher.onFilesCopied = { urls in
            lock.lock(); fired.append(urls); lock.unlock()
        }
        return (watcher, { lock.lock(); defer { lock.unlock() }; return fired })
    }

    func testUserCopyFires() {
        let board = FakePasteboard()
        let (watcher, fired) = makeWatcher(board)
        board.simulateUserCopy([URL(fileURLWithPath: "/tmp/a.txt")])
        watcher.checkNow()
        XCTAssertEqual(fired(), [[URL(fileURLWithPath: "/tmp/a.txt")]])
    }

    func testUnchangedBoardDoesNotFireTwice() {
        let board = FakePasteboard()
        let (watcher, fired) = makeWatcher(board)
        board.simulateUserCopy([URL(fileURLWithPath: "/tmp/a.txt")])
        watcher.checkNow()
        watcher.checkNow() // same changeCount — silent
        XCTAssertEqual(fired().count, 1)
    }

    func testOwnWriteNeverFires_antiLoop() {
        let board = FakePasteboard()
        let (watcher, fired) = makeWatcher(board)
        // What the coordinator does after receiving files (D2): write + marker.
        board.writeFileURLs([URL(fileURLWithPath: "/tmp/recebido.txt")])
        watcher.checkNow()
        XCTAssertEqual(fired(), [], "own write must not re-announce (announce echo loop)")
    }

    func testTextCopyDoesNotFire() {
        let board = FakePasteboard()
        let (watcher, fired) = makeWatcher(board)
        board.simulateTextCopy()
        watcher.checkNow()
        XCTAssertEqual(fired(), [])
    }

    func testBoardContentAtStartupIsIgnored() {
        let board = FakePasteboard()
        board.simulateUserCopy([URL(fileURLWithPath: "/tmp/velho.txt")])
        let (watcher, fired) = makeWatcher(board) // watcher born AFTER the copy
        watcher.checkNow()
        XCTAssertEqual(fired(), [], "pre-existing clipboard is history, not a new copy")
    }
}
