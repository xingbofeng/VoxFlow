import XCTest
@testable import VoxFlowApp

final class StyleViewLayoutTests: XCTestCase {
    func testStyleMenuAndEditorPanesFitMinimumWorkbenchWidth() {
        XCTAssertEqual(StyleViewLayout.menuWidth, 300)
        XCTAssertEqual(StyleViewLayout.minimumEditorPaneWidth, 300)
        XCTAssertLessThanOrEqual(StyleViewLayout.minimumContentWidth, 960)
    }

    func testPromptEditorExposesRestoreDefaultAction() throws {
        let source = try String(
            contentsOfFile: "Sources/VoxFlowApp/Views/StyleView.swift",
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("style.action.restore_default"))
        XCTAssertTrue(source.contains("resetBuiltInPrompt(id: profile.id)"))
        XCTAssertTrue(source.contains("systemImage: \"arrow.counterclockwise\""))
        XCTAssertTrue(source.contains(".disabled(viewModel.selectedProfile?.builtIn != true)"))
    }
}
