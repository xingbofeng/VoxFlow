import AppKit
import XCTest
@testable import VoxFlowApp

final class WaveformModelTests: XCTestCase {
    func testFiveBarsFitExactlyInsideRequiredWidth() {
        XCTAssertEqual(WaveformModel.barCount, 5)
        XCTAssertEqual(WaveformModel.totalWidth, 44)
    }

    func testRequiredWeightsAndEnvelopeRatesAreUsed() {
        XCTAssertEqual(WaveformModel.weights, [0.5, 0.8, 1.0, 0.75, 0.55])
        XCTAssertEqual(WaveformModel.attackRate, 0.40)
        XCTAssertEqual(WaveformModel.releaseRate, 0.15)
    }

    func testAttackAndReleaseSmoothTheRMSLevel() {
        var model = WaveformModel()

        _ = model.update(targetRMS: 1.0, jitter: { 0 })
        XCTAssertEqual(model.smoothedRMS, 0.40, accuracy: 0.0001)

        _ = model.update(targetRMS: 0.0, jitter: { 0 })
        XCTAssertEqual(model.smoothedRMS, 0.34, accuracy: 0.0001)
    }

    func testBarHeightsFollowCenterWeightedShapeWithoutJitter() {
        var model = WaveformModel()

        let heights = model.update(targetRMS: 1.0, jitter: { 0 })

        XCTAssertEqual(heights.count, 5)
        XCTAssertGreaterThan(heights[2], heights[1])
        XCTAssertGreaterThan(heights[1], heights[0])
        XCTAssertGreaterThan(heights[2], heights[3])
        XCTAssertGreaterThan(heights[3], heights[4])
    }
}
