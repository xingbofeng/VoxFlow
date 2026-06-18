import XCTest
@testable import VoxFlowApp

@MainActor
final class HotKeyDecisionPerformerTests: XCTestCase {
    func testIgnoreDoesNotInvokeAnyAction() {
        let recorder = HotKeyDecisionRecorder()
        let performer = recorder.makePerformer()

        performer.perform(.ignore)

        XCTAssertTrue(recorder.events.isEmpty)
    }

    func testNotesDecisionsInvokeNotesActions() {
        let recorder = HotKeyDecisionRecorder()
        let performer = recorder.makePerformer()

        performer.perform(.startNotesRecording)
        performer.perform(.finishNotesRecording)

        XCTAssertEqual(recorder.events, [
            .startNotesRecording,
            .finishNotesRecording
        ])
    }

    func testDictationDecisionsForwardVoiceActions() {
        let recorder = HotKeyDecisionRecorder()
        let performer = recorder.makePerformer()

        performer.perform(.startDictation(.dictation))
        performer.perform(.releaseDictation(.agentCompose))

        XCTAssertEqual(recorder.events, [
            .startDictation(.dictation),
            .releaseDictation(.agentCompose)
        ])
    }
}

@MainActor
private final class HotKeyDecisionRecorder {
    private(set) var events: [HotKeyDecisionEvent] = []

    func makePerformer() -> HotKeyDecisionPerformer {
        HotKeyDecisionPerformer(
            startNotesRecording: { [weak self] in
                self?.events.append(.startNotesRecording)
            },
            finishNotesRecording: { [weak self] in
                self?.events.append(.finishNotesRecording)
            },
            startDictation: { [weak self] action in
                self?.events.append(.startDictation(action))
            },
            releaseDictation: { [weak self] action in
                self?.events.append(.releaseDictation(action))
            }
        )
    }
}

private enum HotKeyDecisionEvent: Equatable {
    case startNotesRecording
    case finishNotesRecording
    case startDictation(VoiceAction)
    case releaseDictation(VoiceAction)
}
