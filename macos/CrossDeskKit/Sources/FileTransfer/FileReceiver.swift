import Foundation
import CryptoKit

/// Consumes the §8 message sequence into a staging directory (design D3):
/// files are written as `<name>.part` and only renamed to their final name
/// after size + SHA-256 check — a partial or corrupt file is never visible
/// under its real name. Paths from the wire are sanitized (R7) and symlink
/// targets are written verbatim, never resolved or followed.
public final class FileReceiver {
    private let stagingRoot: URL
    private let fm = FileManager.default

    private struct OpenFile {
        let relativePath: String
        let stagedURL: URL
        let partURL: URL
        let expectedSize: UInt64
        let handle: FileHandle
        var written: UInt64 = 0
        var hasher = SHA256()
    }

    private enum Current {
        case file(OpenFile)
        case directory
        case symlink(url: URL, target: String)
    }

    private var current: Current?
    public private(set) var isComplete = false
    /// File bytes staged so far — progress source for the UI.
    public private(set) var receivedBytes: UInt64 = 0

    public init(stagingRoot: URL) throws {
        try fm.createDirectory(at: stagingRoot, withIntermediateDirectories: true)
        self.stagingRoot = stagingRoot.standardizedFileURL
    }

    // MARK: - Message intake

    public func handle(_ message: FileChannelMessage) throws {
        guard !isComplete else { throw FileTransferError.unexpectedMessage }
        switch message {
        case let .itemMeta(kind, size, path, symlinkTarget):
            guard current == nil else { throw FileTransferError.unexpectedMessage }
            let staged = try stagedURL(for: path)
            switch kind {
            case .directory:
                try fm.createDirectory(at: staged, withIntermediateDirectories: true)
                current = .directory
            case .symlink:
                current = .symlink(url: staged, target: symlinkTarget ?? "")
            case .file:
                try fm.createDirectory(
                    at: staged.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                let part = staged.appendingPathExtension("part")
                guard fm.createFile(atPath: part.path, contents: nil) else {
                    throw FileTransferError.unsafePath(path)
                }
                current = .file(OpenFile(
                    relativePath: path, stagedURL: staged, partURL: part,
                    expectedSize: size, handle: try FileHandle(forWritingTo: part)
                ))
            }

        case let .data(chunk):
            guard case .file(var item) = current else {
                throw FileTransferError.unexpectedMessage
            }
            guard item.written + UInt64(chunk.count) <= item.expectedSize else {
                try? item.handle.close()
                try? fm.removeItem(at: item.partURL)
                current = nil
                throw FileTransferError.overflow(path: item.relativePath)
            }
            try item.handle.write(contentsOf: chunk)
            item.hasher.update(data: chunk)
            item.written += UInt64(chunk.count)
            receivedBytes += UInt64(chunk.count)
            current = .file(item)

        case let .itemDone(sha256):
            switch current {
            case .file(let item):
                current = nil
                try? item.handle.close()
                guard item.written == item.expectedSize else {
                    try? fm.removeItem(at: item.partURL)
                    throw FileTransferError.sizeMismatch(path: item.relativePath)
                }
                let digest = Data(item.hasher.finalize())
                guard let sha256, digest == sha256 else {
                    try? fm.removeItem(at: item.partURL)
                    throw FileTransferError.hashMismatch(path: item.relativePath)
                }
                // Atomic visibility: the real name appears only now.
                try fm.moveItem(at: item.partURL, to: item.stagedURL)
            case let .symlink(url, target):
                current = nil
                // Target verbatim — creating a link never touches what it points at.
                try fm.createSymbolicLink(atPath: url.path, withDestinationPath: target)
            case .directory:
                current = nil
            case nil:
                throw FileTransferError.unexpectedMessage
            }

        case .transferDone:
            guard current == nil else { throw FileTransferError.unexpectedMessage }
            isComplete = true

        case .fileHello, .cancel, .error:
            // Coordinator-level messages — reaching the receiver is a bug.
            throw FileTransferError.unexpectedMessage
        }
    }

    // MARK: - Output

    /// Staged top-level URLs (for the eager pasteboard flow, design D2).
    /// Only valid after TRANSFER_DONE.
    public func stagedItemURLs() throws -> [URL] {
        guard isComplete else { throw FileTransferError.incompleteTransfer }
        return try fm.contentsOfDirectory(atPath: stagingRoot.path).sorted()
            .map { stagingRoot.appendingPathComponent($0) }
    }

    /// Moves staged top-level items into `destination` ("Receber agora" /
    /// drop fallback, R6), suffixing " (2)" on name collision (R7).
    public func materialize(into destination: URL) throws -> [URL] {
        guard isComplete else { throw FileTransferError.incompleteTransfer }
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        var moved: [URL] = []
        for name in try fm.contentsOfDirectory(atPath: stagingRoot.path).sorted() {
            let target = Self.collisionFreeURL(for: name, in: destination, fm: fm)
            try fm.moveItem(at: stagingRoot.appendingPathComponent(name), to: target)
            moved.append(target)
        }
        return moved
    }

    static func collisionFreeURL(for name: String, in dir: URL, fm: FileManager) -> URL {
        var candidate = dir.appendingPathComponent(name)
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var n = 2
        // attributesOfItem instead of fileExists: a broken symlink still occupies the name.
        while (try? fm.attributesOfItem(atPath: candidate.path)) != nil {
            let next = ext.isEmpty ? "\(base) (\(n))" : "\(base) (\(n)).\(ext)"
            candidate = dir.appendingPathComponent(next)
            n += 1
        }
        return candidate
    }

    /// Removes stale staging directories (design D3: cleaned by age at launch).
    public static func cleanStaging(
        root: URL, olderThan age: TimeInterval = 24 * 3600, now: Date = Date()
    ) {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: root.path) else { return }
        for name in names {
            let url = root.appendingPathComponent(name)
            guard let attrs = try? fm.attributesOfItem(atPath: url.path),
                  let modified = attrs[.modificationDate] as? Date else { continue }
            if now.timeIntervalSince(modified) > age {
                try? fm.removeItem(at: url)
            }
        }
    }

    // MARK: - Path safety (R7 / PROTOCOL.md §8)

    static func components(of path: String) throws -> [String] {
        guard !path.isEmpty, !path.contains("\0"), !path.hasPrefix("/") else {
            throw FileTransferError.unsafePath(path)
        }
        let parts = path.components(separatedBy: "/")
        for part in parts {
            guard !part.isEmpty, part != ".", part != ".." else {
                throw FileTransferError.unsafePath(path)
            }
        }
        return parts
    }

    private func stagedURL(for path: String) throws -> URL {
        let parts = try Self.components(of: path)
        var url = stagingRoot
        var probe = stagingRoot
        for part in parts {
            url.appendPathComponent(part)
            probe.appendPathComponent(part)
            // An already-staged symlink may never be reused as a path component
            // (or re-targeted): a hostile peer could stage "ln → /tmp" and then
            // send "ln/evil" — the filesystem would follow the link right out
            // of staging. Lexical checks don't catch this; an lstat does.
            if let type = (try? fm.attributesOfItem(atPath: probe.path))?[.type] as? FileAttributeType,
               type == .typeSymbolicLink {
                throw FileTransferError.unsafePath(path)
            }
        }
        // Belt and braces on top of the component check.
        guard url.standardizedFileURL.path.hasPrefix(stagingRoot.path + "/") else {
            throw FileTransferError.unsafePath(path)
        }
        return url
    }
}
