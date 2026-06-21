import Foundation
import XCTest
@testable import VoxFlowApp

final class VoiceTaskModelTests: XCTestCase {
    // MARK: - VoiceTaskMode

    func testVoiceTaskModeRawValues() {
        XCTAssertEqual(VoiceTaskMode.dictation.rawValue, "dictation")
        XCTAssertEqual(VoiceTaskMode.agentCompose.rawValue, "agentCompose")
        XCTAssertEqual(VoiceTaskMode.agentDispatch.rawValue, "agentDispatch")
    }

    // MARK: - VoiceTaskStage

    func testVoiceTaskStageRawValues() {
        XCTAssertEqual(VoiceTaskStage.recording.rawValue, "recording")
        XCTAssertEqual(VoiceTaskStage.transcribing.rawValue, "transcribing")
        XCTAssertEqual(VoiceTaskStage.collectingContext.rawValue, "collectingContext")
        XCTAssertEqual(VoiceTaskStage.processing.rawValue, "processing")
        XCTAssertEqual(VoiceTaskStage.outputting.rawValue, "outputting")
    }

    func testVoiceTaskStageOrdering() {
        XCTAssertLessThan(VoiceTaskStage.recording, VoiceTaskStage.transcribing)
        XCTAssertLessThan(VoiceTaskStage.transcribing, VoiceTaskStage.collectingContext)
        XCTAssertLessThan(VoiceTaskStage.collectingContext, VoiceTaskStage.processing)
        XCTAssertLessThan(VoiceTaskStage.processing, VoiceTaskStage.outputting)
    }

    func testVoiceTaskStageAdvancementIsValid() throws {
        let forwardPairs: [(VoiceTaskStage, VoiceTaskStage)] = [
            (.recording, .transcribing),
            (.transcribing, .collectingContext),
            (.collectingContext, .processing),
            (.processing, .outputting),
        ]
        for (from, to) in forwardPairs {
            XCTAssertNoThrow(try from.validateAdvancement(to: to),
                             "\(from) -> \(to) should be valid")
        }
        // Skipping stages forward is also valid
        XCTAssertNoThrow(try VoiceTaskStage.recording.validateAdvancement(to: .processing))
        XCTAssertNoThrow(try VoiceTaskStage.recording.validateAdvancement(to: .outputting))
        // Same stage is valid (idempotent)
        XCTAssertNoThrow(try VoiceTaskStage.recording.validateAdvancement(to: .recording))
    }

    func testVoiceTaskStageBackwardsTransitionIsRejected() {
        let backwardPairs: [(VoiceTaskStage, VoiceTaskStage)] = [
            (.transcribing, .recording),
            (.collectingContext, .transcribing),
            (.processing, .collectingContext),
            (.outputting, .processing),
            (.outputting, .recording),
        ]
        for (from, to) in backwardPairs {
            XCTAssertThrowsError(try from.validateAdvancement(to: to),
                                 "\(from) -> \(to) should throw") { error in
                guard case VoiceTaskError.backwardsStageTransition = error else {
                    XCTFail("Expected backwardsStageTransition, got \(error)")
                    return
                }
            }
        }
    }

    // MARK: - VoiceTaskStatus

    func testVoiceTaskStatusRawValues() {
        XCTAssertEqual(VoiceTaskStatus.inProgress.rawValue, "inProgress")
        XCTAssertEqual(VoiceTaskStatus.completed.rawValue, "completed")
        XCTAssertEqual(VoiceTaskStatus.partiallyCompleted.rawValue, "partiallyCompleted")
        XCTAssertEqual(VoiceTaskStatus.failed.rawValue, "failed")
        XCTAssertEqual(VoiceTaskStatus.cancelled.rawValue, "cancelled")
    }

    // MARK: - VoiceTaskFailure

    func testVoiceTaskFailureCoding() throws {
        let failure = VoiceTaskFailure(
            stage: "transcribing",
            code: "ASR_TIMEOUT",
            message: "Speech recognition timed out",
            recoverable: true
        )

        let data = try JSONEncoder().encode(failure)
        let decoded = try JSONDecoder().decode(VoiceTaskFailure.self, from: data)

        XCTAssertEqual(decoded, failure)
    }

    // MARK: - OutputResult

    func testOutputResultCoding() throws {
        let cases: [OutputResult] = [
            .injected,
            .copied,
            .targetChanged(reason: "Window changed"),
            .permissionDenied(reason: "Accessibility denied"),
            .injectionFailed(reason: "Clipboard unavailable"),
            .copyFailed(reason: "Pasteboard write failed"),
            .cancelled,
        ]
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for value in cases {
            let data = try encoder.encode(value)
            let decoded = try decoder.decode(OutputResult.self, from: data)
            XCTAssertEqual(decoded, value, "Round-trip failed for \(value)")
        }
    }

    func testOutputResultIsEquatable() {
        XCTAssertEqual(OutputResult.injected, OutputResult.injected)
        XCTAssertEqual(OutputResult.copied, OutputResult.copied)
        XCTAssertEqual(OutputResult.cancelled, OutputResult.cancelled)
        XCTAssertEqual(
            OutputResult.permissionDenied(reason: "a"),
            OutputResult.permissionDenied(reason: "a")
        )
        XCTAssertEqual(
            OutputResult.injectionFailed(reason: "a"),
            OutputResult.injectionFailed(reason: "a")
        )
        XCTAssertNotEqual(OutputResult.injected, OutputResult.copied)
        XCTAssertNotEqual(
            OutputResult.injectionFailed(reason: "a"),
            OutputResult.injectionFailed(reason: "b")
        )
        XCTAssertNotEqual(
            OutputResult.injectionFailed(reason: "a"),
            OutputResult.copyFailed(reason: "a")
        )
        XCTAssertNotEqual(
            OutputResult.permissionDenied(reason: "a"),
            OutputResult.injectionFailed(reason: "a")
        )
    }
}
