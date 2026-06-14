import XCTest
@testable import VoiceInputApp

final class PermissionGuideLayoutTests: XCTestCase {
    func testTwoPermissionItemsLeaveRoomForFooterActions() {
        XCTAssertGreaterThanOrEqual(
            PermissionGuideLayout.windowHeight(itemCount: 2),
            470
        )
    }

    func testAdditionalPermissionItemIncreasesWindowHeight() {
        XCTAssertGreaterThan(
            PermissionGuideLayout.windowHeight(itemCount: 3),
            PermissionGuideLayout.windowHeight(itemCount: 2)
        )
    }
}
