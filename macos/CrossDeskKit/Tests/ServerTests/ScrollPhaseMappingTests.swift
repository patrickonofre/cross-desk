import XCTest
@testable import CrossDeskKit

/// The scroll phase crosses the wire as a neutral value: capture maps macOS
/// `CGScrollPhase`→neutral, injection maps neutral→`CGScrollPhase`. The two must
/// be inverse so a trackpad gesture survives the round trip intact (R20).
final class ScrollPhaseMappingTests: XCTestCase {
    func testScrollPhaseRoundTripThroughCG() {
        for phase in ScrollPhase.allCases {
            let cg = InputInjector.cgScrollPhase(phase)
            XCTAssertEqual(InputCapture.scrollPhase(cg), phase, "phase \(phase) not preserved")
        }
    }

    func testMomentumPhaseRoundTripThroughCG() {
        for momentum in MomentumPhase.allCases {
            let cg = InputInjector.cgMomentumPhase(momentum)
            XCTAssertEqual(InputCapture.momentumPhase(cg), momentum, "momentum \(momentum) not preserved")
        }
    }

    func testUnknownCGScrollPhaseCollapsesToNone() {
        XCTAssertEqual(InputCapture.scrollPhase(128), .none) // kCGScrollPhaseMayBegin
        XCTAssertEqual(InputCapture.scrollPhase(99), .none)
    }
}
