import Foundation
import XCTest
@testable import VoiceInputApp

@MainActor
final class VoiceTaskCoordinatorTests: XCTestCase {
    private var databaseQueue: DatabaseQueue!
    private var repository: VoiceTaskRepository!
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

    // MARK: - Raw transcript

    func testCoordinatorRecordsRawTranscriptAfterASR() throws {
        let coordinator = makeCoordinator()
        let task = try coordinator.startTask(mode: .dictation, target: nil)

        try coordinator.recordRawTranscript("hello world")

        let fetched = try repository.fetch(id: task.id)
        XCTAssertEqual(fetched?.rawTranscript, "hello world")
        XCTAssertEqual(fetched?.stage, .transcribing)
    }

    func testCoordinatorTrimsWhitespaceFromTranscript() throws {
        let coordinator = makeCoordinator()
        let task = try coordinator.startTask(mode: .dictation, target: nil)

        try coordinator.recordRawTranscript("  hello world  ")

        let fetched = try repository.fetch(id: task.id)
        XCTAssertEqual(fetched?.rawTranscript, "hello world")
    }

    func testCoordinatorIgnoresEmptyTranscript() throws {
        let coordinator = makeCoordinator()
        let task = try coordinator.startTask(mode: .dictation, target: nil)

        try coordinator.recordRawTranscript("   ")

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
        try coordinator.recordRawTranscript("raw")

        _ = try await coordinator.processAndDeliver()

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
        try coordinator.recordRawTranscript("raw")

        let result = try await coordinator.processAndDeliver()

        XCTAssertEqual(result, .injected)
        let fetched = try repository.fetch(id: task.id)
        XCTAssertEqual(fetched?.status, .completed)
        XCTAssertNotNil(fetched?.completedAt)
        XCTAssertNotNil(fetched?.outputResult)
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
        let task = try coordinator.startTask(mode: .agentCompose, target: nil)
        try coordinator.recordRawTranscript("raw")

        let result = try await coordinator.processAndDeliver()

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
        try coordinator.recordRawTranscript("raw")

        let result = try await coordinator.processAndDeliver()

        XCTAssertEqual(result, .injectionFailed(reason: "Accessibility denied"))
        let fetched = try repository.fetch(id: task.id)
        XCTAssertEqual(fetched?.status, .partiallyCompleted)
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
        try coordinator.recordRawTranscript("raw text")

        let result = try await coordinator.processAndDeliver()

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

        try coordinator.recordRawTranscript("raw")
        let afterTranscript = try repository.fetch(id: task.id)
        XCTAssertEqual(afterTranscript?.stage, .transcribing)

        _ = try await coordinator.processAndDeliver()
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
        try coordinator.recordRawTranscript("raw")

        _ = try await coordinator.processAndDeliver()

        XCTAssertEqual(outputService.lastOriginalTarget, target)
        XCTAssertEqual(outputService.lastCurrentTarget, target)
        XCTAssertEqual(outputService.lastMode, .dictation)
    }

    // MARK: - Helpers

    private func makeCoordinator(
        pipeline: CoordinatorStubTextPipeline = CoordinatorStubTextPipeline(
            result: TextProcessingResult(rawText: "", finalText: "")
        ),
        outputService: CoordinatorStubOutputService = CoordinatorStubOutputService(result: .injected),
        targetProvider: CoordinatorMutableTargetProvider = CoordinatorMutableTargetProvider(target: nil)
    ) -> VoiceTaskCoordinator {
        VoiceTaskCoordinator(
            taskRepository: repository,
            outputService: outputService,
            textPipeline: pipeline,
            targetProvider: targetProvider,
            clock: clock
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
