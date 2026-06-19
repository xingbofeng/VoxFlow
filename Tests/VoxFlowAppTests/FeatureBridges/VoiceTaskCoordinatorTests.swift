import Foundation
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

        let snapshot = await coordinator.awaitContextCollection(timeoutMilliseconds: 1)
        try await Task.sleep(nanoseconds: 20_000_000)

        XCTAssertEqual(snapshot?.warnings, ["context_collection_timeout"])
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

    // MARK: - Helpers

    private func makeCoordinator(
        pipeline: any TextProcessing = CoordinatorStubTextPipeline(
            result: TextProcessingResult(rawText: "", finalText: "")
        ),
        outputService: any OutputService = CoordinatorStubOutputService(result: .injected),
        targetProvider: CoordinatorMutableTargetProvider = CoordinatorMutableTargetProvider(target: nil),
        contextPipeline: (any ContextCollecting)? = nil
    ) -> VoiceTaskCoordinator {
        VoiceTaskCoordinator(
            taskRepository: repository,
            outputService: outputService,
            textPipeline: pipeline,
            targetProvider: targetProvider,
            clock: clock,
            contextPipeline: contextPipeline
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
            trace: result.trace
        )
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
            trace: result.trace
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
}
