import XCTest
import Network
@testable import CrossDeskKit

/// Advertise + browse + connect on the same machine — kills design
/// uncertainties 1 (DTLS over a `.service` endpoint) and 3 in one pass.
///
/// mDNS may be unavailable in sandboxed/CI environments (Local Network
/// policy); the test skips instead of failing there — the real-network
/// behavior is covered by UAT T38.
final class DiscoveryTests: XCTestCase {
    private var server: DTLSServer!
    private var client: DTLSClient!
    private var browser: ServerBrowser!

    override func tearDown() {
        client?.stop()
        browser?.stop()
        server?.stop()
        client = nil
        browser = nil
        server = nil
        super.tearDown()
    }

    func testAdvertisedServerIsDiscoveredAndConnectable() throws {
        let serviceName = "cdtest-\(UUID().uuidString.prefix(8))"
        let tokenPSK = PairingKey.psk(fromCode: "ABCD-EFGH")
        let port: UInt16 = 24895

        server = DTLSServer(port: port, psk: tokenPSK, advertiseName: serviceName)
        try server.start()

        // Browse until OUR instance shows up (other CrossDesk servers may
        // legitimately exist on the LAN).
        let found = LockedValue<DiscoveredServer?>(nil)
        let discovered = expectation(description: "server discovered")
        discovered.assertForOverFulfill = false
        browser = ServerBrowser()
        browser.onUpdate = { servers in
            if let match = servers.first(where: { $0.name == serviceName }) {
                if found.get() == nil { found.set(match) }
                discovered.fulfill()
            }
        }
        browser.start()

        guard XCTWaiter().wait(for: [discovered], timeout: 8) == .completed else {
            throw XCTSkip("mDNS indisponível neste ambiente (Local Network policy?) — coberto pelo UAT T38")
        }

        // Connect straight to the Bonjour endpoint — no host, no port.
        let endpoint = try XCTUnwrap(found.get()).endpoint
        let connected = expectation(description: "client connected via Bonjour endpoint")
        client = DTLSClient(endpoint: endpoint, psk: tokenPSK, deviceName: "c")
        client.onEvent = { event in
            if case .connected = event { connected.fulfill() }
        }
        client.start()
        wait(for: [connected], timeout: 10)
    }
}
