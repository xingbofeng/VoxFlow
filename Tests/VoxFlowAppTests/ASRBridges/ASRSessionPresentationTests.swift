import VoxFlowASRCore
import XCTest
@testable import VoxFlowApp

@MainActor
final class ASRSessionPresentationTests: XCTestCase {
    func testReducerDistinguishesPreparingRecognizingWaitingForFinalCompletedAndFailed() {
        let sessionID = ASRSessionID(rawValue: "presentation-session")
        var reducer = ASRSessionPresentationReducer(sessionID: sessionID)

        XCTAssertEqual(
            reducer.apply(.preparing(sessionID: sessionID, revision: 0)),
            .preparing
        )
        XCTAssertEqual(
            reducer.apply(.ready(sessionID: sessionID, revision: 1)),
            .recognizing(text: "")
        )
        XCTAssertEqual(
            reducer.apply(Self.partial(sessionID: sessionID, text: "hello", revision: 2)),
            .recognizing(text: "hello")
        )
        XCTAssertEqual(
            reducer.waitForFinal(),
            .waitingForFinal(text: "hello")
        )
        XCTAssertEqual(
            reducer.apply(.final(sessionID: sessionID, revision: 3, text: "hello world")),
            .completed(text: "hello world")
        )
        XCTAssertEqual(
            reducer.apply(
                .failure(
                    sessionID: sessionID,
                    revision: 4,
                    error: ASRError(category: .finalTimeout, message: "final timed out")
                )
            ),
            .failed(message: "final timed out")
        )
    }

    func testReducerShowsFriendlyMessageForEmptyTranscriptFailure() {
        let sessionID = ASRSessionID(rawValue: "empty-transcript-session")
        var reducer = ASRSessionPresentationReducer(sessionID: sessionID)

        XCTAssertEqual(
            reducer.apply(
                .failure(
                    sessionID: sessionID,
                    revision: 1,
                    error: ASRError(
                        category: .emptyTranscript,
                        message: "Qwen3-ASR final result was empty."
                    )
                )
            ),
            .failed(message: "没有检测到有效语音，请靠近麦克风再试一次。")
        )
    }

    func testASRCoreBackedEngineErrorShowsFriendlyMessageForEmptyTranscriptFailure() {
        let error = ASRCoreBackedASREngineError.failure(
            ASRError(
                category: .emptyTranscript,
                message: "Qwen3-ASR final result was empty."
            )
        )

        XCTAssertEqual(error.localizedDescription, "没有检测到有效语音，请靠近麦克风再试一次。")
    }

    func testEmptyTranscriptErrorUsesShortNonActionableHUDFeedback() {
        let feedback = RecognitionErrorHUDPresentation.feedback(
            for: ASRCoreBackedASREngineError.failure(
                ASRError(
                    category: .emptyTranscript,
                    message: "Qwen3-ASR final result was empty."
                )
            ),
            recovery: .openMainWindow
        )

        XCTAssertEqual(feedback.message, "没有检测到有效语音，请靠近麦克风再试一次。")
        XCTAssertEqual(feedback.duration, 2.4)
        XCTAssertFalse(feedback.isActionable)
    }

    func testGeneralRecognitionErrorKeepsActionableRecoveryFeedback() {
        let feedback = RecognitionErrorHUDPresentation.feedback(
            for: ASRCoreBackedASREngineError.failure(
                ASRError(category: .finalTimeout, message: "final timed out")
            ),
            recovery: .openMainWindow
        )

        XCTAssertEqual(feedback.message, "final timed out")
        XCTAssertEqual(feedback.duration, 8.0)
        XCTAssertTrue(feedback.isActionable)
    }

    func testReducerIgnoresOtherSessionsAndOldRevisionsWithoutChangingPhase() {
        let sessionID = ASRSessionID(rawValue: "current-session")
        var reducer = ASRSessionPresentationReducer(sessionID: sessionID)

        XCTAssertEqual(
            reducer.apply(Self.partial(sessionID: sessionID, text: "current", revision: 2)),
            .recognizing(text: "current")
        )
        XCTAssertNil(
            reducer.apply(Self.partial(sessionID: ASRSessionID(rawValue: "old-session"), text: "old", revision: 3))
        )
        XCTAssertNil(
            reducer.apply(Self.partial(sessionID: sessionID, text: "stale", revision: 1))
        )
        XCTAssertEqual(reducer.phase, .recognizing(text: "current"))
    }

    func testRouterIgnoresLateEventsFromPreviousActiveSession() {
        let oldSessionID = ASRSessionID(rawValue: "old-session")
        let currentSessionID = ASRSessionID(rawValue: "current-session")
        var router = ASRSessionPresentationRouter()

        router.beginSession(oldSessionID)
        XCTAssertEqual(
            router.apply(Self.partial(sessionID: oldSessionID, text: "old partial", revision: 1)),
            .recognizing(text: "old partial")
        )

        router.beginSession(currentSessionID)
        XCTAssertNil(
            router.apply(.final(sessionID: oldSessionID, revision: 2, text: "late old final"))
        )
        XCTAssertEqual(router.phase, .idle)
        XCTAssertEqual(
            router.apply(Self.partial(sessionID: currentSessionID, text: "current partial", revision: 1)),
            .recognizing(text: "current partial")
        )
        XCTAssertEqual(router.phase, .recognizing(text: "current partial"))
    }

    func testHUDControllerMapsASRPresentationPhasesToDistinctOverlayActions() {
        let overlay = CapturingASRSessionHUDOverlay()
        let controller = VoiceHUDFeatureController(overlay: overlay)

        controller.handleASRPresentation(.preparing)
        controller.handleASRPresentation(.recognizing(text: "partial text"))
        controller.handleASRPresentation(.waitingForFinal(text: "partial text"))
        controller.handleASRPresentation(.failed(message: "network down"))

        XCTAssertEqual(overlay.events, [
            .show,
            .updateTranscription(text: "准备识别...", isRefining: true),
            .show,
            .updateStreamingText("partial text"),
            .updateTranscription(text: "partial text", isRefining: true),
            .showTemporaryMessage(message: "network down", duration: 6.0, tone: .info),
        ])
    }

    private static func partial(
        sessionID: ASRSessionID,
        text: String,
        revision: UInt64
    ) -> ASREvent {
        .partial(
            sessionID: sessionID,
            transcript: PartialTranscript(
                stablePrefix: "",
                unstableSuffix: text,
                revision: revision,
                audioDuration: .zero
            )
        )
    }
}

@MainActor
private final class CapturingASRSessionHUDOverlay: HUDOverlayControlling {
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
        events.append(.showTemporaryMessage(message: message, duration: duration, tone: tone))
    }
}
