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

    func testPrimarySettingsURLPrefersFirstUnauthorizedSpecificPane() {
        let accessibility = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        let microphone = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
        let fallback = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy")!
        let items = [
            PermissionStatusItem(
                title: "麦克风",
                subtitle: "录制声音",
                systemImage: "mic",
                status: "已授权",
                granted: true,
                settingsURL: microphone
            ),
            PermissionStatusItem(
                title: "辅助功能",
                subtitle: "监听快捷键",
                systemImage: "accessibility",
                status: "未授权",
                granted: false,
                settingsURL: accessibility
            ),
        ]

        XCTAssertEqual(
            PermissionGuideDestination.primarySettingsURL(items: items, fallback: fallback),
            accessibility
        )
    }
}
