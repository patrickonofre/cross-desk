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
    /// Shared secret. Server generates it; client stores what the user typed.
    /// Kept in the JSON config for the MVP — Keychain migration is tracked in
    /// STATE.md.
    public var pairingCode: String
    public var deviceName: String

    public init(
        role: Role = .server,
        edgeSide: EdgeSide = .right,
        serverHost: String = "",
        port: UInt16 = ProtocolConstants.defaultPort,
        pairingCode: String = "",
        deviceName: String = Host.current().localizedName ?? "Mac"
    ) {
        self.role = role
        self.edgeSide = edgeSide
        self.serverHost = serverHost
        self.port = port
        self.pairingCode = pairingCode
        self.deviceName = deviceName
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
