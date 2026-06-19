import Foundation
import XCTest
@testable import VoxFlowApp

@MainActor
final class ContextAwareWorkflowIntegrationTests: XCTestCase {
    nonisolated(unsafe) private var databaseQueue: DatabaseQueue!
    nonisolated(unsafe) private var repository: VoiceTaskRepository!
    private let clock = IntegrationTestClock(
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

    // MARK: - testFullDictationSuccessPath

    func testFullDictationSuccessPath() async throws {
        let pipeline = IntegrationStubTextPipeline(
            result: TextProcessingResult(rawText: "raw text", finalText: "processed text")
        )
        let outputService = IntegrationStubOutputService(result: .injected)
        let coordinator = makeCoordinator(
            pipeline: pipeline,
            outputService: outputService
        )
        let target = DictationTarget(
            bundleID: "com.example.notes",
            appName: "Notes",
            pid: 100,
            windowTitle: "My Note"
        )

        // 1. Start task
        let task = try coordinator.startTask(mode: .dictation, target: target)
        XCTAssertEqual(task.stage, .recording)
        XCTAssertEqual(task.mode, .dictation)

        // 2. Record transcript
        try coordinator.recordRawTranscript("raw text from speech", kind: .dictation)
        let afterTranscript = try repository.fetch(id: task.id)
        XCTAssertEqual(afterTranscript?.stage, .transcribing)

        // 3. Process and deliver
        let result = try await coordinator.processAndDeliver(kind: .dictation)
        XCTAssertEqual(result, .injected)

        // 4. Verify final state
        let completed = try repository.fetch(id: task.id)
        XCTAssertEqual(completed?.status, .completed)
        XCTAssertEqual(completed?.finalText, "processed text")
        XCTAssertNotNil(completed?.completedAt)
    }

    // MARK: - testWindowChangeFallsBackToCopy

    func testWindowChangeFallsBackToCopy() async throws {
        let target1 = DictationTarget(
            bundleID: "com.example.app1",
            appName: "App1",
            pid: 100,
            windowID: "win-1"
        )
        let target2 = DictationTarget(
            bundleID: "com.example.app2",
            appName: "App2",
            pid: 200,
            windowID: "win-2"
        )

        let pipeline = IntegrationStubTextPipeline(
            result: TextProcessingResult(rawText: "raw", finalText: "final")
        )
        let outputService = IntegrationStubOutputService(
            result: .targetChanged(reason: "Application changed")
        )
        let targetProvider = IntegrationMutableTargetProvider(target: target1)
        let coordinator = makeCoordinator(
            pipeline: pipeline,
            outputService: outputService,
            targetProvider: targetProvider
        )

        // Start on app1
        let task = try coordinator.startTask(mode: .dictation, target: target1)
        try coordinator.recordRawTranscript("raw", kind: .dictation)

        // Switch to app2 before delivery
        targetProvider.target = target2

        let result = try await coordinator.processAndDeliver(kind: .dictation)

        // Should fall back to copy since target changed
        XCTAssertEqual(result, .targetChanged(reason: "Application changed"))
        let completed = try repository.fetch(id: task.id)
        XCTAssertEqual(completed?.status, .partiallyCompleted)
        XCTAssertEqual(completed?.finalText, "final")
    }

    // MARK: - testAgentComposeSuccessPath

    func testAgentComposeSuccessPath() async throws {
        let refiner = IntegrationStubRefiner(result: "Generated professional reply")
        let outputService = IntegrationStubOutputService(result: .copied)
        let coordinator = makeCoordinator(
            outputService: outputService,
            agentRefiner: refiner
        )

        let context = ContextSnapshot(
            windowTitle: "Inbox - Mail",
            targetAppBundleID: "com.apple.mail",
            targetAppName: "Mail",
            visibleText: "Subject: Project update needed\nFrom: boss@company.com",
            sources: [.windowMetadata, .accessibilityVisibleText],
            trimmedLength: 60
        )

        // 1. Start agent compose task
        let task = try coordinator.startTask(mode: .agentCompose, target: nil)
        XCTAssertEqual(task.mode, .agentCompose)

        // 2. Record user dictation
        try coordinator.recordRawTranscript("reply that I'll send the update by Friday")

        // 3. Process with context
        let result = try await coordinator.processAgentComposeAndDeliver(
            context: context,
            stylePrompt: nil
        )

        XCTAssertEqual(result, .copied)

        // 4. Verify
        let completed = try repository.fetch(id: task.id)
        XCTAssertEqual(completed?.status, .completed)
        XCTAssertEqual(completed?.finalText, "Generated professional reply")
        XCTAssertNotNil(completed?.contextJson)
    }

    func testAgentComposePersistsRedactedLLMTraceForDetailInspection() async throws {
        let trace = LLMRefinementTrace(
            providerID: "provider-1",
            providerName: "OpenAI 兼容配置",
            endpoint: "https://api.example.com/v1/chat/completions",
            model: "gpt-test",
            temperature: 0.2,
            timeoutSeconds: 8,
            requestBodyJSON: #"{"messages":[{"role":"user","content":"帮我回复微信"}]}"#,
            responseText: "可以，我六点前发给你。",
            statusCode: 200,
            durationMS: 321,
            errorMessage: nil
        )
        let refiner = IntegrationStubRefiner(
            result: "可以，我六点前发给你。",
            trace: trace
        )
        let outputService = IntegrationStubOutputService(result: .copied)
        let coordinator = makeCoordinator(
            outputService: outputService,
            agentRefiner: refiner
        )
        let task = try coordinator.startTask(mode: .agentCompose, target: nil)
        try coordinator.recordRawTranscript("帮我回复微信")

        _ = try await coordinator.processAgentComposeAndDeliver(
            context: nil,
            stylePrompt: nil
        )

        let completed = try XCTUnwrap(repository.fetch(id: task.id))
        let traceJSON = try XCTUnwrap(completed.trace)
        let decoded = try JSONDecoder().decode(TextProcessingTrace.self, from: Data(traceJSON.utf8))
        XCTAssertEqual(decoded.llm?.model, "gpt-test")
        XCTAssertTrue(decoded.llm?.requestBodyJSON.contains("[redacted: user content]") == true)
        XCTAssertNil(decoded.llm?.responseText)
        XCTAssertFalse(traceJSON.contains("帮我回复微信"))
        XCTAssertFalse(traceJSON.contains("可以，我六点前发给你。"))
    }

    // MARK: - testContextFailureDegradation

    func testContextFailureDegradation() async throws {
        let refiner = IntegrationStubRefiner(result: "Simple text from dictation alone")
        let outputService = IntegrationStubOutputService(result: .copied)
        let coordinator = makeCoordinator(
            outputService: outputService,
            agentRefiner: refiner
        )

        let task = try coordinator.startTask(mode: .agentCompose, target: nil)
        try coordinator.recordRawTranscript("write something simple")

        // Context collection failed (nil context)
        let result = try await coordinator.processAgentComposeAndDeliver(
            context: nil,
            stylePrompt: nil
        )

        // Should still succeed using dictation alone
        XCTAssertEqual(result, .copied)
        let completed = try repository.fetch(id: task.id)
        XCTAssertEqual(completed?.status, .completed)
        XCTAssertEqual(completed?.finalText, "Simple text from dictation alone")
    }

    // MARK: - testLLMFailureRecovery

    func testLLMFailureRecovery() async throws {
        let refiner = IntegrationStubRefiner(error: IntegrationStubError.serviceUnavailable)
        let outputService = IntegrationStubOutputService(result: .copied)
        let coordinator = makeCoordinator(
            outputService: outputService,
            agentRefiner: refiner
        )

        let task = try coordinator.startTask(mode: .agentCompose, target: nil)
        try coordinator.recordRawTranscript("compose something")

        // LLM fails
        do {
            _ = try await coordinator.processAgentComposeAndDeliver(
                context: nil,
                stylePrompt: nil
            )
            XCTFail("Should have thrown")
        } catch let error as CoordinatorError {
            if case .llmCallFailed = error {
                // Expected - the task text is preserved for retry from home page
            } else {
                XCTFail("Wrong error type")
            }
        }

        // The raw transcript is still in the task for retry
        let fetched = try repository.fetch(id: task.id)
        XCTAssertEqual(fetched?.rawTranscript, "compose something")
        XCTAssertTrue(fetched?.warnings.contains("agent_llm_failed") ?? false)
    }

    // MARK: - testIncompleteTaskDetectedOnRestart

    func testIncompleteTaskDetectedOnRestart() async throws {
        // Create an incomplete task (simulating a crash mid-processing)
        let incomplete = VoiceTask(
            id: "incomplete-agent-1",
            mode: .agentCompose,
            stage: .processing,
            status: .inProgress,
            targetAppName: "Slack",
            rawTranscript: "send update to team",
            createdAt: clock.now,
            updatedAt: clock.now
        )
        try repository.create(incomplete)

        // Also create a completed task
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

        // On restart, check for incomplete tasks
        let coordinator = makeCoordinator()
        let tasks = try coordinator.checkIncompleteTasks()

        XCTAssertEqual(tasks.count, 1)
        XCTAssertEqual(tasks.first?.id, "incomplete-agent-1")
        XCTAssertEqual(tasks.first?.mode, .agentCompose)
        XCTAssertEqual(tasks.first?.rawTranscript, "send update to team")
    }

    // MARK: - Helpers

    private func makeCoordinator(
        pipeline: IntegrationStubTextPipeline = IntegrationStubTextPipeline(
            result: TextProcessingResult(rawText: "", finalText: "")
        ),
        outputService: IntegrationStubOutputService = IntegrationStubOutputService(result: .injected),
        targetProvider: IntegrationMutableTargetProvider = IntegrationMutableTargetProvider(target: nil),
        agentRefiner: IntegrationStubRefiner? = nil
    ) -> VoiceTaskCoordinator {
        VoiceTaskCoordinator(
            taskRepository: repository,
            outputService: outputService,
            textPipeline: pipeline,
            targetProvider: targetProvider,
            clock: clock,
            contextPipeline: nil,
            agentRefiner: agentRefiner
        )
    }
}

// MARK: - Test Doubles

@MainActor
private final class IntegrationStubTextPipeline: TextProcessing {
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
private final class IntegrationStubOutputService: OutputService {
    let result: OutputResult
    private(set) var lastText: String?
    private(set) var lastMode: VoiceTaskMode?

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
        return result
    }
}

@MainActor
private final class IntegrationMutableTargetProvider: DictationTargetProviding {
    var target: DictationTarget?

    init(target: DictationTarget?) {
        self.target = target
    }

    func currentTarget() -> DictationTarget? {
        target
    }
}

private final class IntegrationStubRefiner: PromptAwareTextRefining, RefinementTraceProviding, @unchecked Sendable {
    let result: String?
    let error: Error?
    private let trace: LLMRefinementTrace?
    private(set) var lastTrace: LLMRefinementTrace?

    init(result: String? = nil, error: Error? = nil, trace: LLMRefinementTrace? = nil) {
        self.result = result
        self.error = error
        self.trace = trace
        self.lastTrace = nil
    }

    var isEnabled: Bool { true }
    var isConfigured: Bool { true }
    func clearLastTrace() {
        lastTrace = nil
    }

    func refine(_ text: String) async throws -> String {
        if let error { throw error }
        lastTrace = trace
        return result ?? text
    }

    func refine(_ request: TextRefinementRequest) async throws -> String {
        if let error { throw error }
        lastTrace = trace
        return result ?? request.text
    }
}

private enum IntegrationStubError: Error {
    case serviceUnavailable
}

private final class IntegrationTestClock: AppClock, @unchecked Sendable {
    var now: Date

    init(now: Date) {
        self.now = now
    }

    func sleep(nanoseconds: UInt64) async throws {}
}
