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
        config.pairingCode = "0123456789abcdef0123456789abcdef"
        config.edgeSide = .left
        config.deviceName = "MacBook do Patrick"

        try store.save(config)
        XCTAssertEqual(try store.load(), config)
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
