import XCTest
@testable import CrossDeskKit

final class ConfigStoreTests: XCTestCase {
    var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("crossdesk-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: tempDir)
    }

    private var store: ConfigStore {
        ConfigStore(fileURL: tempDir.appendingPathComponent("nested/config.json"))
    }

    func testMissingFileLoadsDefaults() throws {
        let config = try store.load()
        XCTAssertEqual(config.role, .server)
        XCTAssertEqual(config.port, ProtocolConstants.defaultPort)
        XCTAssertEqual(config.edgeSide, .right)
    }

    func testSaveLoadRoundTrip() throws {
        var config = AppConfig()
        config.role = .client
        config.serverHost = "192.168.1.10"
        config.port = 24801
        config.pairingCode = "ABCD-EFGH"
        config.pairedSecret = "0123456789abcdef0123456789abcdef"
        config.pairedServerName = "Mac Studio"
        config.edgeSide = .left
        config.deviceName = "MacBook do Patrick"

        try store.save(config)
        XCTAssertEqual(try store.load(), config)
    }

    func testConfigFromOlderBuildLoadsWithPairingDefaults() throws {
        // A config written before discovery-pairing has no pairedSecret /
        // pairedServerName keys — it must load with defaults, never throw
        // (throwing would discard the user's pairing code, see AppConfig docs).
        let url = tempDir.appendingPathComponent("nested/config.json")
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let oldJSON = """
        {"role":"client","edgeSide":"right","serverHost":"10.0.0.2","port":24800,
         "pairingCode":"0123456789abcdef0123456789abcdef","deviceName":"Mac","concealCursor":true}
        """
        try Data(oldJSON.utf8).write(to: url)

        let config = try store.load()
        XCTAssertEqual(config.pairingCode, "0123456789abcdef0123456789abcdef")
        XCTAssertEqual(config.pairedSecret, "")
        XCTAssertEqual(config.pairedServerName, "")
    }

    func testCorruptFileThrows() throws {
        let url = tempDir.appendingPathComponent("nested/config.json")
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data("not json{{".utf8).write(to: url)
        XCTAssertThrowsError(try store.load())
    }
}
