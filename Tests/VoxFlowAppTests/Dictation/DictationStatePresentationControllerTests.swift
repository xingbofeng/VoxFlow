import XCTest
@testable import VoxFlowApp

@MainActor
final class DictationStatePresentationControllerTests: XCTestCase {
    func testRecordingStartsCancelMonitorAndHidesRefiningStatus() {
        let recorder = DictationStatePresentationRecorder()
        let controller = recorder.makeController()

        let result = controller.handle(.recording, activeVoiceAction: .dictation)

        XCTAssertFalse(result.shouldClearActiveVoiceAction)
        XCTAssertEqual(recorder.feedbackStates, [.recording])
        XCTAssertEqual(recorder.hudCalls, [
            .init(state: .recording, action: .dictation, showsWaitingIndicator: true)
        ])
        XCTAssertEqual(recorder.cancelMonitorEvents, ["start"])
        XCTAssertEqual(recorder.refiningVisibility, [false])
    }

    func testIdleClearsActiveActionStopsCancelMonitorAndHidesRefiningStatus() {
        let recorder = DictationStatePresentationRecorder()
        let controller = recorder.makeController()

        let result = controller.handle(.idle, activeVoiceAction: .agentCompose)

        XCTAssertTrue(result.shouldClearActiveVoiceAction)
        XCTAssertEqual(recorder.feedbackStates, [.idle])
        XCTAssertEqual(recorder.hudCalls, [
            .init(state: .idle, action: .agentCompose, showsWaitingIndicator: false)
        ])
        XCTAssertEqual(recorder.cancelMonitorEvents, ["stop"])
        XCTAssertEqual(recorder.refiningVisibility, [false])
    }

    func testProcessingShowsRefiningStatusWithoutChangingCancelMonitor() {
        let recorder = DictationStatePresentationRecorder()
        let controller = recorder.makeController()

        let result = controller.handle(.processing, activeVoiceAction: .dictation)

        XCTAssertFalse(result.shouldClearActiveVoiceAction)
        XCTAssertEqual(recorder.feedbackStates, [.processing])
        XCTAssertEqual(recorder.hudCalls, [
            .init(state: .processing, action: .dictation, showsWaitingIndicator: true)
        ])
        XCTAssertTrue(recorder.cancelMonitorEvents.isEmpty)
        XCTAssertEqual(recorder.refiningVisibility, [true])
    }

    func testInjectingAndFailedStopCancelMonitorAndHideRefiningStatus() {
        let recorder = DictationStatePresentationRecorder()
        let controller = recorder.makeController()

        let injectingResult = controller.handle(.injecting, activeVoiceAction: .dictation)
        let failedResult = controller.handle(.failed("boom"), activeVoiceAction: .dictation)

        XCTAssertFalse(injectingResult.shouldClearActiveVoiceAction)
        XCTAssertFalse(failedResult.shouldClearActiveVoiceAction)
        XCTAssertEqual(recorder.cancelMonitorEvents, ["stop", "stop"])
        XCTAssertEqual(recorder.refiningVisibility, [false, false])
    }
}

@MainActor
private final class DictationStatePresentationRecorder {
    var feedbackStates: [DictationState] = []
    var hudCalls: [HUDCall] = []
    var cancelMonitorEvents: [String] = []
    var refiningVisibility: [Bool] = []

    func makeController() -> DictationStatePresentationController {
        DictationStatePresentationController(
            handleFeedbackState: { [weak self] state in
                self?.feedbackStates.append(state)
            },
            handleHUDState: { [weak self] state, action, showsWaitingIndicator in
                self?.hudCalls.append(
                    HUDCall(
                        state: state,
                        action: action,
                        showsWaitingIndicator: showsWaitingIndicator
                    )
                )
            },
            shouldShowWaitingIndicator: { action in
                action == .dictation
            },
            startCancelMonitor: { [weak self] in
                self?.cancelMonitorEvents.append("start")
            },
            stopCancelMonitor: { [weak self] in
                self?.cancelMonitorEvents.append("stop")
            },
            setRefiningStatusVisible: { [weak self] isVisible in
                self?.refiningVisibility.append(isVisible)
            }
        )
    }
}

private struct HUDCall: Equatable {
    let state: DictationState
    let action: VoiceAction?
    let showsWaitingIndicator: Bool
}
