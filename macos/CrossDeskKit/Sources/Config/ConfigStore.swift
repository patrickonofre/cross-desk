import Foundation

public enum Role: String, Codable, Equatable, Sendable {
    case server, client
}

public struct AppConfig: Codable, Equatable, Sendable {
    public var role: Role
    /// Server only: which edge hands control to the client.
    public var edgeSide: EdgeSide
    /// Client only: server address.
    public var serverHost: String
    public var port: UInt16
    /// Pairing token/code. Server: current short token (regenerated while
    /// unpaired); client: last token the user typed — kept until a handshake
    /// with `pairedSecret` succeeds (fallback, R30). Kept in the JSON config
    /// for the MVP — Keychain migration is tracked in STATE.md.
    public var pairingCode: String
    /// Long-term secret delivered via PAIR_SET after the first handshake
    /// (32 hex chars). "" = not paired. Same Keychain caveat as pairingCode.
    public var pairedSecret: String
    /// Client only: Bonjour instance name of the paired server — highlights it
    /// in the discovery list and drives silent reconnection.
    public var pairedServerName: String
    public var deviceName: String
    /// Hide the arrow on the unfocused machine (R17). Off → cursor stays visible
    /// but parked (R18). Default on.
    public var concealCursor: Bool

    public init(
        role: Role = .server,
        edgeSide: EdgeSide = .right,
        serverHost: String = "",
        port: UInt16 = ProtocolConstants.defaultPort,
        pairingCode: String = "",
        pairedSecret: String = "",
        pairedServerName: String = "",
        deviceName: String = Host.current().localizedName ?? "Mac",
        concealCursor: Bool = true
    ) {
        self.role = role
        self.edgeSide = edgeSide
        self.serverHost = serverHost
        self.port = port
        self.pairingCode = pairingCode
        self.pairedSecret = pairedSecret
        self.pairedServerName = pairedServerName
        self.deviceName = deviceName
        self.concealCursor = concealCursor
    }

    // Tolerant decode: a config written by an older build is missing newer keys
    // (e.g. concealCursor). Fill absent keys with defaults instead of throwing —
    // ConfigStore reserves throwing for genuinely corrupt (unparseable) files,
    // never for a stale-but-valid config that would discard the pairing code.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppConfig()
        role = try c.decodeIfPresent(Role.self, forKey: .role) ?? d.role
        edgeSide = try c.decodeIfPresent(EdgeSide.self, forKey: .edgeSide) ?? d.edgeSide
        serverHost = try c.decodeIfPresent(String.self, forKey: .serverHost) ?? d.serverHost
        port = try c.decodeIfPresent(UInt16.self, forKey: .port) ?? d.port
        pairingCode = try c.decodeIfPresent(String.self, forKey: .pairingCode) ?? d.pairingCode
        pairedSecret = try c.decodeIfPresent(String.self, forKey: .pairedSecret) ?? d.pairedSecret
        pairedServerName = try c.decodeIfPresent(String.self, forKey: .pairedServerName) ?? d.pairedServerName
        deviceName = try c.decodeIfPresent(String.self, forKey: .deviceName) ?? d.deviceName
        concealCursor = try c.decodeIfPresent(Bool.self, forKey: .concealCursor) ?? d.concealCursor
    }
}

/// Loads/saves the JSON config (R13). Default location:
/// ~/Library/Application Support/CrossDesk/config.json
public struct ConfigStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.fileURL = base.appendingPathComponent("CrossDesk/config.json")
        }
    }

    /// Missing file → defaults. Corrupt file → throws (caller decides; silently
    /// resetting would discard the user's pairing code).
    public func load() throws -> AppConfig {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return AppConfig()
        }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(AppConfig.self, from: data)
    }

    public func save(_ config: AppConfig) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        try data.write(to: fileURL, options: .atomic)
    }
}
