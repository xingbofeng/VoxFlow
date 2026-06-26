import XCTest
import CoreGraphics
@testable import VoxFlowScreenshotKit

final class ScreenRecordingEligibilityTests: XCTestCase {
    private let displayA = makeDisplay(id: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
    private let displayB = makeDisplay(id: 2, frame: CGRect(x: 1920, y: 0, width: 1920, height: 1080))

    func testSingleDisplaySelectionIsEligible() {
        let rect = CGRect(x: 100, y: 100, width: 500, height: 400)

        let result = ScreenRecordingEligibility.evaluate(
            selectionRect: rect,
            displays: [displayA, displayB]
        )

        XCTAssertEqual(result, .eligible(display: displayA))
        XCTAssertTrue(result.isEligible)
    }

    func testCrossDisplaySelectionIsDisabled() {
        // 选区横跨 displayA 与 displayB 的边界。
        let rect = CGRect(x: 1800, y: 100, width: 300, height: 400)

        let result = ScreenRecordingEligibility.evaluate(
            selectionRect: rect,
            displays: [displayA, displayB]
        )

        XCTAssertEqual(result, .disabled(reason: .crossDisplay))
        XCTAssertFalse(result.isEligible)
        XCTAssertEqual(ScreenRecordingDisabledReason.crossDisplay.tooltip, "区域录屏暂不支持跨显示器，请只选择一个屏幕内的区域")
    }

    func testTinyRegionIsDisabled() {
        let rect = CGRect(x: 100, y: 100, width: 30, height: 30)

        let result = ScreenRecordingEligibility.evaluate(
            selectionRect: rect,
            displays: [displayA]
        )

        XCTAssertEqual(result, .disabled(reason: .tooSmall))
        XCTAssertFalse(result.isEligible)
        XCTAssertEqual(ScreenRecordingDisabledReason.tooSmall.tooltip, "选区录屏区域太小")
    }

    func testExactlyMinimumSizeIsEligible() {
        let size = ScreenRecordingEligibility.minimumSizePoints
        let rect = CGRect(x: 100, y: 100, width: size, height: size)

        let result = ScreenRecordingEligibility.evaluate(
            selectionRect: rect,
            displays: [displayA]
        )

        XCTAssertEqual(result, .eligible(display: displayA))
    }

    func testEvaluateFromSelectionStateUsesNormalizedRect() {
        // startPoint/currentPoint 反向，normalizedRect 仍应正确归一化。
        let selection = SelectionState(
            displayFrame: displayA.frame,
            displayScale: 2,
            startPoint: CGPoint(x: 600, y: 500),
            currentPoint: CGPoint(x: 100, y: 100)
        )

        let result = ScreenRecordingEligibility.evaluate(
            selection: selection,
            displays: [displayA]
        )

        XCTAssertEqual(result, .eligible(display: displayA))
    }

    func testNoIntersectingDisplayIsDisabledAsCrossDisplay() {
        // 选区位于所有显示器之外（理论上不应发生），按跨显示器禁用。
        let rect = CGRect(x: -5000, y: -5000, width: 200, height: 200)

        let result = ScreenRecordingEligibility.evaluate(
            selectionRect: rect,
            displays: [displayA]
        )

        XCTAssertEqual(result, .disabled(reason: .crossDisplay))
    }
}

private func makeDisplay(id: CGDirectDisplayID, frame: CGRect) -> ScreenshotDisplay {
    ScreenshotDisplay(
        id: id,
        name: "Display \(id)",
        frame: frame,
        overlayFrame: frame,
        scale: 2,
        isPrimary: id == 1
    )
}
