import XCTest
@testable import VoxFlowApp

final class SmartConfigurationPresentationTests: XCTestCase {
    func testSmartConfigurationCanCloseFromHeaderAndBackdrop() {
        XCTAssertTrue(SmartConfigurationPresentationPolicy.showsCloseButton)
        XCTAssertTrue(SmartConfigurationPresentationPolicy.dismissesOnBackdropTap)
        XCTAssertTrue(SmartConfigurationPresentationPolicy.dismissesOnEscapeKey)
    }

    func testSmartConfigurationCountTextFormatsIntegerValuesSafely() {
        XCTAssertTrue(SmartConfigurationText.discoveredAppCount(122).contains("122"))
        XCTAssertTrue(SmartConfigurationText.appliedRecommendationCount(7).contains("7"))
        XCTAssertTrue(SmartConfigurationText.groupAppCount(3).contains("3"))
    }
}
