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
}
