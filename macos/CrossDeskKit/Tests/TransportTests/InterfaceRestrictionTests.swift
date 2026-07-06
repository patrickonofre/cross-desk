import XCTest
import Network
@testable import CrossDeskKit

/// Regression coverage for the VPN-interference fix (2026-07-06 UAT): both
/// connection parameter builders must keep refusing to route over a
/// VPN/virtual interface.
final class InterfaceRestrictionTests: XCTestCase {
    func testDTLSParametersProhibitsVirtualInterfaces() {
        let parameters = DTLSParameters.make(psk: Data("test-psk".utf8))
        XCTAssertEqual(parameters.prohibitedInterfaceTypes, [.other])
    }

    func testFileChannelParametersProhibitsVirtualInterfaces() {
        let parameters = FileChannelParameters.make(psk: Data("test-psk".utf8))
        XCTAssertEqual(parameters.prohibitedInterfaceTypes, [.other])
    }
}
