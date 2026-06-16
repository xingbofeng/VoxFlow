import XCTest
@testable import VoiceInputApp

final class AppThemeTests: XCTestCase {
    func testThemeUsesStableCompactRadiiAndSpacing() {
        XCTAssertEqual(AppTheme.Radius.card, 12)
        XCTAssertEqual(AppTheme.Radius.control, 8)
        XCTAssertEqual(AppTheme.Radius.row, 10)
        XCTAssertEqual(AppTheme.Spacing.page, 28)
        XCTAssertEqual(AppTheme.Spacing.grid, 12)
    }

    func testThemeExposesStyleOnlySurfaceTokens() {
        XCTAssertEqual(AppTheme.Border.panelLineWidth, 1)
        XCTAssertEqual(AppTheme.Border.selectedLineWidth, 1)
        XCTAssertEqual(AppTheme.Shadow.cardRadius, 8)
        XCTAssertEqual(AppTheme.Shadow.cardYOffset, 3)
    }

    func testActionFeedbackUsesCompactTopCenteredToastLayout() {
        XCTAssertEqual(ActionFeedbackLayout.maxWidth, 340)
        XCTAssertEqual(ActionFeedbackLayout.topPadding, 18)
        XCTAssertEqual(ActionFeedbackLayout.verticalPadding, 8)
        XCTAssertEqual(ActionFeedbackLayout.cornerRadius, 10)
    }

    func testActionFeedbackContentIsImmediatelyRenderable() {
        XCTAssertEqual(
            ActionFeedbackContent.resolve(message: "连接测试成功", error: nil),
            .message("连接测试成功")
        )
        XCTAssertEqual(
            ActionFeedbackContent.resolve(message: "ignored", error: "连接失败"),
            .error("连接失败")
        )
        XCTAssertEqual(
            ActionFeedbackContent.resolve(message: nil, error: nil),
            .none
        )
    }
}
