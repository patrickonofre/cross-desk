import Foundation

/// Streams this device's own unified log for the debug console (debug-console
/// R44) by shelling out to the exact command already documented in
/// `Logging.swift`. `OSLogStore` has no push API and would need polling anyway,
/// so the subprocess is the simpler, already-proven path — same `Process`/`Pipe`
/// pattern as `AppState.relaunch()`.
public final class LogStreamer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "crossdesk.debug.logstreamer")
    private var process: Process?
    private var pipe: Pipe?
    private var carry = Data()
    private let buffer: DebugLogBuffer

    public init(buffer: DebugLogBuffer) {
        self.buffer = buffer
    }

    public func start() {
        queue.async { [self] in
            guard process == nil else { return }
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/log")
            task.arguments = [
                "stream",
                "--predicate", "subsystem == \"dev.crossdesk.mac\"",
                "--style", "compact",
                "--info", "--debug",
            ]
            let outputPipe = Pipe()
            task.standardOutput = outputPipe
            task.standardError = FileHandle.nullDevice
            outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                guard let self else { return }
                let data = handle.availableData
                guard !data.isEmpty else { return }
                self.queue.async {
                    self.consume(data)
                }
            }
            do {
                try task.run()
                process = task
                pipe = outputPipe
                Log.app.info("debug console: log stream started (pid \(task.processIdentifier))")
            } catch {
                Log.app.error("debug console: log stream failed to start: \(String(describing: error), privacy: .public)")
            }
        }
    }

    public func stop() {
        queue.async { [self] in
            pipe?.fileHandleForReading.readabilityHandler = nil
            process?.terminate()
            process = nil
            pipe = nil
            carry.removeAll()
        }
    }

    /// Runs on `queue`. Splits on raw newline bytes (never a UTF-8 continuation
    /// byte) before decoding — decoding a chunk independently would risk the same
    /// multi-byte truncation class of bug fixed in Message/FileChannelMessage on
    /// 2026-07-05.
    private func consume(_ data: Data) {
        carry.append(data)
        while let range = carry.range(of: Data([0x0A])) {
            let lineData = carry.subdata(in: carry.startIndex..<range.lowerBound)
            carry.removeSubrange(carry.startIndex..<range.upperBound)
            if let line = String(data: lineData, encoding: .utf8), !line.isEmpty {
                buffer.append(line)
            }
        }
    }
}
