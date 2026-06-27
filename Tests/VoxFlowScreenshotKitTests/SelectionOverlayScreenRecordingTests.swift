import XCTest
import CoreGraphics
@testable import VoxFlowScreenshotKit

@MainActor
final class SelectionOverlayScreenRecordingTests: XCTestCase {
    func testScreenRecordingActionEntersPreparationForSingleDisplay() {
        let display = ScreenshotDisplay(
            id: 1,
            name: "Built-in",
            frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            scale: 2,
            isPrimary: true
        )
        let factory = FakeSelectionOverlayWindowFactory()
        var results: [SelectionOverlayResult] = []
        let controller = SelectionOverlayController(windowFactory: factory) { result in
            results.append(result)
        }
        controller.present(displays: [display])

        controller.beginSelection(on: display.id, at: CGPoint(x: 300, y: 220))
        controller.updateSelection(to: CGPoint(x: 120, y: 80))

        controller.handleToolbarRole(.screenRecording)

        XCTAssertTrue(results.isEmpty)
        XCTAssertEqual(factory.windows.first?.closeCallCount, 0)
        XCTAssertEqual(
            factory.windows.first?.annotationStates.last?.screenRecordingPreparation?.audioMode,
            ScreenRecordingAudioMode.none
        )
        XCTAssertEqual(factory.windows.first?.annotationStates.last?.shouldShowToolbar, false)
    }

    func testScreenRecordingPreparationStartEmitsSelectionResultForSingleDisplay() {
        let display = ScreenshotDisplay(
            id: 1,
            name: "Built-in",
            frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            scale: 2,
            isPrimary: true
        )
        let factory = FakeSelectionOverlayWindowFactory()
        var results: [SelectionOverlayResult] = []
        let controller = SelectionOverlayController(windowFactory: factory) { result in
            results.append(result)
        }
        controller.present(displays: [display])

        controller.beginSelection(on: display.id, at: CGPoint(x: 300, y: 220))
        controller.updateSelection(to: CGPoint(x: 120, y: 80))
        controller.handleToolbarRole(.screenRecording)
        controller.handleScreenRecordingPreparationStart()

        let expectedState = SelectionState(
            displayFrame: display.frame,
            displayScale: 2,
            startPoint: CGPoint(x: 300, y: 220),
            currentPoint: CGPoint(x: 120, y: 80)
        )
        XCTAssertEqual(results, [.acceptedScreenRecording(expectedState, display, .none)])
        // overlay 不在点击开始时立即关闭；app 层会在倒计时结束、采集开始前关闭。
        XCTAssertEqual(factory.windows.first?.closeCallCount, 0)
    }

    func testScreenRecordingExclusionWindowIDsComeFromOverlayWindows() {
        let primaryDisplay = ScreenshotDisplay(
            id: 1,
            name: "Built-in",
            frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            scale: 2,
            isPrimary: true
        )
        let externalDisplay = ScreenshotDisplay(
            id: 2,
            name: "External",
            frame: CGRect(x: 1440, y: 0, width: 1024, height: 768),
            scale: 1,
            isPrimary: false
        )
        let factory = FakeSelectionOverlayWindowFactory()
        let controller = SelectionOverlayController(windowFactory: factory)

        controller.present(displays: [primaryDisplay, externalDisplay])

        XCTAssertEqual(controller.currentScreenCaptureExclusionWindowIDs(), [1_000, 1_001])
    }

    func testScreenRecordingPreparationCanSelectMicrophoneMode() {
        let display = ScreenshotDisplay(
            id: 1,
            name: "Built-in",
            frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            scale: 2,
            isPrimary: true
        )
        let factory = FakeSelectionOverlayWindowFactory()
        var results: [SelectionOverlayResult] = []
        let controller = SelectionOverlayController(windowFactory: factory) { result in
            results.append(result)
        }
        controller.present(displays: [display])

        controller.beginSelection(on: display.id, at: CGPoint(x: 300, y: 220))
        controller.updateSelection(to: CGPoint(x: 120, y: 80))
        controller.handleToolbarRole(.screenRecording)
        controller.setScreenRecordingPreparationAudioMode(.microphone)
        controller.handleScreenRecordingPreparationStart()

        let expectedState = SelectionState(
            displayFrame: display.frame,
            displayScale: 2,
            startPoint: CGPoint(x: 300, y: 220),
            currentPoint: CGPoint(x: 120, y: 80)
        )
        XCTAssertEqual(results, [.acceptedScreenRecording(expectedState, display, .microphone)])
    }

    func testScreenRecordingPreparationActionEventStartsWithSelectedAudioMode() {
        let display = ScreenshotDisplay(
            id: 1,
            name: "Built-in",
            frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            scale: 2,
            isPrimary: true
        )
        let factory = FakeSelectionOverlayWindowFactory()
        var results: [SelectionOverlayResult] = []
        let controller = SelectionOverlayController(windowFactory: factory) { result in
            results.append(result)
        }
        controller.present(displays: [display])

        controller.beginSelection(on: display.id, at: CGPoint(x: 300, y: 220))
        controller.updateSelection(to: CGPoint(x: 120, y: 80))
        controller.handleToolbarRole(.screenRecording)
        factory.windows.first?.emit(.screenRecordingPreparationAction(.audioMode(.microphone)))
        factory.windows.first?.emit(.screenRecordingPreparationAction(.start))

        let expectedState = SelectionState(
            displayFrame: display.frame,
            displayScale: 2,
            startPoint: CGPoint(x: 300, y: 220),
            currentPoint: CGPoint(x: 120, y: 80)
        )
        XCTAssertEqual(results, [.acceptedScreenRecording(expectedState, display, .microphone)])
        XCTAssertEqual(factory.windows.first?.closeCallCount, 0)
    }

    func testScreenRecordingCountdownUpdatesPreparationStateWithoutClosingOverlay() {
        let display = ScreenshotDisplay(
            id: 1,
            name: "Built-in",
            frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            scale: 2,
            isPrimary: true
        )
        let factory = FakeSelectionOverlayWindowFactory()
        let controller = SelectionOverlayController(windowFactory: factory)
        controller.present(displays: [display])

        controller.beginSelection(on: display.id, at: CGPoint(x: 300, y: 220))
        controller.updateSelection(to: CGPoint(x: 120, y: 80))
        controller.handleToolbarRole(.screenRecording)
        controller.updateScreenRecordingCountdown(3)

        let preparation = factory.windows.first?.annotationStates.last?.screenRecordingPreparation
        XCTAssertEqual(preparation?.audioMode, ScreenRecordingAudioMode.none)
        XCTAssertEqual(preparation?.countdownRemaining, 3)
        XCTAssertEqual(factory.windows.first?.closeCallCount, 0)
    }

    func testActiveScreenRecordingOverlayKeepsSelectionFrameAndPassesMouseThrough() {
        let display = ScreenshotDisplay(
            id: 1,
            name: "Built-in",
            frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            scale: 2,
            isPrimary: true
        )
        let factory = FakeSelectionOverlayWindowFactory()
        let controller = SelectionOverlayController(windowFactory: factory)
        controller.present(displays: [display])

        controller.beginSelection(on: display.id, at: CGPoint(x: 300, y: 220))
        controller.updateSelection(to: CGPoint(x: 120, y: 80))
        controller.handleToolbarRole(.screenRecording)
        controller.enterActiveScreenRecordingOverlay()

        XCTAssertNil(factory.windows.first?.annotationStates.last?.screenRecordingPreparation)
        XCTAssertEqual(factory.windows.first?.scrollCaptureStates.last, true)
        XCTAssertEqual(factory.windows.first?.selectionStates.compactMap { $0 }.last?.normalizedRect,
                       CGRect(x: 120, y: 80, width: 180, height: 140))
        XCTAssertEqual(factory.windows.first?.closeCallCount, 0)
    }

    func testScreenRecordingPreparationCanBeCancelledWithoutEmittingResult() {
        let display = ScreenshotDisplay(
            id: 1,
            name: "Built-in",
            frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            scale: 2,
            isPrimary: true
        )
        let factory = FakeSelectionOverlayWindowFactory()
        var results: [SelectionOverlayResult] = []
        let controller = SelectionOverlayController(windowFactory: factory) { result in
            results.append(result)
        }
        controller.present(displays: [display])

        controller.beginSelection(on: display.id, at: CGPoint(x: 300, y: 220))
        controller.updateSelection(to: CGPoint(x: 120, y: 80))
        controller.handleToolbarRole(.screenRecording)
        controller.cancelScreenRecordingPreparation()

        XCTAssertTrue(results.isEmpty)
        XCTAssertNil(factory.windows.first?.annotationStates.last?.screenRecordingPreparation)
        XCTAssertEqual(factory.windows.first?.annotationStates.last?.shouldShowToolbar, true)
        XCTAssertEqual(factory.windows.first?.closeCallCount, 0)
    }

    func testScreenRecordingActionDoesNotEmitForCrossDisplaySelection() {
        let displays = [
            ScreenshotDisplay(
                id: 1, name: "Left",
                frame: CGRect(x: 0, y: 0, width: 100, height: 100),
                scale: 1, isPrimary: true
            ),
            ScreenshotDisplay(
                id: 2, name: "Right",
                frame: CGRect(x: 100, y: 0, width: 100, height: 100),
                scale: 1, isPrimary: false
            )
        ]
        let factory = FakeSelectionOverlayWindowFactory()
        var results: [SelectionOverlayResult] = []
        let controller = SelectionOverlayController(windowFactory: factory) { result in
            results.append(result)
        }
        controller.present(displays: displays)

        // 选区跨越两个显示器边界（20..150），尺寸足够但跨显示器。
        controller.beginSelection(on: displays[0].id, at: CGPoint(x: 20, y: 10))
        controller.updateSelection(to: CGPoint(x: 150, y: 80))

        controller.handleToolbarRole(.screenRecording)

        // 录屏被禁用，不回传结果，且不影响 overlay 仍可继续截图操作。
        XCTAssertTrue(results.isEmpty)
    }

    func testScreenRecordingActionDoesNotEmitForTinySelection() {
        let display = ScreenshotDisplay(
            id: 1, name: "Built-in",
            frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            scale: 2, isPrimary: true
        )
        let factory = FakeSelectionOverlayWindowFactory()
        var results: [SelectionOverlayResult] = []
        let controller = SelectionOverlayController(windowFactory: factory) { result in
            results.append(result)
        }
        controller.present(displays: [display])

        // 选区 30×30，小于最小录屏尺寸。
        controller.beginSelection(on: display.id, at: CGPoint(x: 130, y: 130))
        controller.updateSelection(to: CGPoint(x: 100, y: 100))

        controller.handleToolbarRole(.screenRecording)

        XCTAssertTrue(results.isEmpty)
    }

    func testScreenshotCompleteStillWorksAlongsideScreenRecordingRole() {
        let display = ScreenshotDisplay(
            id: 1, name: "Built-in",
            frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            scale: 2, isPrimary: true
        )
        let factory = FakeSelectionOverlayWindowFactory()
        var results: [SelectionOverlayResult] = []
        let controller = SelectionOverlayController(windowFactory: factory) { result in
            results.append(result)
        }
        controller.present(displays: [display])

        controller.beginSelection(on: display.id, at: CGPoint(x: 300, y: 220))
        controller.updateSelection(to: CGPoint(x: 120, y: 80))

        // 截图完成动作不受新增录屏 role 影响。
        controller.handleToolbarRole(.complete)

        XCTAssertEqual(results.count, 1)
        if case .accepted = results.first {

        } else {
            XCTFail("expected .accepted result, got \(String(describing: results.first))")
        }
    }
}
