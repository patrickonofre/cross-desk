import os

/// Unified logging, hidden from regular users (PROTOCOL debugging aid).
/// Follow live from a terminal:
///
///     log stream --predicate 'subsystem == "dev.crossdesk.mac"' --info --debug
///
/// Or filter by `dev.crossdesk.mac` in Console.app. Never log secrets here —
/// pairing codes/PSKs only as truncated fingerprints (`PairingKey.fingerprint`).
public enum Log {
    public static let transport = Logger(subsystem: "dev.crossdesk.mac", category: "transport")
    public static let session = Logger(subsystem: "dev.crossdesk.mac", category: "session")
    public static let capture = Logger(subsystem: "dev.crossdesk.mac", category: "capture")
    public static let app = Logger(subsystem: "dev.crossdesk.mac", category: "app")
}
