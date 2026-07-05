import XCTest
@testable import CrossDeskKit

/// End-to-end loopback (T45 "done when"): two coordinators cross-wired over a
/// fake control channel + a REAL TCP/TLS-PSK file channel on localhost.
final class TransferCoordinatorTests: XCTestCase {

    private nonisolated(unsafe) static var nextPort: UInt16 = 24940
    private var port: UInt16 = 0
    private var workDir: URL!
    private var serverCoordinator: TransferCoordinator?
    private var clientCoordinator: TransferCoordinator?
    private let fm = FileManager.default

    private static let psk = PairingKey.filePSK(fromCode: "0123456789abcdef0123456789abcdef")

    override func setUpWithError() throws {
        port = Self.nextPort
        Self.nextPort += 1
        workDir = fm.temporaryDirectory
            .appendingPathComponent("crossdesk-coord-\(UUID().uuidString)")
        try fm.createDirectory(at: workDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        serverCoordinator?.stop()
        clientCoordinator?.stop()
        serverCoordinator = nil
        clientCoordinator = nil
        try? fm.removeItem(at: workDir)
    }

    private struct Pair {
        let server: TransferCoordinator
        let client: TransferCoordinator
        let serverBoard: FakePasteboard
        let clientBoard: FakePasteboard
        let serverDownloads: URL
    }

    private func makePair(serverEagerLimit: UInt64 = 200 * 1024 * 1024) throws -> Pair {
        let serverBoard = FakePasteboard()
        let clientBoard = FakePasteboard()
        let serverDownloads = workDir.appendingPathComponent("downloads-server")

        let server = TransferCoordinator(
            role: .server,
            port: port,
            filePSK: Self.psk,
            policy: TransferPolicy(
                eagerLimit: serverEagerLimit,
                stagingRoot: workDir.appendingPathComponent("staging-server"),
                downloadsDir: serverDownloads
            ),
            pasteboard: serverBoard
        )
        let client = TransferCoordinator(
            role: .client(serverHost: "127.0.0.1"),
            port: port,
            filePSK: Self.psk,
            policy: TransferPolicy(
                stagingRoot: workDir.appendingPathComponent("staging-client"),
                downloadsDir: workDir.appendingPathComponent("downloads-client")
            ),
            pasteboard: clientBoard
        )
        // Fake DTLS control channel: direct cross-wiring.
        server.sendControl = { [weak client] messages in
            for message in messages { client?.handleControl(message) }
        }
        client.sendControl = { [weak server] messages in
            for message in messages { server?.handleControl(message) }
        }
        try server.start()
        try client.start()
        serverCoordinator = server
        clientCoordinator = client
        return Pair(
            server: server, client: client,
            serverBoard: serverBoard, clientBoard: clientBoard,
            serverDownloads: serverDownloads
        )
    }

    @discardableResult
    private func writeSource(_ content: Data, name: String) throws -> URL {
        let url = workDir.appendingPathComponent(name)
        try content.write(to: url)
        return url
    }

    private func expectDone(
        _ coordinator: TransferCoordinator, description: String
    ) -> XCTestExpectation {
        let expectation = expectation(description: description)
        coordinator.onUIState = { state in
            if case .done = state { expectation.fulfill() }
        }
        return expectation
    }

    // MARK: - Eager flows (D2), both directions

    func testClientCopyLandsOnServerPasteboard() throws {
        let pair = try makePair()
        let content = Data("olá do cliente".utf8)
        let source = try writeSource(content, name: "mensagem.txt")

        let done = expectDone(pair.server, description: "server .done")
        // Watcher path is unit-tested; here the copy enters via the public API.
        pair.client.announceLocalCopy(roots: [source])
        wait(for: [done], timeout: 15)

        let urls = pair.serverBoard.readFileURLs()
        XCTAssertEqual(urls.map(\.lastPathComponent), ["mensagem.txt"])
        XCTAssertEqual(try Data(contentsOf: urls[0]), content)
        XCTAssertTrue(pair.serverBoard.hasOwnMarker(), "received write must carry the anti-loop marker")
    }

    func testServerCopyLandsOnClientPasteboard() throws {
        let pair = try makePair()
        let content = Data((0..<100_000).map { UInt8($0 % 251) }) // 2 chunks
        let source = try writeSource(content, name: "grande.bin")

        let done = expectDone(pair.client, description: "client .done")
        pair.server.announceLocalCopy(roots: [source])
        wait(for: [done], timeout: 15)

        let urls = pair.clientBoard.readFileURLs()
        XCTAssertEqual(urls.map(\.lastPathComponent), ["grande.bin"])
        XCTAssertEqual(try Data(contentsOf: urls[0]), content)
    }

    // MARK: - Above the limit: pending offer → "Receber agora" (D2/R6)

    func testAboveLimitWaitsAndReceiveNowGoesToDownloads() throws {
        let pair = try makePair(serverEagerLimit: 10) // everything is "big"
        let content = Data("conteúdo acima do teto".utf8)
        let source = try writeSource(content, name: "pesado.bin")

        nonisolated(unsafe) var sawPending: (UInt32, Int, UInt64)?
        let pending = expectation(description: "server .pendingOffer")
        let done = expectation(description: "server .done in Downloads")
        pair.server.onUIState = { state in
            switch state {
            case let .pendingOffer(id, items, bytes):
                sawPending = (id, items, bytes)
                pending.fulfill()
            case let .done(_, urls, movedToDownloads):
                XCTAssertTrue(movedToDownloads)
                XCTAssertEqual(urls.map(\.lastPathComponent), ["pesado.bin"])
                done.fulfill()
            default:
                break
            }
        }

        pair.client.announceLocalCopy(roots: [source])
        wait(for: [pending], timeout: 15)
        XCTAssertEqual(sawPending?.1, 1)
        XCTAssertEqual(sawPending?.2, UInt64(content.count))
        // Nothing materialized yet — the pasteboard must be untouched.
        XCTAssertEqual(pair.serverBoard.readFileURLs(), [])

        pair.server.receiveNow()
        wait(for: [done], timeout: 15)

        let landed = pair.serverDownloads.appendingPathComponent("pesado.bin")
        XCTAssertEqual(try Data(contentsOf: landed), content)
        XCTAssertEqual(pair.serverBoard.readFileURLs(), [], "Downloads flow must not touch the pasteboard")
    }

    func testDismissPendingOfferGoesIdle() throws {
        let pair = try makePair(serverEagerLimit: 10)
        let source = try writeSource(Data("bem maior que dez bytes".utf8), name: "a.bin")

        let pending = expectation(description: "pendingOffer")
        let idle = expectation(description: "idle after dismiss")
        pair.server.onUIState = { state in
            switch state {
            case .pendingOffer: pending.fulfill()
            case .idle: idle.fulfill()
            default: break
            }
        }
        pair.client.announceLocalCopy(roots: [source])
        wait(for: [pending], timeout: 15)

        pair.server.dismissPendingOffer()
        wait(for: [idle], timeout: 5)
    }

    // MARK: - Tree fidelity through the whole stack

    func testDirectoryTreeSurvivesTheFullStack() throws {
        let pair = try makePair()
        let root = workDir.appendingPathComponent("Projeto")
        try fm.createDirectory(at: root.appendingPathComponent("docs"), withIntermediateDirectories: true)
        try Data("readme".utf8).write(to: root.appendingPathComponent("README.md"))
        try Data("spec".utf8).write(to: root.appendingPathComponent("docs/spec.md"))

        let done = expectDone(pair.server, description: "server .done")
        pair.client.announceLocalCopy(roots: [root])
        wait(for: [done], timeout: 15)

        let staged = try XCTUnwrap(pair.serverBoard.readFileURLs().first)
        XCTAssertEqual(staged.lastPathComponent, "Projeto")
        XCTAssertEqual(
            try Data(contentsOf: staged.appendingPathComponent("README.md")),
            Data("readme".utf8)
        )
        XCTAssertEqual(
            try Data(contentsOf: staged.appendingPathComponent("docs/spec.md")),
            Data("spec".utf8)
        )
    }
}
