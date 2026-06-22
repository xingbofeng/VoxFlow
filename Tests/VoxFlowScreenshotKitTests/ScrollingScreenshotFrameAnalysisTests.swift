import XCTest
@testable import VoxFlowScreenshotKit

final class ScrollingScreenshotFrameAnalysisTests: XCTestCase {
    func testShiftEstimateConfidenceUsesAgreeingBandRatio() {
        let estimate = ScrollingScreenshotShiftEstimate(
            rows: 42,
            agreeingBandCount: 4,
            totalBandCount: 5,
            excludedTopRows: 12,
            excludedRightColumns: 8
        )

        XCTAssertEqual(estimate.confidence, 0.8, accuracy: 0.0001)
        XCTAssertEqual(estimate.rows, 42)
        XCTAssertEqual(estimate.excludedTopRows, 12)
        XCTAssertEqual(estimate.excludedRightColumns, 8)
    }

    func testSessionStatusTracksUnstableFailure() {
        let status = ScrollingScreenshotSessionStatus(
            stripCount: 3,
            pixelHeight: 1800,
            health: .unstable(reason: .bandVoteDisagreed, consecutiveFailures: 2),
            isAutoScrolling: false
        )

        XCTAssertEqual(status.stripCount, 3)
        XCTAssertEqual(status.pixelHeight, 1800)
        XCTAssertEqual(status.health, .unstable(reason: .bandVoteDisagreed, consecutiveFailures: 2))
        XCTAssertFalse(status.isAutoScrolling)
    }

    func testStitchResultSkippedStoresFailureReason() {
        let result = ScrollingScreenshotStitchResult.skipped(.shiftTooSmall(2))

        XCTAssertNil(result.image)
        XCTAssertNil(result.estimate)
        XCTAssertEqual(result.failureReason, .shiftTooSmall(2))
    }
}
