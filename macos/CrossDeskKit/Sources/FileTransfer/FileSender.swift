import Foundation
import CryptoKit

/// Walks a selection of file URLs and emits the §8 message sequence:
/// ITEM_META (+ DATA chunks + ITEM_DONE) per item, then TRANSFER_DONE.
///
/// Pull-based: the coordinator asks for the next message only after the
/// previous send completed — that is the sender-side backpressure (design D5).
/// Symlinks are transferred as links and NEVER followed (R3): a symlinked
/// directory does not get its contents walked.
public final class FileSender {
    struct Item {
        let url: URL
        let relativePath: String
        let kind: FileItemKind
        let size: UInt64
        let symlinkTarget: String?
    }

    let items: [Item]
    public let totalBytes: UInt64
    public var itemCount: Int { items.count }

    private var itemIndex = 0
    private enum Phase { case meta, data, done, transferDone, finished }
    private var phase: Phase = .meta
    private var handle: FileHandle?
    private var hasher = SHA256()
    private var remaining: UInt64 = 0

    public init(roots: [URL]) throws {
        let fm = FileManager.default
        var collected: [Item] = []
        // Two roots may share a display name (selection across folders) —
        // uniquify the top-level component so they don't merge at the receiver.
        var usedNames = Set<String>()
        for root in roots {
            var name = root.lastPathComponent
            if usedNames.contains(name) {
                var n = 2
                let base = (name as NSString).deletingPathExtension
                let ext = (name as NSString).pathExtension
                repeat {
                    name = ext.isEmpty ? "\(base) (\(n))" : "\(base) (\(n)).\(ext)"
                    n += 1
                } while usedNames.contains(name)
            }
            usedNames.insert(name)
            try Self.walk(url: root, relativePath: name, into: &collected, fm: fm)
        }
        // Deterministic order; lexicographic also guarantees parents before
        // children ("a" < "a/b"), which the receiver relies on.
        collected.sort { $0.relativePath < $1.relativePath }
        items = collected
        totalBytes = collected.reduce(0) { $0 + ($1.kind == .file ? $1.size : 0) }
    }

    private static func walk(
        url: URL, relativePath: String, into items: inout [Item], fm: FileManager
    ) throws {
        // attributesOfItem is lstat-like: a symlink reports itself, not its target.
        let attrs = try fm.attributesOfItem(atPath: url.path)
        switch attrs[.type] as? FileAttributeType {
        case .typeSymbolicLink:
            let target = try fm.destinationOfSymbolicLink(atPath: url.path)
            items.append(Item(
                url: url, relativePath: relativePath, kind: .symlink,
                size: 0, symlinkTarget: target
            ))
        case .typeDirectory:
            items.append(Item(
                url: url, relativePath: relativePath, kind: .directory,
                size: 0, symlinkTarget: nil
            ))
            for name in try fm.contentsOfDirectory(atPath: url.path).sorted() {
                try walk(
                    url: url.appendingPathComponent(name),
                    relativePath: relativePath + "/" + name,
                    into: &items, fm: fm
                )
            }
        case .typeRegular:
            let size = (attrs[.size] as? NSNumber)?.uint64Value ?? 0
            items.append(Item(
                url: url, relativePath: relativePath, kind: .file,
                size: size, symlinkTarget: nil
            ))
        default:
            break // sockets, fifos, devices: silently skipped
        }
    }

    /// Next frame to put on the wire; nil after TRANSFER_DONE was returned.
    public func nextMessage() throws -> FileChannelMessage? {
        switch phase {
        case .finished:
            return nil

        case .transferDone:
            phase = .finished
            return .transferDone

        case .meta:
            guard itemIndex < items.count else {
                phase = .finished
                return .transferDone
            }
            let item = items[itemIndex]
            if item.kind == .file {
                handle = try FileHandle(forReadingFrom: item.url)
                hasher = SHA256()
                remaining = item.size
                phase = item.size == 0 ? .done : .data
            } else {
                phase = .done
            }
            return .itemMeta(
                kind: item.kind, size: item.size,
                path: item.relativePath, symlinkTarget: item.symlinkTarget
            )

        case .data:
            let item = items[itemIndex]
            let want = Int(min(remaining, UInt64(FileChannelConstants.maxChunkSize)))
            guard let chunk = try handle?.read(upToCount: want), !chunk.isEmpty else {
                // The file shrank between the walk and the read.
                try? handle?.close()
                handle = nil
                throw FileTransferError.sizeMismatch(path: item.relativePath)
            }
            hasher.update(data: chunk)
            remaining -= UInt64(chunk.count)
            if remaining == 0 { phase = .done }
            return .data(chunk)

        case .done:
            let item = items[itemIndex]
            var sha: Data?
            if item.kind == .file {
                try? handle?.close()
                handle = nil
                sha = Data(hasher.finalize())
            }
            itemIndex += 1
            phase = itemIndex < items.count ? .meta : .transferDone
            return .itemDone(sha256: sha)
        }
    }
}
