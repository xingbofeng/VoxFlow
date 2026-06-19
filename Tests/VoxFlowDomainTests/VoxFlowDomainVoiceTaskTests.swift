import Foundation
import XCTest
import VoxFlowDomain

final class VoxFlowDomainVoiceTaskTests: XCTestCase {
    func testVoiceTaskTypesAreAvailableFromDomainTarget() throws {
        XCTAssertEqual(VoiceTaskMode.dictation.rawValue, "dictation")
        XCTAssertEqual(VoiceTaskMode.agentCompose.rawValue, "agentCompose")

        XCTAssertLessThan(VoiceTaskStage.recording, VoiceTaskStage.transcribing)
        XCTAssertLessThan(VoiceTaskStage.transcribing, VoiceTaskStage.collectingContext)
        XCTAssertLessThan(VoiceTaskStage.collectingContext, VoiceTaskStage.processing)
        XCTAssertLessThan(VoiceTaskStage.processing, VoiceTaskStage.outputting)
        XCTAssertNoThrow(try VoiceTaskStage.recording.validateAdvancement(to: .outputting))

        XCTAssertEqual(VoiceTaskStatus.inProgress.rawValue, "inProgress")
        XCTAssertEqual(VoiceTaskStatus.partiallyCompleted.rawValue, "partiallyCompleted")

        let task = VoiceTask(
            id: "task-1",
            mode: .agentCompose,
            stage: .collectingContext,
            status: .inProgress,
            targetAppBundleID: "com.example.Editor",
            targetAppName: "Editor",
            targetAppPID: 42,
            targetWindowID: "window-1",
            targetWindowTitle: "Notes.swift",
            audioRelativePath: "voice-tasks/task-1.wav",
            rawTranscript: "raw",
            contextJson: "{\"source\":\"selectedText\"}",
            finalText: "final",
            outputResult: "copied",
            failureJson: nil,
            warnings: ["context_truncated"],
            trace: "{\"events\":[]}",
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 2),
            completedAt: nil
        )

        XCTAssertEqual(task.id, "task-1")
        XCTAssertEqual(task.mode, .agentCompose)
        XCTAssertEqual(task.stage, .collectingContext)
        XCTAssertEqual(task.status, .inProgress)
        XCTAssertEqual(task.warnings, ["context_truncated"])
    }

    func testVoiceTaskCodableSupportTypesRoundTripFromDomainTarget() throws {
        let failure = VoiceTaskFailure(
            stage: "transcribing",
            code: "ASR_TIMEOUT",
            message: "Speech recognition timed out",
            recoverable: true
        )
        let failureData = try JSONEncoder().encode(failure)
        let decodedFailure = try JSONDecoder().decode(VoiceTaskFailure.self, from: failureData)
        XCTAssertEqual(decodedFailure, failure)

        let outputCases: [OutputResult] = [
            .injected,
            .copied,
            .targetChanged(reason: "window changed"),
            .permissionDenied(reason: "accessibility denied"),
            .injectionFailed(reason: "pasteboard unavailable"),
            .copyFailed(reason: "write failed"),
            .cancelled,
        ]

        for outputResult in outputCases {
            let data = try JSONEncoder().encode(outputResult)
            let decoded = try JSONDecoder().decode(OutputResult.self, from: data)
            XCTAssertEqual(decoded, outputResult)
        }
    }

    func testOutputResultKindDistinguishesRecoverableOutputOutcomes() {
        XCTAssertEqual(OutputResult.injected.kind, .inserted)
        XCTAssertEqual(OutputResult.copied.kind, .copied)
        XCTAssertEqual(
            OutputResult.targetChanged(reason: "window changed").kind,
            .targetChanged
        )
        XCTAssertEqual(
            OutputResult.permissionDenied(reason: "accessibility denied").kind,
            .permissionDenied
        )
        XCTAssertEqual(
            OutputResult.injectionFailed(reason: "event failed").kind,
            .failed
        )
        XCTAssertEqual(
            OutputResult.copyFailed(reason: "pasteboard failed").kind,
            .failed
        )
        XCTAssertEqual(OutputResult.cancelled.kind, .cancelled)
    }

    func testOutputResultKindDecodesPersistedSnapshotAndLegacyFullResult() throws {
        let snapshotData = try JSONEncoder().encode(
            OutputResult.permissionDenied(reason: "sensitive reason").snapshot
        )
        let legacyData = try JSONEncoder().encode(
            OutputResult.permissionDenied(reason: "legacy sensitive reason")
        )

        XCTAssertEqual(
            OutputResultKind.decodePersisted(from: String(data: snapshotData, encoding: .utf8)),
            .permissionDenied
        )
        XCTAssertEqual(
            OutputResultKind.decodePersisted(from: String(data: legacyData, encoding: .utf8)),
            .permissionDenied
        )
    }

    func testOutputResultSnapshotCodableRoundTripStoresOnlyKind() throws {
        let snapshot = OutputResultSnapshot(kind: .permissionDenied)
        let data = try JSONEncoder().encode(snapshot)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        let decoded = try JSONDecoder().decode(OutputResultSnapshot.self, from: data)

        XCTAssertEqual(decoded, snapshot)
        XCTAssertTrue(json.contains(#""kind":"permissionDenied""#))
        XCTAssertFalse(json.contains("reason"))
    }

    func testRecoveryActionsKeepAgentComposeCopyOnlyUsingOutputResultKind() {
        let actions = VoiceTaskRecoveryPolicy.availableActions(
            mode: .agentCompose,
            status: .completed,
            hasFinalText: true,
            hasRawTranscript: true,
            outputResultKind: OutputResult.targetChanged(
                reason: "Injected by another app"
            ).kind
        )

        XCTAssertEqual(actions, [.copy, .regenerate, .delete])
        XCTAssertFalse(actions.contains(.reoutput))
    }

    func testRecoveryActionsAllowCompletedDictationReoutputWhenOutputWasRecoverable() {
        let actions = VoiceTaskRecoveryPolicy.availableActions(
            mode: .dictation,
            status: .completed,
            hasFinalText: true,
            hasRawTranscript: true,
            outputResultKind: .inserted
        )

        XCTAssertEqual(actions, [.copy, .reoutput, .delete])
    }

    func testRecoveryActionsForCancelledTaskOnlyAllowDelete() {
        let actions = VoiceTaskRecoveryPolicy.availableActions(
            mode: .dictation,
            status: .cancelled,
            hasFinalText: true,
            hasRawTranscript: true,
            outputResultKind: .cancelled
        )

        XCTAssertEqual(actions, [.delete])
    }

    func testVoiceTaskStageBackwardsTransitionErrorIsAvailableFromDomainTarget() {
        XCTAssertThrowsError(
            try VoiceTaskStage.outputting.validateAdvancement(to: .recording)
        ) { error in
            guard case VoiceTaskError.backwardsStageTransition(
                from: "outputting",
                to: "recording"
            ) = error else {
                XCTFail("Expected backwardsStageTransition, got \(error)")
                return
            }
        }
    }

    func testDefaultDiagnosticExportOmitsFullUserTextAndAudioPath() throws {
        let output = OutputResult.permissionDenied(reason: "包含敏感原因")
        let outputData = try JSONEncoder().encode(output)
        let task = VoiceTask(
            id: "task-diagnostic",
            mode: .dictation,
            stage: .outputting,
            status: .partiallyCompleted,
            targetAppBundleID: "com.example.editor",
            targetAppName: "Editor",
            audioRelativePath: "audio/private-recording.wav",
            rawTranscript: "这是一段完整的敏感原始识别文本",
            finalText: "这是一段完整的敏感最终文本",
            outputResult: String(data: outputData, encoding: .utf8),
            failureJson: #"{"stage":"output","code":"permissionDenied","message":"包含敏感失败详情","recoverable":true}"#,
            asrMetadata: VoiceTaskASRMetadata(
                providerID: "qwen3_asr",
                modelID: "qwen3-asr-0.6b-mlx-4bit",
                language: "zh-CN",
                sessionID: "session-123",
                audioDurationMs: 1200,
                finalLatencyMs: 340,
                droppedFrameCount: 2,
                errorCode: "permissionDenied"
            ),
            warnings: ["warning"],
            trace: #"{"llm":{"requestBodyJSON":"包含敏感 trace 请求","responseText":"包含敏感 trace 响应"}}"#,
            createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_800_000_001),
            completedAt: Date(timeIntervalSince1970: 1_800_000_002)
        )

        let data = try VoiceTaskDiagnosticExporter().export(task)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertFalse(json.contains("这是一段完整的敏感原始识别文本"))
        XCTAssertFalse(json.contains("这是一段完整的敏感最终文本"))
        XCTAssertFalse(json.contains("audio/private-recording.wav"))
        XCTAssertFalse(json.contains("包含敏感原因"))
        XCTAssertFalse(json.contains("包含敏感失败详情"))
        XCTAssertFalse(json.contains("包含敏感 trace 请求"))
        XCTAssertFalse(json.contains("包含敏感 trace 响应"))
        XCTAssertFalse(json.contains("requestBodyJSON"))
        XCTAssertFalse(json.contains("responseText"))
        XCTAssertTrue(json.contains(#""rawTranscriptLength":"#))
        XCTAssertTrue(json.contains(#""finalTextLength":"#))
        XCTAssertTrue(json.contains(#""hasAudio":true"#))
        XCTAssertTrue(json.contains(#""outputResultKind":"permissionDenied""#))
        XCTAssertTrue(json.contains(#""errorCode":"permissionDenied""#))
    }
}
