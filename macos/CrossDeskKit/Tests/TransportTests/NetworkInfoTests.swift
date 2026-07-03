import XCTest
@testable import CrossDeskKit

final class NetworkInfoTests: XCTestCase {
    func testHostnameIsNonEmpty() {
        XCTAssertFalse(NetworkInfo.localHostname().isEmpty)
    }

    func testAddressesExcludeLoopbackAndLinkLocal() {
        for entry in NetworkInfo.localIPv4Addresses() {
            XCTAssertFalse(entry.ip.hasPrefix("127."), "loopback leaked: \(entry)")
            XCTAssertFalse(entry.ip.hasPrefix("169.254."), "link-local leaked: \(entry)")
            XCTAssertFalse(entry.interface.isEmpty)
        }
    }

    func testPhysicalInterfacesSortFirst() {
        let addresses = NetworkInfo.localIPv4Addresses()
        guard let firstTunnelIndex = addresses.firstIndex(where: { !$0.interface.hasPrefix("en") }),
              let lastPhysicalIndex = addresses.lastIndex(where: { $0.interface.hasPrefix("en") })
        else { return } // machine has only one kind — nothing to assert
        XCTAssertLessThan(lastPhysicalIndex, firstTunnelIndex)
    }
}
