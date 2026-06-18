import XCTest
@testable import VoxFlowApp

final class SmartConfigurationPresentationTests: XCTestCase {
    func testSmartConfigurationCanCloseFromHeaderAndBackdrop() {
        XCTAssertTrue(SmartConfigurationPresentationPolicy.showsCloseButton)
        XCTAssertTrue(SmartConfigurationPresentationPolicy.dismissesOnBackdropTap)
    }
}
