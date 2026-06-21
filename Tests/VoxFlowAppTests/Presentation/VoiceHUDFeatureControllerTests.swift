import XCTest
@testable import VoxFlowApp

@MainActor
final class VoiceHUDFeatureControllerTests: XCTestCase {
    func testDictationStateMapsToHUDSnapshots() {
        XCTAssertEqual(
            VoiceHUDFeatureController.snapshot(
                state: .recording,
                activeVoiceAction: .dictation,
                shouldShowWaitingIndicator: false
            ),
            .recording(action: .dictation)
        )
        XCTAssertEqual(
            VoiceHUDFeatureController.snapshot(
                state: .waitingForFinal,
                activeVoiceAction: .dictation,
                shouldShowWaitingIndicator: true
            ),
            .waitingForFinal(showIndicator: true)
        )
        XCTAssertEqual(
            VoiceHUDFeatureController.snapshot(
                state: .injecting,
                activeVoiceAction: .dictation,
                shouldShowWaitingIndicator: false
            ),
            .inserting
        )
    }

    func testASRPresentationPhaseMapsToHUDSnapshots() {
        XCTAssertEqual(
            VoiceHUDFeatureController.snapshot(phase: .preparing),
            .preparing
        )
        XCTAssertEqual(
            VoiceHUDFeatureController.snapshot(phase: .recognizing(text: "partial")),
            .recognizing(text: "partial")
        )
        XCTAssertEqual(
            VoiceHUDFeatureController.snapshot(phase: .waitingForFinal(text: "")),
            .finalizing(text: "")
        )
        XCTAssertEqual(
            VoiceHUDFeatureController.snapshot(phase: .completed(text: "final")),
            .completed(text: "final")
        )
    }

    func testAgentComposeStageRendersThroughSnapshot() {
        let overlay = CapturingHUDOverlay()
        let controller = VoiceHUDFeatureController(overlay: overlay)

        controller.render(.agentComposeStage(.generating))

        XCTAssertEqual(overlay.events, [
            .updateAgentComposeStatus(.generating),
            .showWithoutReset,
        ])
    }

    func testStreamingTranscriptionAndAudioLevelRenderThroughSnapshots() {
        let overlay = CapturingHUDOverlay()
        let controller = VoiceHUDFeatureController(overlay: overlay)

        controller.render(.transcription(text: "hello", isRefining: false))
        controller.render(.streamingText("partial"))
        controller.render(.audioLevel(0.4))

        XCTAssertEqual(overlay.events, [
            .updateTranscription(text: "hello", isRefining: false),
            .updateStreamingText("partial"),
            .updateRMS(0.4),
        ])
    }

    func testDictationRecordingShowsDefaultHUDAndClearsText() {
        let overlay = CapturingHUDOverlay()
        let controller = VoiceHUDFeatureController(overlay: overlay)

        controller.handleState(
            .recording,
            activeVoiceAction: .dictation,
            shouldShowWaitingIndicator: false
        )

        XCTAssertEqual(overlay.events, [
            .show,
            .updateTranscription(text: "", isRefining: false),
        ])
    }

    func testAgentComposeRecordingKeepsExistingHUDStage() {
        let overlay = CapturingHUDOverlay()
        let controller = VoiceHUDFeatureController(overlay: overlay)

        controller.handleAgentComposeStage(.readingWindow)
        controller.handleState(
            .recording,
            activeVoiceAction: .agentCompose,
            shouldShowWaitingIndicator: false
        )

        XCTAssertEqual(overlay.events, [
            .updateAgentComposeStatus(.readingWindow),
            .showWithoutReset,
            .showWithoutReset,
        ])
    }

    func testAgentDispatchRecordingShowsDefaultHUDAndClearsText() {
        let overlay = CapturingHUDOverlay()
        let controller = VoiceHUDFeatureController(overlay: overlay)

        controller.handleState(
            .recording,
            activeVoiceAction: .agentDispatch,
            shouldShowWaitingIndicator: false
        )

        XCTAssertEqual(overlay.events, [
            .show,
            .updateTranscription(text: "", isRefining: false),
        ])
    }

    func testAgentDispatchListeningPresentationKeepsDefaultRecordingHUD() {
        let overlay = CapturingHUDOverlay()
        let controller = VoiceHUDFeatureController(overlay: overlay)

        controller.handleAgentDispatch(.listening(agentNames: ["voice-input-method-mac"]))

        XCTAssertEqual(overlay.events, [
            .show,
            .updateTranscription(text: "", isRefining: false),
        ])
    }

    func testWaitingForFinalShowsIndicatorOnlyWhenRequested() {
        let overlay = CapturingHUDOverlay()
        let controller = VoiceHUDFeatureController(overlay: overlay)

        controller.handleState(
            .waitingForFinal,
            activeVoiceAction: .dictation,
            shouldShowWaitingIndicator: false
        )
        controller.handleState(
            .waitingForFinal,
            activeVoiceAction: .dictation,
            shouldShowWaitingIndicator: true
        )

        XCTAssertEqual(overlay.events, [
            .updateTranscription(text: "正在识别...", isRefining: true),
        ])
    }

    func testProcessingShowsLoadingIndicatorImmediately() {
        let overlay = CapturingHUDOverlay()
        let controller = VoiceHUDFeatureController(overlay: overlay)

        controller.handleState(
            .processing,
            activeVoiceAction: .dictation,
            shouldShowWaitingIndicator: true
        )

        XCTAssertEqual(overlay.events, [
            .showWithoutReset,
            .updateTranscription(text: "正在处理...", isRefining: true),
        ])
    }

    func testInjectingShowsWritingStateAndTerminalStatesDismissHUD() {
        let overlay = CapturingHUDOverlay()
        let controller = VoiceHUDFeatureController(overlay: overlay)

        controller.handleState(.injecting, activeVoiceAction: nil, shouldShowWaitingIndicator: false)
        controller.handleState(.idle, activeVoiceAction: nil, shouldShowWaitingIndicator: false)
        controller.handleState(.failed("error"), activeVoiceAction: nil, shouldShowWaitingIndicator: false)

        XCTAssertEqual(overlay.events, [
            .showWithoutReset,
            .updateTranscription(text: "正在写入...", isRefining: true),
            .dismiss,
            .dismiss,
        ])
    }

    func testStreamingAndTemporaryMessagesAreForwarded() {
        let overlay = CapturingHUDOverlay()
        let controller = VoiceHUDFeatureController(overlay: overlay)

        controller.updateTranscription("hello", isRefining: false)
        controller.processingStarted("hello")
        controller.updateStreamingText("partial")
        controller.updateRMS(0.4)
        controller.showTemporaryMessage("done", duration: 2.5)

        XCTAssertEqual(overlay.events, [
            .updateTranscription(text: "hello", isRefining: false),
            .updateTranscription(text: "hello", isRefining: true),
            .updateStreamingText("partial"),
            .updateRMS(0.4),
            .showTemporaryMessage(message: "done", duration: 2.5, tone: .info),
        ])
    }

    func testClipboardImageOCRSuccessUsesSuccessTone() {
        let overlay = CapturingHUDOverlay()
        let controller = VoiceHUDFeatureController(overlay: overlay)

        controller.handleWorkflowFeedback(.clipboardImageOCRSucceeded)

        XCTAssertEqual(overlay.events, [
            .showTemporaryMessage(
                message: "已识别图片文字并粘贴",
                duration: 2.2,
                tone: .success
            ),
        ])
    }

    func testAgentComposeOutputSuccessUsesSuccessTone() {
        let overlay = CapturingHUDOverlay()
        let controller = VoiceHUDFeatureController(overlay: overlay)

        controller.handleWorkflowFeedback(.agentComposeCopied)
        controller.handleWorkflowFeedback(.agentComposeInjected)

        XCTAssertEqual(overlay.events, [
            .showTemporaryMessage(
                message: "已生成并复制到剪贴板",
                duration: 2.5,
                tone: .success
            ),
            .showTemporaryMessage(
                message: "已生成并写入当前输入框",
                duration: 2.5,
                tone: .success
            ),
        ])
    }

    func testRecognitionErrorFeedbackOnlyBindsActionWhenActionable() {
        let overlay = CapturingHUDOverlay()
        let controller = VoiceHUDFeatureController(overlay: overlay)

        controller.handleRecognitionErrorFeedback(
            RecognitionErrorHUDFeedback(
                message: "没有检测到有效语音，请靠近麦克风再试一次。",
                duration: 2.4,
                isActionable: false
            )
        ) {
            XCTFail("Non-actionable recognition feedback should not keep an action")
        }
        controller.handleRecognitionErrorFeedback(
            RecognitionErrorHUDFeedback(
                message: "final timed out",
                duration: 8.0,
                isActionable: true
            )
        ) {}

        XCTAssertEqual(overlay.events, [
            .showTemporaryMessage(
                message: "没有检测到有效语音，请靠近麦克风再试一次。",
                duration: 2.4,
                tone: .info
            ),
            .showTemporaryMessage(
                message: "final timed out",
                duration: 8.0,
                tone: .info
            ),
        ])
        XCTAssertEqual(overlay.actionBindingCount, 1)
    }
}

@MainActor
private final class CapturingHUDOverlay: HUDOverlayControlling {
    enum Event: Equatable {
        case show
        case showWithoutReset
        case dismiss
        case updateTranscription(text: String, isRefining: Bool)
        case updateAgentComposeStatus(AgentComposeHUDStage)
        case updateAgentDispatch(AgentDispatchHUDPresentation)
        case updateStreamingText(String)
        case updateRMS(Float)
        case showTemporaryMessage(
            message: String,
            duration: TimeInterval,
            tone: HUDTemporaryMessageTone
        )
    }

    private(set) var events: [Event] = []
    private(set) var actionBindingCount = 0

    func show() {
        events.append(.show)
    }

    func showWithoutReset() {
        events.append(.showWithoutReset)
    }

    func dismiss() {
        events.append(.dismiss)
    }

    func updateTranscription(_ text: String, isRefining: Bool) {
        events.append(.updateTranscription(text: text, isRefining: isRefining))
    }

    func updateAgentComposeStatus(_ stage: AgentComposeHUDStage) {
        events.append(.updateAgentComposeStatus(stage))
    }

    func updateAgentDispatch(_ presentation: AgentDispatchHUDPresentation) {
        events.append(.updateAgentDispatch(presentation))
    }

    func updateStreamingText(_ partialText: String) {
        events.append(.updateStreamingText(partialText))
    }

    func updateRMS(_ rms: Float) {
        events.append(.updateRMS(rms))
    }

    func showTemporaryMessage(
        _ message: String,
        duration: TimeInterval,
        tone: HUDTemporaryMessageTone,
        action: (() -> Void)?
    ) {
        if action != nil {
            actionBindingCount += 1
        }
        events.append(.showTemporaryMessage(message: message, duration: duration, tone: tone))
    }
}
