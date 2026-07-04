import Foundation

extension NSLock {
    /// Runs `body` while holding the lock. Shared across the kit's small
    /// lock-guarded state machines (capture, cursor, metrics).
    func withLock<T>(_ body: () -> T) -> T {
        lock(); defer { unlock() }
        return body()
    }
}
