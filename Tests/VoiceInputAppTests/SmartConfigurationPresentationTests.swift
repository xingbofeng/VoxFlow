import XCTest
@testable import VoiceInputApp

final class SmartConfigurationPresentationTests: XCTestCase {
    func testSmartConfigurationCanCloseFromHeaderAndBackdrop() {
        XCTAssertTrue(SmartConfigurationPresentationPolicy.showsCloseButton)
        XCTAssertTrue(SmartConfigurationPresentationPolicy.dismissesOnBackdropTap)
    }
}
