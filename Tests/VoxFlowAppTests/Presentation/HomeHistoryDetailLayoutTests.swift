import XCTest
@testable import VoxFlowApp

final class HomeHistoryDetailLayoutTests: XCTestCase {
    func testExpandedRequestJSONLivesInsideScrollableBoundedModal() {
        XCTAssertTrue(HomeHistoryDetailLayout.usesScrollableContent)
        XCTAssertGreaterThan(HomeHistoryDetailLayout.modalMaxHeight, HomeHistoryDetailLayout.modalIdealHeight)
        XCTAssertLessThanOrEqual(HomeHistoryDetailLayout.modalMaxHeight, 760)
        XCTAssertEqual(HomeHistoryDetailLayout.requestJSONMaxHeight, 220)
    }

    func testFixedResultSectionContractKeepsHeaderAndResultsAboveScrollableDiagnostics() {
        // The Header and top result comparison area must live above the
        // diagnostic ScrollView. Only dispatch info, transcription info,
        // pipeline, warnings, and diagnostics scroll.
        XCTAssertTrue(HomeHistoryDetailLayout.usesFixedResultSection)
        XCTAssertTrue(HomeHistoryDetailLayout.scrollsDiagnosticsBelowResults)
    }

    func testTextComparisonHasBoundedMaxHeightAvoidingNestedScrollbar() {
        // Comparison text wraps inside the fixed top area without introducing
        // a second vertical scrollbar; its maxHeight must stay within the
        // modal's overall height budget.
        XCTAssertGreaterThan(HomeHistoryDetailLayout.textComparisonMaxHeight, 0)
        XCTAssertLessThanOrEqual(
            HomeHistoryDetailLayout.textComparisonMaxHeight,
            HomeHistoryDetailLayout.modalIdealHeight
        )
    }
}
