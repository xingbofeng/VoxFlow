import XCTest
@testable import VoxFlowApp

@MainActor
final class VoiceHUDFeatureControllerTests: XCTestCase {
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

    func testTerminalStatesDismissHUD() {
        let overlay = CapturingHUDOverlay()
        let controller = VoiceHUDFeatureController(overlay: overlay)

        controller.handleState(.idle, activeVoiceAction: nil, shouldShowWaitingIndicator: false)
        controller.handleState(.injecting, activeVoiceAction: nil, shouldShowWaitingIndicator: false)
        controller.handleState(.failed("error"), activeVoiceAction: nil, shouldShowWaitingIndicator: false)

        XCTAssertEqual(overlay.events, [.dismiss, .dismiss, .dismiss])
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
            .showTemporaryMessage(message: "done", duration: 2.5),
        ])
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
        case updateStreamingText(String)
        case updateRMS(Float)
        case showTemporaryMessage(message: String, duration: TimeInterval)
    }

    private(set) var events: [Event] = []

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

    func updateStreamingText(_ partialText: String) {
        events.append(.updateStreamingText(partialText))
    }

    func updateRMS(_ rms: Float) {
        events.append(.updateRMS(rms))
    }

    func showTemporaryMessage(
        _ message: String,
        duration: TimeInterval,
        action: (() -> Void)?
    ) {
        events.append(.showTemporaryMessage(message: message, duration: duration))
    }
}
