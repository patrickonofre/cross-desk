import XCTest
@testable import CrossDeskKit

/// Sender → Receiver round-trips with no network (T43): spec acceptances
/// 3 (tree fidelity), 5 (malicious paths) and 6 (name collision) live here.
final class FilePipelineTests: XCTestCase {

    private var workDir: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        workDir = fm.temporaryDirectory
            .appendingPathComponent("crossdesk-tests-\(UUID().uuidString)")
        try fm.createDirectory(at: workDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: workDir)
    }

    private func makeStaging() throws -> FileReceiver {
        try FileReceiver(stagingRoot: workDir.appendingPathComponent("staging-\(UUID().uuidString)"))
    }

    private func pump(_ sender: FileSender, into receiver: FileReceiver) throws {
        while let message = try sender.nextMessage() {
            try receiver.handle(message)
        }
    }

    @discardableResult
    private func write(_ content: Data, to relative: String, under root: URL) throws -> URL {
        let url = root.appendingPathComponent(relative)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: url)
        return url
    }

    /// Deterministic non-trivial content, larger than N chunks when asked.
    private func blob(_ count: Int) -> Data {
        Data((0..<count).map { UInt8($0 % 251) })
    }

    // MARK: - Acceptance 3: tree fidelity

    func testRoundTripFaithfullyReproducesTree() throws {
        let root = workDir.appendingPathComponent("Fotos de férias")
        let big = blob(150_000) // > 2 chunks of 64 KiB
        try write(Data("hello".utf8), to: "a.txt", under: root)
        try write(Data(), to: "vazio.bin", under: root)
        try write(big, to: "céu ☀️/imagem.jpg", under: root)
        try write(Data("fundo".utf8), to: "céu ☀️/sub/b.txt", under: root)
        try fm.createDirectory(at: root.appendingPathComponent("pasta vazia"), withIntermediateDirectories: true)
        try fm.createSymbolicLink(
            atPath: root.appendingPathComponent("ln").path,
            withDestinationPath: "a.txt"
        )

        let sender = try FileSender(roots: [root])
        let receiver = try makeStaging()
        try pump(sender, into: receiver)
        XCTAssertTrue(receiver.isComplete)

        let staged = try XCTUnwrap(receiver.stagedItemURLs().first)
        XCTAssertEqual(staged.lastPathComponent, "Fotos de férias")
        XCTAssertEqual(
            try Data(contentsOf: staged.appendingPathComponent("a.txt")),
            Data("hello".utf8)
        )
        XCTAssertEqual(
            try Data(contentsOf: staged.appendingPathComponent("vazio.bin")).count, 0
        )
        XCTAssertEqual(
            try Data(contentsOf: staged.appendingPathComponent("céu ☀️/imagem.jpg")),
            big
        )
        XCTAssertEqual(
            try Data(contentsOf: staged.appendingPathComponent("céu ☀️/sub/b.txt")),
            Data("fundo".utf8)
        )
        var isDir: ObjCBool = false
        XCTAssertTrue(fm.fileExists(
            atPath: staged.appendingPathComponent("pasta vazia").path, isDirectory: &isDir
        ))
        XCTAssertTrue(isDir.boolValue)
        XCTAssertEqual(
            try fm.destinationOfSymbolicLink(atPath: staged.appendingPathComponent("ln").path),
            "a.txt"
        )
        XCTAssertEqual(receiver.receivedBytes, UInt64(5 + 0 + big.count + 5))
    }

    func testBigFileIsChunkedAt64KiB() throws {
        let root = workDir.appendingPathComponent("src")
        let content = blob(150_000)
        try write(content, to: "big.bin", under: root)

        let sender = try FileSender(roots: [root.appendingPathComponent("big.bin")])
        var chunks: [Data] = []
        while let message = try sender.nextMessage() {
            if case let .data(bytes) = message { chunks.append(bytes) }
        }
        XCTAssertEqual(chunks.count, 3) // 64 KiB + 64 KiB + rest
        XCTAssertTrue(chunks.allSatisfy { $0.count <= FileChannelConstants.maxChunkSize })
        XCTAssertEqual(chunks.reduce(Data(), +), content)
    }

    func testSymlinkedDirectoryIsNotWalkedThrough() throws {
        // outside/ holds a file; root/ links to it. The link must travel as a
        // link — its contents must never be read or transferred (R3).
        let outside = workDir.appendingPathComponent("outside")
        try write(Data("segredo".utf8), to: "secreto.txt", under: outside)
        let root = workDir.appendingPathComponent("root")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        try fm.createSymbolicLink(
            atPath: root.appendingPathComponent("atalho").path,
            withDestinationPath: outside.path
        )

        let sender = try FileSender(roots: [root])
        var paths: [String] = []
        while let message = try sender.nextMessage() {
            if case let .itemMeta(_, _, path, _) = message { paths.append(path) }
        }
        XCTAssertEqual(paths.sorted(), ["root", "root/atalho"])
        XCTAssertEqual(sender.totalBytes, 0, "symlink content must not count as payload")
    }

    func testTwoRootsWithSameNameAreUniquified() throws {
        let a = try write(Data("um".utf8), to: "dir1/nota.txt", under: workDir)
        let b = try write(Data("dois".utf8), to: "dir2/nota.txt", under: workDir)

        let sender = try FileSender(roots: [a, b])
        let receiver = try makeStaging()
        try pump(sender, into: receiver)

        let names = try receiver.stagedItemURLs().map(\.lastPathComponent)
        XCTAssertEqual(names, ["nota (2).txt", "nota.txt"])
    }

    // MARK: - Acceptance 5: malicious paths

    func testMaliciousPathsAreRejected() throws {
        for path in ["../evil", "/abs", "a/../b", "a//b", ".", "..", "", "a/./b"] {
            let receiver = try makeStaging()
            XCTAssertThrowsError(
                try receiver.handle(.itemMeta(kind: .file, size: 1, path: path, symlinkTarget: nil)),
                "path deveria ser rejeitado: \(path)"
            ) { error in
                XCTAssertEqual(error as? FileTransferError, .unsafePath(path))
            }
        }
    }

    func testPathWithNULByteIsRejected() throws {
        let receiver = try makeStaging()
        let path = "bad\0name"
        XCTAssertThrowsError(
            try receiver.handle(.itemMeta(kind: .file, size: 1, path: path, symlinkTarget: nil))
        ) { error in
            XCTAssertEqual(error as? FileTransferError, .unsafePath(path))
        }
    }

    func testStagedSymlinkCannotBecomePathComponent() throws {
        // Hostile sequence: stage "ln → /tmp", then address "ln/evil" — the
        // filesystem would follow the link out of staging. Must be refused.
        let receiver = try makeStaging()
        try receiver.handle(.itemMeta(kind: .symlink, size: 0, path: "ln", symlinkTarget: "/tmp"))
        try receiver.handle(.itemDone(sha256: nil))
        XCTAssertThrowsError(
            try receiver.handle(.itemMeta(kind: .file, size: 1, path: "ln/evil", symlinkTarget: nil))
        ) { error in
            XCTAssertEqual(error as? FileTransferError, .unsafePath("ln/evil"))
        }
    }

    // MARK: - Integrity (R5)

    func testWrongHashDiscardsItemAndLeavesNoVisibleFile() throws {
        let receiver = try makeStaging()
        try receiver.handle(.itemMeta(kind: .file, size: 5, path: "doc.txt", symlinkTarget: nil))
        try receiver.handle(.data(Data("hello".utf8)))
        XCTAssertThrowsError(
            try receiver.handle(.itemDone(sha256: Data(repeating: 0xFF, count: 32)))
        ) { error in
            XCTAssertEqual(error as? FileTransferError, .hashMismatch(path: "doc.txt"))
        }
        // Neither the final name nor the .part may remain.
        try receiver.handle(.transferDone)
        XCTAssertEqual(try receiver.stagedItemURLs(), [])
    }

    func testOverflowBeyondDeclaredSizeIsFatalForItem() throws {
        let receiver = try makeStaging()
        try receiver.handle(.itemMeta(kind: .file, size: 3, path: "x.bin", symlinkTarget: nil))
        XCTAssertThrowsError(try receiver.handle(.data(Data("hello".utf8)))) { error in
            XCTAssertEqual(error as? FileTransferError, .overflow(path: "x.bin"))
        }
    }

    func testItemDoneBeforeAllBytesIsSizeMismatch() throws {
        let receiver = try makeStaging()
        try receiver.handle(.itemMeta(kind: .file, size: 5, path: "y.bin", symlinkTarget: nil))
        try receiver.handle(.data(Data("abc".utf8)))
        XCTAssertThrowsError(
            try receiver.handle(.itemDone(sha256: Data(repeating: 0, count: 32)))
        ) { error in
            XCTAssertEqual(error as? FileTransferError, .sizeMismatch(path: "y.bin"))
        }
    }

    func testDataWithoutOpenFileIsUnexpected() throws {
        let receiver = try makeStaging()
        XCTAssertThrowsError(try receiver.handle(.data(Data([1])))) { error in
            XCTAssertEqual(error as? FileTransferError, .unexpectedMessage)
        }
    }

    // MARK: - Acceptance 6: collision on materialize

    func testMaterializeSuffixesOnCollision() throws {
        let root = workDir.appendingPathComponent("src2")
        try write(Data("novo".utf8), to: "relatório.pdf", under: root)

        let sender = try FileSender(roots: [root.appendingPathComponent("relatório.pdf")])
        let receiver = try makeStaging()
        try pump(sender, into: receiver)

        let destination = workDir.appendingPathComponent("Downloads")
        try write(Data("antigo".utf8), to: "relatório.pdf", under: destination)
        try write(Data("antigo 2".utf8), to: "relatório (2).pdf", under: destination)

        let moved = try receiver.materialize(into: destination)
        XCTAssertEqual(moved.map(\.lastPathComponent), ["relatório (3).pdf"])
        XCTAssertEqual(try Data(contentsOf: moved[0]), Data("novo".utf8))
        // Originals untouched.
        XCTAssertEqual(
            try Data(contentsOf: destination.appendingPathComponent("relatório.pdf")),
            Data("antigo".utf8)
        )
    }

    func testMaterializeBeforeCompleteThrows() throws {
        let receiver = try makeStaging()
        XCTAssertThrowsError(try receiver.materialize(into: workDir)) { error in
            XCTAssertEqual(error as? FileTransferError, .incompleteTransfer)
        }
    }

    // MARK: - Staging hygiene (D3)

    func testCleanStagingRemovesOnlyOldEntries() throws {
        let root = workDir.appendingPathComponent("incoming")
        let old = root.appendingPathComponent("velho")
        let fresh = root.appendingPathComponent("novo")
        try fm.createDirectory(at: old, withIntermediateDirectories: true)
        try fm.createDirectory(at: fresh, withIntermediateDirectories: true)
        try fm.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: -48 * 3600)],
            ofItemAtPath: old.path
        )

        FileReceiver.cleanStaging(root: root)

        XCTAssertFalse(fm.fileExists(atPath: old.path))
        XCTAssertTrue(fm.fileExists(atPath: fresh.path))
    }
}
