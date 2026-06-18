import XCTest
@testable import VoxFlowApp

final class StyleViewLayoutTests: XCTestCase {
    func testStyleMenuAndEditorPanesFitMinimumWorkbenchWidth() {
        XCTAssertEqual(StyleViewLayout.menuWidth, 300)
        XCTAssertEqual(StyleViewLayout.minimumEditorPaneWidth, 300)
        XCTAssertLessThanOrEqual(StyleViewLayout.minimumContentWidth, 960)
    }
}
