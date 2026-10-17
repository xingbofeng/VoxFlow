import AppKit
import XCTest
@testable import VoxFlowApp

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

    func testHomeDetailOverlayHostsActionFeedbackAboveModal() {
        XCTAssertTrue(HomeDetailOverlayPresentation.hostsActionFeedback)
    }

    // MARK: - CDS token contract

    func testCDSClayAccentIsTerracottaNotColdGreen() {
        assertRGB(CDS.Clay.baseNSColor, 0xD9, 0x77, 0x57)
        assertRGB(CDS.Clay.hoverNSColor, 0xCC, 0x5A, 0x36)
    }

    func testCDSSurfaceLadderStaysWarmNeutral() {
        assertRGB(CDS.Surface.level0NSColor, 0xF9, 0xF9, 0xF7)
        assertRGB(CDS.Surface.level2NSColor, 0xFF, 0xFF, 0xFF)
        assertRGB(CDS.Surface.level3NSColor, 0xFF, 0xFF, 0xFF)
    }

    func testAppThemeResolvesToCDSTokens() {
        assertRGB(NSColor(AppTheme.ColorToken.accent), 0xD9, 0x77, 0x57)
        assertRGB(NSColor(AppTheme.ColorToken.accentDark), 0xC2, 0x51, 0x24)
    }

    func testCDSScrollFadeUsesSevenNonLinearStops() {
        XCTAssertEqual(CDS.scrollFadeStops.count, 6)
        XCTAssertEqual(CDS.scrollFadeStops.first?.location, 0.15)
        XCTAssertEqual(CDS.scrollFadeStops.last?.location, 0.87)
        let alphas = CDS.scrollFadeStops.map(\.alpha)
        XCTAssertEqual(alphas, alphas.sorted(), "fade must be monotonic inward")
        XCTAssertLessThan(alphas[0], 0.06, "edge stop must stay nearly transparent")
    }

    func testCDSRadiiFollowRadiusMatrix() {
        XCTAssertEqual(CDS.Radius.panel, 10)
        XCTAssertEqual(CDS.Radius.bubble, 18)
        XCTAssertEqual(CDS.Radius.composer, 20)
        XCTAssertEqual(CDS.Radius.pill, 999)
    }

    private func assertRGB(
        _ color: NSColor,
        _ red: Int,
        _ green: Int,
        _ blue: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let resolved = color.usingColorSpace(.sRGB) ?? color
        XCTAssertEqual(Int((resolved.redComponent * 255).rounded()), red, "red", file: file, line: line)
        XCTAssertEqual(Int((resolved.greenComponent * 255).rounded()), green, "green", file: file, line: line)
        XCTAssertEqual(Int((resolved.blueComponent * 255).rounded()), blue, "blue", file: file, line: line)
    }
}
