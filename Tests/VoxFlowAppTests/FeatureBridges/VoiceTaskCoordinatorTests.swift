import Foundation
import VoxFlowVoiceCorrection
import XCTest
@testable import VoxFlowApp

@MainActor
final class VoiceTaskCoordinatorTests: XCTestCase {
    nonisolated(unsafe) private var databaseQueue: DatabaseQueue!
    nonisolated(unsafe) private var repository: VoiceTaskRepository!
    private let clock = CoordinatorTestClock(
        now: Date(timeIntervalSince1970: 1_800_000_000)
    )

    override func setUpWithError() throws {
        try super.setUpWithError()
        databaseQueue = try DatabaseQueue(connection: .inMemory())
        try AppDatabase.migrator(clock: clock).migrate(databaseQueue)
        repository = VoiceTaskRepository(databaseQueue: databaseQueue, clock: clock)
    }

    override func tearDown() {
        repository = nil
        databaseQueue = nil
        super.tearDown()
    }

    // MARK: - Task creation

    func testCoordinatorCreatesTaskAtRecordingStart() throws {
        let coordinator = makeCoordinator()
        let target = DictationTarget(
            bundleID: "com.example.editor",
            appName: "Editor",
            pid: 42
        )

        let task = try coordinator.startTask(mode: .dictation, target: target)

        XCTAssertEqual(task.mode, .dictation)
        XCTAssertEqual(task.stage, .recording)
        XCTAssertEqual(task.status, .inProgress)
        XCTAssertEqual(task.targetAppBundleID, "com.example.editor")
        XCTAssertEqual(task.targetAppName, "Editor")
        XCTAssertEqual(task.targetAppPID, 42)

        // Verify persistence
        let fetched = try repository.fetch(id: task.id)
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.mode, .dictation)
        XCTAssertEqual(fetched?.stage, .recording)
    }

    func testCoordinatorCreatesTaskWithNilTarget() throws {
        let coordinator = makeCoordinator()

        let task = try coordinator.startTask(mode: .agentCompose, target: nil)

        XCTAssertEqual(task.mode, .agentCompose)
        XCTAssertNil(task.targetAppBundleID)
        XCTAssertNil(task.targetAppName)
    }

    func testCoordinatorRejectsSecondTaskForSameWorkflowKind() throws {
        let coordinator = makeCoordinator()
        let first = try coordinator.startTask(mode: .dictation, target: nil)

        XCTAssertThrowsError(try coordinator.startTask(mode: .dictation, target: nil)) { error in
            guard case .workflowAlreadyRunning("dictation") = error as? CoordinatorError else {
                return XCTFail("Expected dictation workflow conflict, got \(error)")
            }
        }
        XCTAssertEqual(coordinator.activeTaskID(for: .dictation), first.id)
    }

    func testCoordinatorTracksIndependentWorkflowLeasesByKind() throws {
        let coordinator = makeCoordinator()
        let dictation = try coordinator.startTask(mode: .dictation, target: nil)
        let agentCompose = try coordinator.startTask(mode: .agentCompose, target: nil)

        XCTAssertEqual(coordinator.activeTaskID(for: .dictation), dictation.id)
        XCTAssertEqual(coordinator.activeTaskID(for: .agentCompose), agentCompose.id)

        try coordinator.cancelTask(kind: .dictation)

        XCTAssertNil(coordinator.activeTaskID(for: .dictation))
        XCTAssertEqual(coordinator.activeTaskID(for: .agentCompose), agentCompose.id)
    }

    func testCoordinatorRecordsTranscriptForExplicitWorkflowKind() throws {
        let coordinator = makeCoordinator()
        let dictation = try coordinator.startTask(mode: .dictation, target: nil)
        let agentCompose = try coordinator.startTask(mode: .agentCompose, target: nil)

        try coordinator.recordRawTranscript("dictation text", kind: .dictation)

        XCTAssertEqual(try repository.fetch(id: dictation.id)?.rawTranscript, "dictation text")
        XCTAssertNil(try repository.fetch(id: agentCompose.id)?.rawTranscript)
    }

    func testExplicitWorkflowUpdateDoesNotStealCurrentTaskFromAnotherWorkflow() throws {
        let coordinator = makeCoordinator()
        let dictation = try coordinator.startTask(mode: .dictation, target: nil)
        let agentCompose = try coordinator.startTask(mode: .agentCompose, target: nil)

        try coordinator.recordRawTranscript("dictation text", kind: .dictation)

        XCTAssertEqual(coordinator.currentTaskID, agentCompose.id)
        XCTAssertEqual(coordinator.activeTaskID(for: .dictation), dictation.id)
        XCTAssertEqual(coordinator.activeTaskID(for: .agentCompose), agentCompose.id)
    }

    func testCoordinatorProcessesExplicitDictationWorkflowWhenAnotherWorkflowIsCurrent() async throws {
        let pipeline = CoordinatorStubTextPipeline(
            result: TextProcessingResult(rawText: "dictation raw", finalText: "dictation final")
        )
        let outputService = CoordinatorStubOutputService(result: .injected)
        let coordinator = makeCoordinator(
            pipeline: pipeline,
            outputService: outputService
        )
        let dictation = try coordinator.startTask(mode: .dictation, target: nil)
        try coordinator.recordRawTranscript("dictation raw", kind: .dictation)
        let agentCompose = try coordinator.startTask(mode: .agentCompose, target: nil)

        let result = try await coordinator.processAndDeliver(kind: .dictation)

        XCTAssertEqual(result, .injected)
        XCTAssertEqual(try repository.fetch(id: dictation.id)?.finalText, "dictation final")
        XCTAssertNil(try repository.fetch(id: agentCompose.id)?.finalText)
        XCTAssertNil(coordinator.activeTaskID(for: .dictation))
        XCTAssertEqual(coordinator.activeTaskID(for: .agentCompose), agentCompose.id)
        XCTAssertEqual(coordinator.currentTaskID, agentCompose.id)
    }

    func testDictationProcessingReturnsCancelledWhenWorkflowIsCancelledDuringPipeline() async throws {
        let outputService = CoordinatorStubOutputService(result: .injected)
        var coordinator: VoiceTaskCoordinator!
        let pipeline = CoordinatorCancellingTextPipeline(
            result: TextProcessingResult(rawText: "raw", finalText: "late final"),
            onProcess: {
                try? coordinator.cancelTask(kind: .dictation)
            }
        )
        coordinator = makeCoordinator(
            pipeline: pipeline,
            outputService: outputService
        )
        let task = try coordinator.startTask(mode: .dictation, target: nil)
        try coordinator.recordRawTranscript("raw", kind: .dictation)

        let result = try await coordinator.processAndDeliver(kind: .dictation)

        XCTAssertEqual(result, .cancelled)
        XCTAssertNil(outputService.lastText)
        let fetched = try repository.fetch(id: task.id)
        XCTAssertEqual(fetched?.status, .cancelled)
        XCTAssertNil(fetched?.finalText)
        XCTAssertNil(coordinator.activeTaskID(for: .dictation))
    }

    func testCoordinatorTracksEphemeralOCRWorkflowsIndependently() throws {
        let coordinator = makeCoordinator()
        let clipboardLease = try coordinator.beginEphemeralWorkflow(kind: .clipboardImageOCR)
        let screenshotLease = try coordinator.beginEphemeralWorkflow(kind: .screenshotOCR)

        XCTAssertEqual(coordinator.activeTaskID(for: .clipboardImageOCR), clipboardLease.taskID)
        XCTAssertEqual(coordinator.activeTaskID(for: .screenshotOCR), screenshotLease.taskID)
        XCTAssertThrowsError(try coordinator.beginEphemeralWorkflow(kind: .clipboardImageOCR)) { error in
            guard case .workflowAlreadyRunning("clipboardImageOCR") = error as? CoordinatorError else {
                return XCTFail("Expected clipboard OCR workflow conflict, got \(error)")
            }
        }

        coordinator.completeEphemeralWorkflow(clipboardLease)

        XCTAssertNil(coordinator.activeTaskID(for: .clipboardImageOCR))
        XCTAssertEqual(coordinator.activeTaskID(for: .screenshotOCR), screenshotLease.taskID)
    }

    func testCancellingEphemeralWorkflowInvalidatesLease() throws {
        let coordinator = makeCoordinator()
        let lease = try coordinator.beginEphemeralWorkflow(kind: .clipboardImageOCR)

        coordinator.cancelEphemeralWorkflow(kind: .clipboardImageOCR)

        XCTAssertNil(coordinator.activeTaskID(for: .clipboardImageOCR))
        XCTAssertFalse(coordinator.isWorkflowLeaseActive(lease))
    }

    func testCancellingEphemeralWorkflowCancelsRegisteredTask() throws {
        let coordinator = makeCoordinator()
        let lease = try coordinator.beginEphemeralWorkflow(kind: .clipboardImageOCR)
        let task = Task { @MainActor in
            while !Task.isCancelled {
                await Task.yield()
            }
        }
        coordinator.registerEphemeralWorkflowTask(task, for: lease)

        coordinator.cancelEphemeralWorkflow(kind: .clipboardImageOCR)

        XCTAssertTrue(task.isCancelled)
    }

    func testCoordinatorRejectsEphemeralLeaseForPersistedVoiceModes() throws {
        let coordinator = makeCoordinator()

        XCTAssertThrowsError(try coordinator.beginEphemeralWorkflow(kind: .dictation)) { error in
            guard case .invalidMode = error as? CoordinatorError else {
                return XCTFail("Expected invalid mode for persisted workflow, got \(error)")
            }
        }
    }

    func testStartingContextCollectionCancelsPreviousCollection() async throws {
        let contextPipeline = CancellableContextCollector()
        let coordinator = makeCoordinator(contextPipeline: contextPipeline)
        try coordinator.startTask(mode: .agentCompose, target: nil)

        coordinator.startContextCollection(target: nil, visionSupported: true)
        coordinator.startContextCollection(target: nil, visionSupported: true)
        for _ in 0..<5 {
            await Task.yield()
        }

        let collectCount = await contextPipeline.collectCount
        let cancelledCount = await contextPipeline.cancelledCount
        XCTAssertEqual(collectCount, 2)
        XCTAssertEqual(cancelledCount, 1)
    }

    func testAwaitContextCollectionTimesOutAndFallsBackToWarningSnapshot() async throws {
        let contextPipeline = CancellableContextCollector()
        let coordinator = makeCoordinator(contextPipeline: contextPipeline)
        try coordinator.startTask(mode: .agentCompose, target: nil)

        coordinator.startContextCollection(target: nil, visionSupported: true)

        let snapshot = await coordinator.awaitContextCollection(timeoutMilliseconds: 0)

        XCTAssertEqual(snapshot?.warnings, ["context_collection_timeout"])
        let didCancel = await contextPipeline.waitUntilCancelled()
        XCTAssertTrue(didCancel)
        let cancelledCount = await contextPipeline.cancelledCount
        XCTAssertEqual(cancelledCount, 1)
    }

    func testCoordinatorPersistsASRMetadataAtRecordingStart() throws {
        let coordinator = makeCoordinator()
        let metadata = VoiceTaskASRMetadata(
            providerID: "qwen3_asr",
            modelID: "qwen3-asr-0.6b-mlx-4bit",
            modelVersion: "2025-09-01",
            language: "en-US",
            sessionID: "session-123"
        )

        let task = try coordinator.startTask(
            mode: .agentCompose,
            target: nil,
            asrMetadata: metadata
        )

        let fetched = try repository.fetch(id: task.id)
        XCTAssertEqual(fetched?.asrMetadata, metadata)
    }

    func testCoordinatorUpdatesASRMetadataAfterRuntimeEvents() throws {
        let coordinator = makeCoordinator()
        let task = try coordinator.startTask(
            mode: .agentCompose,
            target: nil,
            asrMetadata: VoiceTaskASRMetadata(
                providerID: "qwen3_asr",
                modelID: "qwen3-asr-0.6b-mlx-4bit",
                language: "zh-CN"
            )
        )
        let runtimeMetadata = VoiceTaskASRMetadata(
            providerID: "qwen3_asr",
            modelID: "qwen3-asr-0.6b-mlx-4bit",
            modelVersion: "2025-09-01",
            language: "zh-CN",
            sessionID: "asr-session-123",
            audioDurationMs: 1_250,
            finalLatencyMs: 430,
            droppedFrameCount: 2,
            errorCode: "finalTimeout"
        )

        try coordinator.updateASRMetadata(runtimeMetadata, kind: .agentCompose)

        let fetched = try repository.fetch(id: task.id)
        XCTAssertEqual(fetched?.asrMetadata, runtimeMetadata)
    }

    // MARK: - Raw transcript

    func testCoordinatorRecordsRawTranscriptAfterASR() throws {
        let coordinator = makeCoordinator()
        let task = try coordinator.startTask(mode: .dictation, target: nil)

        try coordinator.recordRawTranscript("hello world", kind: .dictation)

        let fetched = try repository.fetch(id: task.id)
        XCTAssertEqual(fetched?.rawTranscript, "hello world")
        XCTAssertEqual(fetched?.stage, .transcribing)
    }

    func testCoordinatorTrimsWhitespaceFromTranscript() throws {
        let coordinator = makeCoordinator()
        let task = try coordinator.startTask(mode: .dictation, target: nil)

        try coordinator.recordRawTranscript("  hello world  ", kind: .dictation)

        let fetched = try repository.fetch(id: task.id)
        XCTAssertEqual(fetched?.rawTranscript, "hello world")
    }

    func testCoordinatorIgnoresEmptyTranscript() throws {
        let coordinator = makeCoordinator()
        let task = try coordinator.startTask(mode: .dictation, target: nil)

        try coordinator.recordRawTranscript("   ", kind: .dictation)

        let fetched = try repository.fetch(id: task.id)
        XCTAssertNil(fetched?.rawTranscript)
        XCTAssertEqual(fetched?.stage, .recording)
    }

    // MARK: - Processing and delivery

    func testCoordinatorRecordsFinalTextAfterProcessing() async throws {
        let pipeline = CoordinatorStubTextPipeline(
            result: TextProcessingResult(rawText: "raw", finalText: "processed text")
        )
        let outputService = CoordinatorStubOutputService(result: .injected)
        let coordinator = makeCoordinator(
            pipeline: pipeline,
            outputService: outputService
        )
        let task = try coordinator.startTask(mode: .dictation, target: nil)
        try coordinator.recordRawTranscript("raw", kind: .dictation)

        _ = try await coordinator.processAndDeliver(kind: .dictation)

        let fetched = try repository.fetch(id: task.id)
        XCTAssertEqual(fetched?.finalText, "processed text")
    }

    func testCoordinatorCompletesTaskOnSuccessfulOutput() async throws {
        let pipeline = CoordinatorStubTextPipeline(
            result: TextProcessingResult(rawText: "raw", finalText: "final")
        )
        let outputService = CoordinatorStubOutputService(result: .injected)
        let coordinator = makeCoordinator(
            pipeline: pipeline,
            outputService: outputService
        )
        let task = try coordinator.startTask(mode: .dictation, target: nil)
        try coordinator.recordRawTranscript("raw", kind: .dictation)

        let result = try await coordinator.processAndDeliver(kind: .dictation)

        XCTAssertEqual(result, .injected)
        let fetched = try repository.fetch(id: task.id)
        XCTAssertEqual(fetched?.status, .completed)
        XCTAssertNotNil(fetched?.completedAt)
        XCTAssertNotNil(fetched?.outputResult)
        XCTAssertNil(coordinator.currentTaskID)
    }

    func testCoordinatorPassesFocusedSecureStateToCorrectionContext() async throws {
        let pipeline = CoordinatorCapturingContextPipeline(
            result: TextProcessingResult(rawText: "raw", finalText: "final")
        )
        let coordinator = makeCoordinator(
            pipeline: pipeline,
            isFocusedTextFieldSecure: { true }
        )
        try coordinator.startTask(
            mode: .dictation,
            target: DictationTarget(bundleID: "com.example.secure", appName: "Secure")
        )
        try coordinator.updateASRMetadata(
            VoiceTaskASRMetadata(providerID: "apple", modelID: "local", language: "en"),
            kind: .dictation
        )
        try coordinator.recordRawTranscript("raw", kind: .dictation)

        _ = try await coordinator.processAndDeliver(kind: .dictation)

        XCTAssertEqual(pipeline.capturedContexts.map(\.isSecureField), [true])
    }

    func testCoordinatorSchedulesCorrectionObservationOnlyAfterInjectedOutput() async throws {
        let event = CorrectionEvent(
            ruleID: UUID(),
            original: "q 问",
            replacement: "Qwen",
            range: CorrectionTextRange(location: 0, length: 4),
            scope: .global,
            source: .manual
        )
        let pipeline = CoordinatorStubTextPipeline(
            result: TextProcessingResult(
                rawText: "raw",
                finalText: "Qwen",
                correctionEvents: [event]
            )
        )
        let observer = CapturingCorrectionObservationScheduler()
        let coordinator = makeCoordinator(
            pipeline: pipeline,
            outputService: CoordinatorStubOutputService(result: .injected),
            targetProvider: CoordinatorMutableTargetProvider(
                target: DictationTarget(bundleID: "com.example.editor", appName: "Editor", pid: 4242)
            ),
            correctionObservationScheduler: observer
        )
        try coordinator.startTask(
            mode: .dictation,
            target: DictationTarget(bundleID: "com.example.editor", appName: "Editor", pid: 4242)
        )
        try coordinator.updateASRMetadata(
            VoiceTaskASRMetadata(providerID: "apple", modelID: "local", language: "en"),
            kind: .dictation
        )
        try coordinator.recordRawTranscript("raw", kind: .dictation)

        _ = try await coordinator.processAndDeliver(kind: .dictation)

        XCTAssertEqual(observer.observations.map(\.insertedText), ["Qwen"])
        XCTAssertEqual(observer.observations.first?.context.bundleIdentifier, "com.example.editor")
        XCTAssertEqual(observer.observations.first?.appliedEvents, [event])
        XCTAssertEqual(observer.observations.first?.targetProcessID, 4242)
        XCTAssertEqual(observer.capturedTargetProcessIDs, [4242])

        let skippedObserver = CapturingCorrectionObservationScheduler()
        let skippedCoordinator = makeCoordinator(
            pipeline: pipeline,
            outputService: CoordinatorStubOutputService(result: .targetChanged(reason: "App changed")),
            targetProvider: CoordinatorMutableTargetProvider(
                target: DictationTarget(bundleID: "com.example.other", appName: "Other")
            ),
            correctionObservationScheduler: skippedObserver
        )
        try skippedCoordinator.startTask(
            mode: .dictation,
            target: DictationTarget(bundleID: "com.example.editor", appName: "Editor")
        )
        try skippedCoordinator.recordRawTranscript("raw", kind: .dictation)

        _ = try await skippedCoordinator.processAndDeliver(kind: .dictation)

        XCTAssertTrue(skippedObserver.observations.isEmpty)
    }

    func testCoordinatorDoesNotSkipCorrectionObservationWhenOCRContextBoostWasApplied() async throws {
        let pipeline = CoordinatorStubTextPipeline(
            result: TextProcessingResult(
                rawText: "raw",
                finalText: "Qwen3-ASR",
                trace: TextProcessingTrace(
                    contextBoost: ContextBoostTrace(
                        appName: "Editor",
                        bundleID: "com.example.editor",
                        hotwords: ["Qwen3-ASR"],
                        source: "current_window_ocr",
                        ttlSeconds: 120,
                        appliedToLLMPrompt: true,
                        failureReason: nil
                    )
                )
            )
        )
        let observer = CapturingCorrectionObservationScheduler()
        let coordinator = makeCoordinator(
            pipeline: pipeline,
            outputService: CoordinatorStubOutputService(result: .injected),
            targetProvider: CoordinatorMutableTargetProvider(
                target: DictationTarget(bundleID: "com.example.editor", appName: "Editor")
            ),
            correctionObservationScheduler: observer
        )
        try coordinator.startTask(
            mode: .dictation,
            target: DictationTarget(bundleID: "com.example.editor", appName: "Editor")
        )
        try coordinator.updateASRMetadata(
            VoiceTaskASRMetadata(providerID: "apple", modelID: "local", language: "en"),
            kind: .dictation
        )
        try coordinator.recordRawTranscript("raw", kind: .dictation)

        _ = try await coordinator.processAndDeliver(kind: .dictation)

        XCTAssertEqual(observer.observations.map(\.insertedText), ["Qwen3-ASR"])
        XCTAssertEqual(observer.observations.first?.context.bundleIdentifier, "com.example.editor")
    }

    func testCoordinatorSkipsCorrectionObservationWhenSuccessfulLLMChangedText() async throws {
        let pipeline = CoordinatorStubTextPipeline(
            result: TextProcessingResult(
                rawText: "raw",
                finalText: "refined text",
                trace: TextProcessingTrace(
                    llm: LLMRefinementTrace(
                        providerID: "provider",
                        providerName: "Provider",
                        endpoint: "https://api.example.com/v1/chat/completions",
                        model: "gpt-test",
                        temperature: 0.0,
                        timeoutSeconds: 8,
                        requestBodyJSON: "{}",
                        responseText: "refined text",
                        statusCode: 200,
                        durationMS: 12,
                        errorMessage: nil,
                        completedAt: Date(timeIntervalSince1970: 1_800_000_000)
                    )
                )
            )
        )
        let observer = CapturingCorrectionObservationScheduler()
        let coordinator = makeCoordinator(
            pipeline: pipeline,
            outputService: CoordinatorStubOutputService(result: .injected),
            targetProvider: CoordinatorMutableTargetProvider(
                target: DictationTarget(bundleID: "com.example.editor", appName: "Editor")
            ),
            correctionObservationScheduler: observer
        )
        try coordinator.startTask(
            mode: .dictation,
            target: DictationTarget(bundleID: "com.example.editor", appName: "Editor")
        )
        try coordinator.updateASRMetadata(
            VoiceTaskASRMetadata(providerID: "apple", modelID: "local", language: "en"),
            kind: .dictation
        )
        try coordinator.recordRawTranscript("raw", kind: .dictation)

        _ = try await coordinator.processAndDeliver(kind: .dictation)

        XCTAssertTrue(observer.observations.isEmpty)
    }

    func testCoordinatorCompletesTaskOnCopiedOutput() async throws {
        let pipeline = CoordinatorStubTextPipeline(
            result: TextProcessingResult(rawText: "raw", finalText: "final")
        )
        let outputService = CoordinatorStubOutputService(result: .copied)
        let coordinator = makeCoordinator(
            pipeline: pipeline,
            outputService: outputService
        )
        let task = try coordinator.startTask(mode: .dictation, target: nil)
        try coordinator.recordRawTranscript("raw", kind: .dictation)

        let result = try await coordinator.processAndDeliver(kind: .dictation)

        XCTAssertEqual(result, .copied)
        let fetched = try repository.fetch(id: task.id)
        XCTAssertEqual(fetched?.status, .completed)
    }

    func testCoordinatorFailsTaskOnOutputFailure() async throws {
        let pipeline = CoordinatorStubTextPipeline(
            result: TextProcessingResult(rawText: "raw", finalText: "final")
        )
        let outputService = CoordinatorStubOutputService(
            result: .injectionFailed(reason: "Accessibility denied")
        )
        let coordinator = makeCoordinator(
            pipeline: pipeline,
            outputService: outputService
        )
        let task = try coordinator.startTask(mode: .dictation, target: nil)
        try coordinator.recordRawTranscript("raw", kind: .dictation)

        let result = try await coordinator.processAndDeliver(kind: .dictation)

        XCTAssertEqual(result, .injectionFailed(reason: "Accessibility denied"))
        let fetched = try repository.fetch(id: task.id)
        XCTAssertEqual(fetched?.status, .partiallyCompleted)
    }

    func testCoordinatorMarksTaskCancelledWhenOutputIsCancelled() async throws {
        let pipeline = CoordinatorStubTextPipeline(
            result: TextProcessingResult(rawText: "raw", finalText: "final")
        )
        let outputService = CoordinatorStubOutputService(result: .cancelled)
        let coordinator = makeCoordinator(
            pipeline: pipeline,
            outputService: outputService
        )
        let task = try coordinator.startTask(mode: .dictation, target: nil)
        try coordinator.recordRawTranscript("raw", kind: .dictation)

        let result = try await coordinator.processAndDeliver(kind: .dictation)

        XCTAssertEqual(result, .cancelled)
        let fetched = try repository.fetch(id: task.id)
        XCTAssertEqual(fetched?.status, .cancelled)
        XCTAssertNil(fetched?.finalText)
        XCTAssertNil(coordinator.currentTaskID)
        XCTAssertNil(coordinator.activeTaskID(for: .dictation))
    }

    func testCoordinatorClearsFinalTextWhenCurrentTaskIsCancelledAfterProcessing() async throws {
        let pipeline = CoordinatorCancellingTextPipeline(
            result: TextProcessingResult(rawText: "raw", finalText: "late final"),
            onProcess: {}
        )
        let outputService = CoordinatorCancellingOutputService(
            result: .injected,
            onDeliver: { coordinator in
                try? coordinator.cancelTask(kind: .dictation)
            }
        )
        let coordinator = makeCoordinator(
            pipeline: pipeline,
            outputService: outputService
        )
        outputService.coordinator = coordinator
        let task = try coordinator.startTask(mode: .dictation, target: nil)
        try coordinator.recordRawTranscript("raw", kind: .dictation)

        let result = try await coordinator.processAndDeliver(kind: .dictation)

        XCTAssertEqual(result, .cancelled)
        let fetched = try repository.fetch(id: task.id)
        XCTAssertEqual(fetched?.status, .cancelled)
        XCTAssertNil(fetched?.finalText)
        XCTAssertNil(coordinator.activeTaskID(for: .dictation))
    }

    func testCoordinatorPersistsOutputResultSnapshotWithoutFailureReason() async throws {
        let pipeline = CoordinatorStubTextPipeline(
            result: TextProcessingResult(rawText: "raw", finalText: "final")
        )
        let outputService = CoordinatorStubOutputService(
            result: .permissionDenied(reason: "Sensitive accessibility failure details")
        )
        let coordinator = makeCoordinator(
            pipeline: pipeline,
            outputService: outputService
        )
        let task = try coordinator.startTask(mode: .dictation, target: nil)
        try coordinator.recordRawTranscript("raw", kind: .dictation)

        _ = try await coordinator.processAndDeliver(kind: .dictation)

        let outputResult = try XCTUnwrap(repository.fetch(id: task.id)?.outputResult)
        let snapshot = try JSONDecoder().decode(OutputResultSnapshot.self, from: Data(outputResult.utf8))
        XCTAssertEqual(snapshot.kind, .permissionDenied)
        XCTAssertFalse(outputResult.contains("Sensitive accessibility failure details"))
    }

    func testCoordinatorPartiallyCompletesOnTargetChanged() async throws {
        let pipeline = CoordinatorStubTextPipeline(
            result: TextProcessingResult(rawText: "raw", finalText: "final")
        )
        let outputService = CoordinatorStubOutputService(
            result: .targetChanged(reason: "App changed")
        )
        let coordinator = makeCoordinator(
            pipeline: pipeline,
            outputService: outputService
        )
        let task = try coordinator.startTask(mode: .dictation, target: nil)
        try coordinator.recordRawTranscript("raw")

        let result = try await coordinator.processAndDeliver()

        XCTAssertEqual(result, .targetChanged(reason: "App changed"))
        let fetched = try repository.fetch(id: task.id)
        XCTAssertEqual(fetched?.status, .partiallyCompleted)
    }

    // MARK: - LLM failure fallback

    func testLLMFailureFallsBackToRawTranscript() async throws {
        let pipeline = CoordinatorStubTextPipeline(
            result: TextProcessingResult(
                rawText: "raw text",
                finalText: "raw text",
                warnings: ["llm_refinement_failed"]
            )
        )
        let outputService = CoordinatorStubOutputService(result: .injected)
        let coordinator = makeCoordinator(
            pipeline: pipeline,
            outputService: outputService
        )
        let task = try coordinator.startTask(mode: .dictation, target: nil)
        try coordinator.recordRawTranscript("raw text", kind: .dictation)

        let result = try await coordinator.processAndDeliver(kind: .dictation)

        XCTAssertEqual(result, .injected)
        let fetched = try repository.fetch(id: task.id)
        XCTAssertEqual(fetched?.finalText, "raw text")
        XCTAssertEqual(outputService.lastText, "raw text")
    }

    func testAgentComposePersistsRequestLocalStreamingTrace() async throws {
        let localTrace = LLMRefinementTrace(
            providerID: "stream-local-provider",
            providerName: "Streaming Provider",
            endpoint: "https://api.example.com/v1/chat/completions",
            model: "stream-local-model",
            temperature: 0.2,
            timeoutSeconds: 13,
            requestBodyJSON: "{}",
            responseText: nil,
            statusCode: 200,
            durationMS: 10,
            errorMessage: nil,
            completedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let poisonTrace = LLMRefinementTrace(
            providerID: "poison-provider",
            providerName: "Poison Provider",
            endpoint: "https://api.example.com/v1/chat/completions",
            model: "poison-model",
            temperature: 0.2,
            timeoutSeconds: 13,
            requestBodyJSON: "{}",
            responseText: nil,
            statusCode: 200,
            durationMS: 10,
            errorMessage: nil,
            completedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let refiner = CoordinatorTraceableStreamingRefiner(
            snapshots: ["周", "周三可以"],
            trace: localTrace,
            lastTrace: poisonTrace
        )
        let outputService = CoordinatorStubOutputService(result: .copied)
        let coordinator = makeCoordinator(
            outputService: outputService,
            agentRefiner: refiner
        )
        let task = try coordinator.startTask(mode: .agentCompose, target: nil)
        try coordinator.recordRawTranscript("帮我回复：周三可以", kind: .agentCompose)

        let result = try await coordinator.processAgentComposeAndDeliver(context: nil, stylePrompt: nil)

        XCTAssertEqual(result, .copied)
        XCTAssertEqual(outputService.lastText, "周三可以")
        let traceJSON = try XCTUnwrap(repository.fetch(id: task.id)?.trace)
        let trace = try JSONDecoder().decode(TextProcessingTrace.self, from: Data(traceJSON.utf8))
        XCTAssertEqual(trace.llm?.providerID, "stream-local-provider")
        XCTAssertEqual(trace.llm?.model, "stream-local-model")
    }

    func testAgentDispatchFallbackInputStaysInProgressUntilRealOutputCompletes() throws {
        let coordinator = makeCoordinator()
        let task = try coordinator.startTask(mode: .agentDispatch, target: nil)

        try coordinator.completeAgentDispatch(
            finalText: "原始指令",
            presentation: .fallbackInput(text: "写入输入框")
        )

        let fetched = try XCTUnwrap(repository.fetch(id: task.id))
        XCTAssertEqual(fetched.status, .inProgress)
        XCTAssertEqual(fetched.stage, .processing)
        XCTAssertEqual(coordinator.activeTaskID(for: .agentDispatch), task.id)
    }

    func testAgentDispatchFallbackInputCompletesWithRealOutputResult() throws {
        let coordinator = makeCoordinator()
        let task = try coordinator.startTask(mode: .agentDispatch, target: nil)
        try coordinator.completeAgentDispatch(
            finalText: "原始指令",
            presentation: .fallbackInput(text: "写入输入框")
        )

        try coordinator.completeAgentDispatchFallbackInput(
            finalText: "写入输入框",
            outputResult: .targetChanged(reason: "App changed")
        )

        let fetched = try XCTUnwrap(repository.fetch(id: task.id))
        XCTAssertEqual(fetched.status, .partiallyCompleted)
        XCTAssertEqual(fetched.finalText, "写入输入框")
        XCTAssertEqual(coordinator.activeTaskID(for: .agentDispatch), nil)
    }

    func testCompletedAgentDispatchWritesVoiceAsset() throws {
        let assetRepository = CapturingVoiceTaskAssetRepository()
        let coordinator = makeCoordinator(assetRepository: assetRepository)
        try coordinator.startTask(mode: .agentDispatch, target: nil)
        try coordinator.recordRawTranscript("Codex 看下这个 bug", kind: .agentDispatch)

        try coordinator.completeAgentDispatch(
            finalText: "Codex 看下这个 bug",
            presentation: .sent(agentName: "Codex")
        )

        XCTAssertEqual(assetRepository.savedItems.count, 1)
        let asset = try XCTUnwrap(assetRepository.savedItems.first)
        XCTAssertEqual(asset.source, .dictation)
        XCTAssertEqual(asset.contentType, .text)
        XCTAssertEqual(asset.text, "Codex 看下这个 bug")
        XCTAssertEqual(asset.rawText, "Codex 看下这个 bug")
        XCTAssertEqual(asset.captureReason, .dictationCompleted)
    }

    func testAgentDispatchFallbackInputWritesVoiceAssetAfterSkippingCorrection() throws {
        let assetRepository = CapturingVoiceTaskAssetRepository()
        let coordinator = makeCoordinator(assetRepository: assetRepository)
        try coordinator.startTask(mode: .agentDispatch, target: nil)
        try coordinator.recordRawTranscript("检查一下按钮", kind: .agentDispatch)
        try coordinator.completeAgentDispatch(
            finalText: "检查一下按钮",
            presentation: .fallbackInput(text: "检查一下按钮")
        )

        try coordinator.completeAgentDispatchFallbackInput(
            finalText: "检查一下按钮",
            outputResult: .injected
        )

        XCTAssertEqual(assetRepository.savedItems.count, 1)
        let asset = try XCTUnwrap(assetRepository.savedItems.first)
        XCTAssertEqual(asset.source, .dictation)
        XCTAssertEqual(asset.contentType, .text)
        XCTAssertEqual(asset.text, "检查一下按钮")
        XCTAssertEqual(asset.rawText, "检查一下按钮")
        XCTAssertEqual(asset.captureReason, .dictationCompleted)
    }

    func testAgentDispatchFallbackInputCompletionDoesNotScheduleBaselineLessObservation() throws {
        let observer = CapturingCorrectionObservationScheduler()
        let target = DictationTarget(bundleID: "com.example.editor", appName: "Editor")
        let event = CorrectionEvent(
            ruleID: UUID(),
            original: "q 问",
            replacement: "Qwen",
            range: CorrectionTextRange(location: 0, length: 3),
            scope: .global,
            source: .manual
        )
        let coordinator = makeCoordinator(correctionObservationScheduler: observer)
        try coordinator.startTask(
            mode: .agentDispatch,
            target: target,
            asrMetadata: VoiceTaskASRMetadata(
                providerID: "funasr",
                modelID: "funasr-fp32",
                language: "zh-CN"
            )
        )
        try coordinator.recordRawTranscript("C端四的接口", kind: .agentDispatch)
        try coordinator.completeAgentDispatch(
            finalText: "C端四的接口",
            presentation: .fallbackInput(text: "C端四的接口")
        )

        try coordinator.completeAgentDispatchFallbackInput(
            finalText: "C端四的接口",
            outputResult: .injected,
            appliedCorrectionEvents: [event]
        )

        XCTAssertTrue(observer.observations.isEmpty)
    }

    func testAgentDispatchSentToAssistantDoesNotScheduleCorrectionObservation() throws {
        let observer = CapturingCorrectionObservationScheduler()
        let coordinator = makeCoordinator(correctionObservationScheduler: observer)
        try coordinator.startTask(
            mode: .agentDispatch,
            target: DictationTarget(bundleID: "com.mitchellh.ghostty", appName: "Ghostty")
        )
        try coordinator.recordRawTranscript("Codex 看下接口", kind: .agentDispatch)

        try coordinator.completeAgentDispatch(
            finalText: "看下接口",
            presentation: .sent(agentName: "Codex")
        )

        XCTAssertTrue(observer.observations.isEmpty)
    }

    func testAgentDispatchHandlerStoresActualSentMessageAsFinalText() async throws {
        let taskCoordinator = makeCoordinator()
        let dispatchCoordinator = AgentDispatchCoordinator(
            router: HandlerDirectAgentRouter(
                agent: AgentSessionCard(
                    schemaVersion: 1,
                    agentID: "codex",
                    cli: "codex",
                    command: ["codex"],
                    cwd: "/tmp",
                    status: .active,
                    displayName: "Codex"
                ),
                message: "帮我修 bug"
            )
        )
        let handler = DefaultAgentDispatchHandler(
            taskCoordinator: taskCoordinator,
            dispatchCoordinator: dispatchCoordinator,
            clipboardService: HandlerClipboardService(),
            confirmationTimeoutNanoseconds: 1
        )

        try handler.start(target: nil as DictationTarget?, asrMetadata: nil as VoiceTaskASRMetadata?)
        await drainVoiceTaskMainActorTasks()
        _ = try await handler.finish(rawTranscript: "Codex 帮我修 bug")

        let task = try XCTUnwrap(repository.listRecent(mode: .agentDispatch, limit: 1).first)
        XCTAssertEqual(task.rawTranscript, "Codex 帮我修 bug")
        XCTAssertEqual(task.finalText, "帮我修 bug")
    }

    func testAgentDispatchHandlerKeepsNoAgentFallbackAsInput() async throws {
        let taskCoordinator = makeCoordinator()
        let dispatchCoordinator = AgentDispatchCoordinator(router: HandlerNoAgentRouter())
        let clipboard = HandlerClipboardService()
        let handler = DefaultAgentDispatchHandler(
            taskCoordinator: taskCoordinator,
            dispatchCoordinator: dispatchCoordinator,
            clipboardService: clipboard,
            confirmationTimeoutNanoseconds: 1
        )
        var presentations: [AgentDispatchHUDPresentation] = []
        handler.onPresentationChange = { presentations.append($0) }

        try handler.start(target: nil as DictationTarget?, asrMetadata: nil as VoiceTaskASRMetadata?)
        await drainVoiceTaskMainActorTasks()
        let presentation = try await handler.finish(rawTranscript: "Voice input.")

        XCTAssertEqual(presentation, .fallbackInput(text: "Voice input."))
        XCTAssertFalse(presentations.contains(.fallbackInput(text: "Voice input.")))
        XCTAssertTrue(clipboard.copiedTexts.isEmpty)
        let task = try XCTUnwrap(repository.listRecent(mode: .agentDispatch, limit: 1).first)
        XCTAssertEqual(task.status, .inProgress)
        XCTAssertEqual(task.stage, .processing)
        XCTAssertEqual(task.finalText, "Voice input.")
    }

    func testAgentDispatchHandlerBeginDefaultOutputCancelsConfirmationTimeout() async throws {
        let taskCoordinator = makeCoordinator()
        let clipboard = HandlerClipboardService()
        let handler = DefaultAgentDispatchHandler(
            taskCoordinator: taskCoordinator,
            dispatchCoordinator: AgentDispatchCoordinator(router: HandlerAmbiguousAgentRouter()),
            clipboardService: clipboard,
            confirmationTimeoutNanoseconds: 1_000_000
        )

        try handler.start(target: nil, asrMetadata: nil)
        await drainVoiceTaskMainActorTasks()
        let presentation = try await handler.finish(rawTranscript: "检查一下")
        XCTAssertTrue(presentation.isConfirmationForTest)

        handler.beginDefaultOutput()
        try await Task.sleep(nanoseconds: 5_000_000)

        XCTAssertTrue(clipboard.copiedTexts.isEmpty)
        XCTAssertNotNil(taskCoordinator.activeTaskID(for: .agentDispatch))
    }

    func testAgentDispatchHandlerConfirmationTimeoutRetainsTextWithoutClipboard() async throws {
        let taskCoordinator = makeCoordinator()
        let clipboard = HandlerClipboardService()
        let handler = DefaultAgentDispatchHandler(
            taskCoordinator: taskCoordinator,
            dispatchCoordinator: AgentDispatchCoordinator(router: HandlerAmbiguousAgentRouter()),
            clipboardService: clipboard,
            confirmationTimeoutNanoseconds: 1_000_000
        )
        var presentations: [AgentDispatchHUDPresentation] = []
        handler.onPresentationChange = { presentations.append($0) }

        try handler.start(target: nil, asrMetadata: nil)
        await drainVoiceTaskMainActorTasks()
        let presentation = try await handler.finish(rawTranscript: "检查一下")
        XCTAssertTrue(presentation.isConfirmationForTest)

        let expectedFailure = AgentDispatchHUDPresentation.failure(
            message: "未选择任务助手",
            retainedText: "检查一下"
        )
        let didTimeout = await waitUntilVoiceTaskTestCondition {
            presentations.contains(expectedFailure)
                && taskCoordinator.activeTaskID(for: .agentDispatch) == nil
                && ((try? self.repository.listRecent(mode: .agentDispatch, limit: 1).first?.status) == .failed)
        }

        XCTAssertTrue(clipboard.copiedTexts.isEmpty)
        XCTAssertTrue(didTimeout)
        XCTAssertTrue(presentations.contains(expectedFailure))
        XCTAssertNil(taskCoordinator.activeTaskID(for: .agentDispatch))
        let task = try XCTUnwrap(repository.listRecent(mode: .agentDispatch, limit: 1).first)
        XCTAssertEqual(task.status, .failed)
        XCTAssertEqual(task.finalText, "检查一下")
    }

    func testAgentDispatchHandlerClearsActiveStateWhenFallbackAccountingFails() throws {
        let taskCoordinator = makeCoordinator()
        let handler = DefaultAgentDispatchHandler(
            taskCoordinator: taskCoordinator,
            dispatchCoordinator: AgentDispatchCoordinator(router: HandlerNoAgentRouter()),
            clipboardService: HandlerClipboardService()
        )
        let target = DictationTarget(bundleID: "com.example.editor", appName: "Editor")
        try handler.start(target: target, asrMetadata: nil)
        try taskCoordinator.cancelTask(kind: .agentDispatch)

        XCTAssertThrowsError(
            try handler.completeFallbackInput(
                finalText: "保留文本",
                outputResult: .injected,
                appliedCorrectionEvents: []
            )
        )
        XCTAssertNil(handler.activeTarget)
    }

    func testAgentDispatchHandlerDiscardsLateFinishAfterCancelAndRestart() async throws {
        let taskCoordinator = makeCoordinator()
        let router = HandlerDelayedResolveRouter()
        let handler = DefaultAgentDispatchHandler(
            taskCoordinator: taskCoordinator,
            dispatchCoordinator: AgentDispatchCoordinator(router: router),
            clipboardService: HandlerClipboardService()
        )
        try handler.start(target: nil, asrMetadata: nil)
        await drainVoiceTaskMainActorTasks()

        let oldFinish = Task { try await handler.finish(rawTranscript: "旧任务") }
        await router.waitUntilResolveStarts()
        handler.cancel()
        try handler.start(target: nil, asrMetadata: nil)
        let newTaskID = try XCTUnwrap(taskCoordinator.activeTaskID(for: .agentDispatch))

        await router.resumeResolve()
        do {
            _ = try await oldFinish.value
            XCTFail("Late finish should be discarded after the workflow is replaced")
        } catch is CancellationError {
        }

        let newTask = try XCTUnwrap(repository.fetch(id: newTaskID))
        XCTAssertEqual(newTask.status, .inProgress)
        XCTAssertEqual(newTask.stage, .recording)
        XCTAssertNil(newTask.rawTranscript)
        XCTAssertNil(newTask.finalText)
    }

    func testAgentDispatchHandlerDiscardsLateConfirmAfterCancelAndRestart() async throws {
        let taskCoordinator = makeCoordinator()
        let router = HandlerDelayedConfirmRouter()
        let handler = DefaultAgentDispatchHandler(
            taskCoordinator: taskCoordinator,
            dispatchCoordinator: AgentDispatchCoordinator(router: router),
            clipboardService: HandlerClipboardService(),
            confirmationTimeoutNanoseconds: 10_000_000_000
        )
        try handler.start(target: nil, asrMetadata: nil)
        await drainVoiceTaskMainActorTasks()
        _ = try await handler.finish(rawTranscript: "检查一下")

        let oldConfirm = Task {
            await handler.confirm(
                agentID: "codex",
                utterance: "检查一下",
                message: "旧确认消息",
                alias: nil
            )
        }
        await router.waitUntilSendStarts()
        handler.cancel()
        try handler.start(target: nil, asrMetadata: nil)
        let newTaskID = try XCTUnwrap(taskCoordinator.activeTaskID(for: .agentDispatch))

        await router.resumeSend()
        await oldConfirm.value

        let newTask = try XCTUnwrap(repository.fetch(id: newTaskID))
        XCTAssertEqual(newTask.status, .inProgress)
        XCTAssertEqual(newTask.stage, .recording)
        XCTAssertNil(newTask.rawTranscript)
        XCTAssertNil(newTask.finalText)
    }

    // MARK: - Stage advancement

    func testCoordinatorAdvancesStagesInOrder() async throws {
        let pipeline = CoordinatorStubTextPipeline(
            result: TextProcessingResult(rawText: "raw", finalText: "final")
        )
        let outputService = CoordinatorStubOutputService(result: .injected)
        let coordinator = makeCoordinator(
            pipeline: pipeline,
            outputService: outputService
        )
        let task = try coordinator.startTask(mode: .dictation, target: nil)
        XCTAssertEqual(task.stage, .recording)

        try coordinator.recordRawTranscript("raw", kind: .dictation)
        let afterTranscript = try repository.fetch(id: task.id)
        XCTAssertEqual(afterTranscript?.stage, .transcribing)

        _ = try await coordinator.processAndDeliver(kind: .dictation)
        let afterDelivery = try repository.fetch(id: task.id)
        // Stage should be outputting (the last stage set before completion)
        XCTAssertEqual(afterDelivery?.stage, .outputting)
    }

    // MARK: - Cancellation

    func testCoordinatorCancelsTask() throws {
        let coordinator = makeCoordinator()
        let task = try coordinator.startTask(mode: .dictation, target: nil)

        try coordinator.cancelCurrentTask()

        let fetched = try repository.fetch(id: task.id)
        XCTAssertEqual(fetched?.status, .cancelled)
        XCTAssertNotNil(fetched?.completedAt)
    }

    // MARK: - Failure recording

    func testCoordinatorRecordsStructuredFailure() throws {
        let coordinator = makeCoordinator()
        let task = try coordinator.startTask(mode: .dictation, target: nil)

        try coordinator.recordFailure(
            stage: "transcribing",
            code: "ASR_TIMEOUT",
            message: "Recognition timed out",
            recoverable: true
        )

        let fetched = try repository.fetch(id: task.id)
        XCTAssertEqual(fetched?.status, .failed)
        XCTAssertNotNil(fetched?.failureJson)

        let data = fetched!.failureJson!.data(using: .utf8)!
        let failure = try JSONDecoder().decode(VoiceTaskFailure.self, from: data)
        XCTAssertEqual(failure.stage, "transcribing")
        XCTAssertEqual(failure.code, "ASR_TIMEOUT")
        XCTAssertEqual(failure.recoverable, true)
    }

    // MARK: - Incomplete task detection

    func testIncompleteTasksDetectedOnStartup() throws {
        // Create some tasks directly in the repository
        let incomplete = VoiceTask(
            id: "incomplete-1",
            mode: .dictation,
            stage: .processing,
            status: .inProgress,
            createdAt: clock.now,
            updatedAt: clock.now
        )
        let completed = VoiceTask(
            id: "completed-1",
            mode: .dictation,
            stage: .outputting,
            status: .completed,
            createdAt: clock.now,
            updatedAt: clock.now,
            completedAt: clock.now
        )
        let failed = VoiceTask(
            id: "failed-1",
            mode: .dictation,
            stage: .transcribing,
            status: .failed,
            createdAt: clock.now,
            updatedAt: clock.now
        )
        try repository.create(incomplete)
        try repository.create(completed)
        try repository.create(failed)

        // Use coordinator to check incomplete tasks
        let coordinator = makeCoordinator()
        let tasks = try coordinator.checkIncompleteTasks()

        XCTAssertEqual(tasks.count, 1)
        XCTAssertEqual(tasks.first?.id, "incomplete-1")
    }

    func testNoIncompleteTasksReturnsEmpty() throws {
        let completed = VoiceTask(
            id: "completed-1",
            mode: .dictation,
            stage: .outputting,
            status: .completed,
            createdAt: clock.now,
            updatedAt: clock.now,
            completedAt: clock.now
        )
        try repository.create(completed)

        let coordinator = makeCoordinator()
        let tasks = try coordinator.checkIncompleteTasks()

        XCTAssertTrue(tasks.isEmpty)
    }

    // MARK: - OutputService integration

    func testCoordinatorPassesCorrectTargetToOutputService() async throws {
        let target = DictationTarget(
            bundleID: "com.example.editor",
            appName: "Editor",
            windowID: "win-1"
        )
        let pipeline = CoordinatorStubTextPipeline(
            result: TextProcessingResult(rawText: "raw", finalText: "final")
        )
        let outputService = CoordinatorStubOutputService(result: .injected)
        let targetProvider = CoordinatorMutableTargetProvider(target: target)
        let coordinator = makeCoordinator(
            pipeline: pipeline,
            outputService: outputService,
            targetProvider: targetProvider
        )
        try coordinator.startTask(mode: .dictation, target: target)
        try coordinator.recordRawTranscript("raw", kind: .dictation)

        _ = try await coordinator.processAndDeliver(kind: .dictation)

        XCTAssertEqual(outputService.lastOriginalTarget, target)
        XCTAssertEqual(outputService.lastCurrentTarget, target)
        XCTAssertEqual(outputService.lastMode, .dictation)
    }

    func testCoordinatorWritesSuccessfulDictationAsset() async throws {
        let assetRepository = CapturingVoiceTaskAssetRepository()
        let coordinator = makeCoordinator(
            pipeline: CoordinatorStubTextPipeline(
                result: TextProcessingResult(rawText: "raw text", finalText: "corrected text")
            ),
            outputService: CoordinatorStubOutputService(result: .injected),
            targetProvider: CoordinatorMutableTargetProvider(
                target: DictationTarget(bundleID: "com.example.editor", appName: "Editor")
            ),
            assetRepository: assetRepository
        )
        try coordinator.startTask(
            mode: .dictation,
            target: DictationTarget(bundleID: "com.example.editor", appName: "Editor")
        )
        try coordinator.recordRawTranscript("raw text")

        _ = try await coordinator.processAndDeliver()

        XCTAssertEqual(assetRepository.savedItems.count, 1)
        let asset = try XCTUnwrap(assetRepository.savedItems.first)
        XCTAssertEqual(asset.source, .dictation)
        XCTAssertEqual(asset.contentType, .text)
        XCTAssertEqual(asset.text, "corrected text")
        XCTAssertEqual(asset.rawText, "raw text")
        XCTAssertEqual(asset.captureReason, .dictationCompleted)
        XCTAssertEqual(asset.sourceAppName, "Editor")
        XCTAssertEqual(asset.sourceAppBundleID, "com.example.editor")
    }

    func testCoordinatorWritesFallbackCopiedDictationAssetWithoutClipboardSource() async throws {
        let assetRepository = CapturingVoiceTaskAssetRepository()
        let coordinator = makeCoordinator(
            pipeline: CoordinatorStubTextPipeline(
                result: TextProcessingResult(rawText: "raw text", finalText: "fallback text")
            ),
            outputService: CoordinatorStubOutputService(
                result: .permissionDenied(reason: "Accessibility permission denied")
            ),
            assetRepository: assetRepository
        )
        try coordinator.startTask(mode: .dictation, target: nil)
        try coordinator.recordRawTranscript("raw text")

        _ = try await coordinator.processAndDeliver()

        XCTAssertEqual(assetRepository.savedItems.count, 1)
        XCTAssertEqual(assetRepository.savedItems.first?.source, .dictation)
        XCTAssertEqual(assetRepository.savedItems.first?.captureReason, .fallbackCopied)
    }

    func testCoordinatorWritesSuccessfulAgentDispatchAsset() async throws {
        let assetRepository = CapturingVoiceTaskAssetRepository()
        let coordinator = makeCoordinator(
            pipeline: CoordinatorStubTextPipeline(
                result: TextProcessingResult(rawText: "什么意思", finalText: "什么意思？")
            ),
            outputService: CoordinatorStubOutputService(result: .injected),
            assetRepository: assetRepository
        )
        try coordinator.startTask(mode: .agentDispatch, target: nil)
        try coordinator.recordRawTranscript("什么意思")

        _ = try await coordinator.processAndDeliver(kind: .agentDispatch)

        XCTAssertEqual(assetRepository.savedItems.count, 1)
        let asset = try XCTUnwrap(assetRepository.savedItems.first)
        XCTAssertEqual(asset.source, .dictation)
        XCTAssertEqual(asset.contentType, .text)
        XCTAssertEqual(asset.text, "什么意思")
        XCTAssertEqual(asset.rawText, "什么意思")
        XCTAssertEqual(asset.captureReason, .dictationCompleted)
    }

    func testCoordinatorWritesSuccessfulAgentComposeAsset() async throws {
        let assetRepository = CapturingVoiceTaskAssetRepository()
        let coordinator = makeCoordinator(
            outputService: CoordinatorStubOutputService(result: .copied),
            agentRefiner: CoordinatorStubPromptRefiner(result: "帮我说生成后的文本"),
            assetRepository: assetRepository
        )
        try coordinator.startTask(mode: .agentCompose, target: nil)
        try coordinator.recordRawTranscript("帮我说原始语音", kind: .agentCompose)

        _ = try await coordinator.processAgentComposeAndDeliver(context: nil, stylePrompt: nil)

        XCTAssertEqual(assetRepository.savedItems.count, 1)
        let asset = try XCTUnwrap(assetRepository.savedItems.first)
        XCTAssertEqual(asset.source, .dictation)
        XCTAssertEqual(asset.contentType, .text)
        XCTAssertEqual(asset.text, "帮我说原始语音")
        XCTAssertEqual(asset.rawText, "帮我说原始语音")
        XCTAssertEqual(asset.captureReason, .dictationCompleted)
    }

    func testCoordinatorWritesAgentComposeAssetWhenPostASRWorkflowFails() throws {
        let assetRepository = CapturingVoiceTaskAssetRepository()
        let coordinator = makeCoordinator(assetRepository: assetRepository)
        try coordinator.startTask(mode: .agentCompose, target: nil)
        try coordinator.recordRawTranscript("帮我说失败前的语音", kind: .agentCompose)

        try coordinator.recordFailure(
            stage: "agentCompose",
            code: "agent_compose_failed",
            message: "LLM failed",
            recoverable: true,
            kind: .agentCompose
        )

        XCTAssertEqual(assetRepository.savedItems.count, 1)
        let asset = try XCTUnwrap(assetRepository.savedItems.first)
        XCTAssertEqual(asset.source, .dictation)
        XCTAssertEqual(asset.text, "帮我说失败前的语音")
        XCTAssertEqual(asset.rawText, "帮我说失败前的语音")
        XCTAssertEqual(asset.captureReason, .dictationCompleted)
    }

    func testCoordinatorWritesAgentDispatchAssetWhenPostASRWorkflowFails() throws {
        let assetRepository = CapturingVoiceTaskAssetRepository()
        let coordinator = makeCoordinator(assetRepository: assetRepository)
        try coordinator.startTask(mode: .agentDispatch, target: nil)
        try coordinator.recordRawTranscript("Codex 失败前的语音", kind: .agentDispatch)

        try coordinator.recordFailure(
            stage: "agentDispatch",
            code: "agent_dispatch_failed",
            message: "Router failed",
            recoverable: true,
            kind: .agentDispatch
        )

        XCTAssertEqual(assetRepository.savedItems.count, 1)
        let asset = try XCTUnwrap(assetRepository.savedItems.first)
        XCTAssertEqual(asset.source, .dictation)
        XCTAssertEqual(asset.text, "Codex 失败前的语音")
        XCTAssertEqual(asset.rawText, "Codex 失败前的语音")
        XCTAssertEqual(asset.captureReason, .dictationCompleted)
    }

    // MARK: - Helpers

    private func makeCoordinator(
        pipeline: any TextProcessing = CoordinatorStubTextPipeline(
            result: TextProcessingResult(rawText: "", finalText: "")
        ),
        outputService: any OutputService = CoordinatorStubOutputService(result: .injected),
        targetProvider: CoordinatorMutableTargetProvider = CoordinatorMutableTargetProvider(target: nil),
        contextPipeline: (any ContextCollecting)? = nil,
        agentRefiner: (any PromptAwareTextRefining)? = nil,
        correctionObservationScheduler: (any CorrectionObservationScheduling)? = nil,
        assetRepository: (any AssetRepository)? = nil,
        isFocusedTextFieldSecure: @escaping @MainActor () -> Bool = { false }
    ) -> VoiceTaskCoordinator {
        VoiceTaskCoordinator(
            taskRepository: repository,
            outputService: outputService,
            textPipeline: pipeline,
            targetProvider: targetProvider,
            clock: clock,
            contextPipeline: contextPipeline,
            agentRefiner: agentRefiner,
            correctionObservationScheduler: correctionObservationScheduler,
            assetRepository: assetRepository,
            isFocusedTextFieldSecure: isFocusedTextFieldSecure
        )
    }
}

// MARK: - Test Doubles

@MainActor
private final class CoordinatorStubTextPipeline: TextProcessing {
    let result: TextProcessingResult

    init(result: TextProcessingResult) {
        self.result = result
    }

    func process(_ rawText: String) async -> TextProcessingResult {
        result
    }

    func process(_ rawText: String, target: DictationTarget?) async -> TextProcessingResult {
        TextProcessingResult(
            rawText: rawText,
            finalText: result.finalText,
            llmProviderID: result.llmProviderID,
            styleID: result.styleID,
            warnings: result.warnings,
            trace: result.trace,
            correctionEvents: result.correctionEvents,
            appliedCorrectionEvents: result.appliedCorrectionEvents
        )
    }

    func process(
        _ rawText: String,
        target: DictationTarget?,
        correctionContext: CorrectionContext?,
        onRefinedTextUpdate: @escaping @MainActor (String) -> Void
    ) async -> TextProcessingResult {
        await process(rawText, target: target)
    }
}

@MainActor
private final class CoordinatorCapturingContextPipeline: TextProcessing {
    let result: TextProcessingResult
    private(set) var capturedContexts: [CorrectionContext] = []

    init(result: TextProcessingResult) {
        self.result = result
    }

    func process(_ rawText: String) async -> TextProcessingResult {
        result
    }

    func process(_ rawText: String, target: DictationTarget?) async -> TextProcessingResult {
        result
    }

    func process(
        _ rawText: String,
        target: DictationTarget?,
        correctionContext: CorrectionContext?,
        onRefinedTextUpdate: @escaping @MainActor (String) -> Void
    ) async -> TextProcessingResult {
        if let correctionContext {
            capturedContexts.append(correctionContext)
        }
        return result
    }
}

@MainActor
private final class CapturingCorrectionObservationScheduler: CorrectionObservationScheduling {
    private(set) var observations: [
        (
            insertedText: String,
            context: CorrectionContext,
            appliedEvents: [CorrectionEvent],
            baseline: FocusedTextObservation?,
            targetProcessID: Int?
        )
    ] = []
    private(set) var capturedTargetProcessIDs: [Int?] = []
    var captureBaselineResult: FocusedTextObservation?
    var recaptureBaselineResult: FocusedTextObservation?

    func scheduleObservation(
        insertedText: String,
        context: CorrectionContext,
        appliedEvents: [CorrectionEvent],
        baseline: FocusedTextObservation?,
        targetProcessID: Int?
    ) {
        observations.append((insertedText, context, appliedEvents, baseline, targetProcessID))
    }

    func captureBaselineForObservation(targetProcessID: Int?) -> FocusedTextObservation? {
        capturedTargetProcessIDs.append(targetProcessID)
        return captureBaselineResult
    }

    func recaptureBaselineForObservation(matching baseline: FocusedTextObservation) -> FocusedTextObservation? {
        recaptureBaselineResult
    }
}

@MainActor
private final class CoordinatorCancellingTextPipeline: TextProcessing {
    let result: TextProcessingResult
    let onProcess: () -> Void

    init(
        result: TextProcessingResult,
        onProcess: @escaping () -> Void
    ) {
        self.result = result
        self.onProcess = onProcess
    }

    func process(_ rawText: String) async -> TextProcessingResult {
        onProcess()
        return result
    }

    func process(_ rawText: String, target: DictationTarget?) async -> TextProcessingResult {
        onProcess()
        return TextProcessingResult(
            rawText: rawText,
            finalText: result.finalText,
            llmProviderID: result.llmProviderID,
            styleID: result.styleID,
            warnings: result.warnings,
            trace: result.trace,
            correctionEvents: result.correctionEvents,
            appliedCorrectionEvents: result.appliedCorrectionEvents
        )
    }
}

@MainActor
private final class CoordinatorStubOutputService: OutputService {
    let result: OutputResult
    private(set) var lastText: String?
    private(set) var lastMode: VoiceTaskMode?
    private(set) var lastTarget: DictationTarget?
    private(set) var lastOriginalTarget: DictationTarget?
    private(set) var lastCurrentTarget: DictationTarget?

    init(result: OutputResult) {
        self.result = result
    }

    func deliver(
        text: String,
        mode: VoiceTaskMode,
        target: DictationTarget?,
        originalTarget: DictationTarget?
    ) async -> OutputResult {
        lastText = text
        lastMode = mode
        lastTarget = target
        lastOriginalTarget = originalTarget
        lastCurrentTarget = target
        return result
    }
}

private final class CapturingVoiceTaskAssetRepository: AssetRepository {
    private(set) var savedItems: [AssetItem] = []

    func save(_ item: AssetItem) throws {
        savedItems.removeAll { $0.id == item.id }
        savedItems.append(item)
    }

    func asset(id: String) throws -> AssetItem? {
        savedItems.first { $0.id == id && $0.deletedAt == nil }
    }

    func page(query: AssetQuery) throws -> AssetPage {
        AssetPage(items: savedItems, totalCount: savedItems.count)
    }

    func softDelete(id: String, deletedAt: Date) throws {}
}

private final class HandlerClipboardService: ClipboardSetting {
    private(set) var copiedTexts: [String] = []

    func setString(_ text: String) -> Bool {
        copiedTexts.append(text)
        return true
    }
}

private final class HandlerDirectAgentRouter: AgentRouting, @unchecked Sendable {
    let agent: AgentSessionCard
    let message: String

    init(agent: AgentSessionCard, message: String) {
        self.agent = agent
        self.message = message
    }

    func listAgents() async throws -> [AgentSessionCard] {
        [agent]
    }

    func resolve(utterance: String) async throws -> AgentResolveOutcome {
        .direct(agentID: agent.agentID, message: message, matchedBy: "exact_name")
    }

    func send(_ request: AgentDispatchRequest) async throws {}

    func learnAlias(_ alias: String, agentID: String, userConfirmed: Bool) async throws {}
}

private final class HandlerNoAgentRouter: AgentRouting, @unchecked Sendable {
    func listAgents() async throws -> [AgentSessionCard] {
        []
    }

    func resolve(utterance: String) async throws -> AgentResolveOutcome {
        .notFound
    }

    func send(_ request: AgentDispatchRequest) async throws {}

    func learnAlias(_ alias: String, agentID: String, userConfirmed: Bool) async throws {}
}

private final class HandlerAmbiguousAgentRouter: AgentRouting, @unchecked Sendable {
    private let agent = AgentSessionCard(
        schemaVersion: 1,
        agentID: "codex",
        cli: "codex",
        command: ["codex"],
        cwd: "/tmp",
        status: .active,
        displayName: "Codex"
    )

    func listAgents() async throws -> [AgentSessionCard] {
        [agent]
    }

    func resolve(utterance: String) async throws -> AgentResolveOutcome {
        .ambiguous(candidates: [agent.agentID])
    }

    func send(_ request: AgentDispatchRequest) async throws {}

    func learnAlias(_ alias: String, agentID: String, userConfirmed: Bool) async throws {}
}

private actor HandlerAsyncGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func open() {
        guard !isOpen else { return }
        isOpen = true
        let pendingWaiters = waiters
        waiters.removeAll()
        pendingWaiters.forEach { $0.resume() }
    }
}

private final class HandlerDelayedResolveRouter: AgentRouting, @unchecked Sendable {
    private let resolveStarted = HandlerAsyncGate()
    private let resolveRelease = HandlerAsyncGate()
    private let agent = AgentSessionCard(
        schemaVersion: 1,
        agentID: "codex",
        cli: "codex",
        command: ["codex"],
        cwd: "/tmp",
        status: .active,
        displayName: "Codex"
    )

    func listAgents() async throws -> [AgentSessionCard] { [agent] }

    func resolve(utterance: String) async throws -> AgentResolveOutcome {
        await resolveStarted.open()
        await resolveRelease.wait()
        return .direct(agentID: agent.agentID, message: utterance, matchedBy: "exact_name")
    }

    func send(_ request: AgentDispatchRequest) async throws {}
    func learnAlias(_ alias: String, agentID: String, userConfirmed: Bool) async throws {}

    func waitUntilResolveStarts() async { await resolveStarted.wait() }
    func resumeResolve() async { await resolveRelease.open() }
}

private final class HandlerDelayedConfirmRouter: AgentRouting, @unchecked Sendable {
    private let sendStarted = HandlerAsyncGate()
    private let sendRelease = HandlerAsyncGate()
    private let agent = AgentSessionCard(
        schemaVersion: 1,
        agentID: "codex",
        cli: "codex",
        command: ["codex"],
        cwd: "/tmp",
        status: .active,
        displayName: "Codex"
    )

    func listAgents() async throws -> [AgentSessionCard] { [agent] }
    func resolve(utterance: String) async throws -> AgentResolveOutcome {
        .ambiguous(candidates: [agent.agentID])
    }

    func send(_ request: AgentDispatchRequest) async throws {
        await sendStarted.open()
        await sendRelease.wait()
    }

    func learnAlias(_ alias: String, agentID: String, userConfirmed: Bool) async throws {}

    func waitUntilSendStarts() async { await sendStarted.wait() }
    func resumeSend() async { await sendRelease.open() }
}

private extension AgentDispatchHUDPresentation {
    var isConfirmationForTest: Bool {
        if case .confirmation = self { return true }
        return false
    }
}

private func drainVoiceTaskMainActorTasks() async {
    for _ in 0..<10 {
        await Task.yield()
    }
}

@MainActor
private func waitUntilVoiceTaskTestCondition(
    timeoutNanoseconds: UInt64 = 1_000_000_000,
    _ condition: @escaping () -> Bool
) async -> Bool {
    let deadline = ContinuousClock.now + .nanoseconds(Int64(timeoutNanoseconds))
    while ContinuousClock.now < deadline {
        if condition() {
            return true
        }
        try? await Task.sleep(nanoseconds: 1_000_000)
    }
    return condition()
}

@MainActor
private final class CoordinatorCancellingOutputService: OutputService {
    let result: OutputResult
    let onDeliver: (VoiceTaskCoordinator) -> Void
    weak var coordinator: VoiceTaskCoordinator?

    init(
        result: OutputResult,
        onDeliver: @escaping (VoiceTaskCoordinator) -> Void
    ) {
        self.result = result
        self.onDeliver = onDeliver
    }

    func deliver(
        text: String,
        mode: VoiceTaskMode,
        target: DictationTarget?,
        originalTarget: DictationTarget?
    ) async -> OutputResult {
        if let coordinator {
            onDeliver(coordinator)
        }
        return result
    }
}

@MainActor
private final class CoordinatorMutableTargetProvider: DictationTargetProviding {
    var target: DictationTarget?

    init(target: DictationTarget?) {
        self.target = target
    }

    func currentTarget() -> DictationTarget? {
        target
    }
}

private final class CoordinatorStubPromptRefiner: PromptAwareTextRefining, @unchecked Sendable {
    var isEnabled = true
    var isConfigured = true
    private let result: String

    init(result: String) {
        self.result = result
    }

    func refine(_ text: String) async throws -> String {
        result
    }

    func refine(_ request: TextRefinementRequest) async throws -> String {
        result
    }
}

private final class CoordinatorTraceableStreamingRefiner: TextRefining, TraceableStreamingPromptAwareTextRefining, RefinementTraceProviding, @unchecked Sendable {
    var isEnabled = true
    var isConfigured = true
    private let snapshots: [String]
    private let trace: LLMRefinementTrace
    private(set) var lastTrace: LLMRefinementTrace?

    init(
        snapshots: [String],
        trace: LLMRefinementTrace,
        lastTrace: LLMRefinementTrace?
    ) {
        self.snapshots = snapshots
        self.trace = trace
        self.lastTrace = lastTrace
    }

    func refine(_ text: String) async throws -> String {
        "blocking path should not be used"
    }

    func refine(_ request: TextRefinementRequest) async throws -> String {
        "blocking path should not be used"
    }

    func refineStream(_ request: TextRefinementRequest) -> AsyncThrowingStream<String, Error> {
        refineStreamWithTrace(request).stream
    }

    func refineStreamWithTrace(_ request: TextRefinementRequest) -> TextRefinementStreamTraceResult {
        let traceHandle = TextRefinementTraceHandle()
        let stream = AsyncThrowingStream<String, Error> { continuation in
            for snapshot in snapshots {
                continuation.yield(snapshot)
            }
            traceHandle.complete(trace)
            continuation.finish()
        }
        return TextRefinementStreamTraceResult(
            stream: stream,
            providerID: trace.providerID,
            trace: traceHandle
        )
    }

    func clearLastTrace() {}
}

private final class CoordinatorTestClock: AppClock, @unchecked Sendable {
    var now: Date

    init(now: Date) {
        self.now = now
    }

    func sleep(nanoseconds: UInt64) async throws {}
}

private actor CancellableContextCollector: ContextCollecting {
    private(set) var collectCount = 0
    private(set) var cancelledCount = 0

    func collect(target: DictationTarget?, visionSupported: Bool) async -> ContextSnapshot {
        collectCount += 1
        do {
            try await Task.sleep(nanoseconds: 10_000_000_000)
        } catch {
            cancelledCount += 1
        }
        return ContextSnapshot(
            windowTitle: target?.windowTitle,
            targetAppBundleID: target?.bundleID,
            targetAppName: target?.appName,
            visibleText: nil,
            selectedText: nil,
            inputAreaText: nil,
            visualContentAvailable: false,
            sources: [],
            trimmedLength: 0,
            warnings: [],
        )
    }

    func waitUntilCancelled(timeoutNanoseconds: UInt64 = 1_000_000_000) async -> Bool {
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
        while DispatchTime.now().uptimeNanoseconds < deadline {
            if cancelledCount > 0 {
                return true
            }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        return cancelledCount > 0
    }
}
