import XCTest
@testable import VoxFlowApp

final class HomeHistoryDetailLayoutTests: XCTestCase {
    func testExpandedRequestJSONLivesInsideScrollableBoundedModal() {
        XCTAssertTrue(HomeHistoryDetailLayout.usesScrollableContent)
        XCTAssertGreaterThan(HomeHistoryDetailLayout.modalMaxHeight, HomeHistoryDetailLayout.modalIdealHeight)
        XCTAssertLessThanOrEqual(HomeHistoryDetailLayout.modalMaxHeight, 760)
        XCTAssertEqual(HomeHistoryDetailLayout.requestJSONMaxHeight, 220)
    }
}
