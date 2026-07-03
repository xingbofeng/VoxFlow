import Foundation
import XCTest
@testable import VoxFlowApp

@MainActor
final class AgentComposeTests: XCTestCase {
    nonisolated(unsafe) private var databaseQueue: DatabaseQueue!
    nonisolated(unsafe) private var repository: VoiceTaskRepository!
    private let clock = AgentComposeTestClock(
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

    // MARK: - testAgentComposeDeliversGeneratedTextViaOutputService

    func testAgentComposeDeliversGeneratedTextViaOutputService() async throws {
        let refiner = AgentComposeStubRefiner(result: "Generated text")
        let outputService = AgentComposeStubOutputService(result: .copied)
        let coordinator = makeCoordinator(
            outputService: outputService,
            agentRefiner: refiner
        )
        let task = try coordinator.startTask(mode: .agentCompose, target: nil)
        try coordinator.recordRawTranscript("tell them hello")

        let result = try await coordinator.processAgentComposeAndDeliver(
            context: nil,
            stylePrompt: nil
        )

        XCTAssertEqual(result, .copied)
        XCTAssertEqual(outputService.lastMode, .agentCompose)
        XCTAssertEqual(outputService.lastText, "Generated text")
        let fetched = try repository.fetch(id: task.id)
        XCTAssertEqual(fetched?.finalText, "Generated text")
        XCTAssertEqual(fetched?.status, .completed)
    }

    // MARK: - testAgentComposeUsesAgentComposeOutputMode

    func testAgentComposeUsesAgentComposeOutputMode() async throws {
        let refiner = AgentComposeStubRefiner(result: "Generated text")
        let outputService = AgentComposeStubOutputService(result: .copied)
        let coordinator = makeCoordinator(
            outputService: outputService,
            agentRefiner: refiner
        )
        _ = try coordinator.startTask(mode: .agentCompose, target: nil)
        try coordinator.recordRawTranscript("compose something")

        let result = try await coordinator.processAgentComposeAndDeliver(
            context: nil,
            stylePrompt: nil
        )

        XCTAssertEqual(outputService.lastMode, .agentCompose)
        XCTAssertEqual(result, .copied)
    }

    func testCodexRuntimeProviderCompletesWithoutDeliveringTextOutput() async throws {
        let assetRepository = AgentComposeCapturingAssetRepository()
        let outputService = AgentComposeStubOutputService(result: .copied)
        let runtimeService = AgentComposeRuntimeServiceStub(
            availability: .available(),
            result: .successSummary("Opened Google")
        )
        let coordinator = makeCoordinator(
            outputService: outputService,
            agentRuntimeService: runtimeService,
            assetRepository: assetRepository,
            agentRuntimeSelection: {
                AgentRuntimeProviderSelection(providerID: "codex", model: "gpt-5.5")
            }
        )
        let task = try coordinator.startTask(mode: .agentCompose, target: nil)
        try coordinator.recordRawTranscript("打开 Google")

        let result = try await coordinator.processAgentComposeAndDeliver(
            context: nil,
            stylePrompt: nil
        )

        XCTAssertEqual(result, .cancelled)
        XCTAssertNil(outputService.lastText)
        XCTAssertEqual(runtimeService.lastInstruction, "打开 Google")
        let fetched = try XCTUnwrap(repository.fetch(id: task.id))
        XCTAssertEqual(fetched.status, .completed)
        XCTAssertEqual(fetched.finalText, "Opened Google")
        let traceJSON = try XCTUnwrap(fetched.trace)
        let trace = try JSONDecoder().decode(TextProcessingTrace.self, from: Data(traceJSON.utf8))
        XCTAssertEqual(trace.agentAction?.providerID, "codex")
        XCTAssertEqual(trace.agentAction?.executionMode, .codexRuntime)
        XCTAssertEqual(trace.agentAction?.status, .completed)
        XCTAssertEqual(assetRepository.savedItems.count, 1)
        let asset = try XCTUnwrap(assetRepository.savedItems.first)
        XCTAssertEqual(asset.id, "dictation-\(task.id)")
        XCTAssertEqual(asset.text, "打开 Google")
        XCTAssertEqual(asset.rawText, "打开 Google")
        XCTAssertEqual(asset.source, .dictation)
    }

    func testDefaultHandlerOpensDetailAfterLocalAgentRuntimeCompletion() async throws {
        let runtimeService = AgentComposeRuntimeServiceStub(
            availability: .available(providerID: "codebuddy"),
            result: .successSummary("Opened Google", providerID: "codebuddy")
        )
        let coordinator = makeCoordinator(
            agentRuntimeService: runtimeService,
            agentRuntimeSelection: {
                AgentRuntimeProviderSelection(providerID: "codebuddy", model: "deepseek-v4-flash-202605")
            }
        )
        let handler = DefaultAgentComposeHandler(
            coordinator: coordinator,
            styleSelector: AgentComposeNilStyleSelector()
        )
        var openedTaskID: String?
        handler.onRuntimeCompleted = { openedTaskID = $0 }
        try handler.start(target: nil)
        let taskID = try XCTUnwrap(coordinator.activeTaskID(for: .agentCompose))

        let result = try await handler.finish(rawTranscript: "打开 Google")

        XCTAssertEqual(result, .cancelled)
        XCTAssertEqual(openedTaskID, taskID)
    }

    func testLocalAgentRuntimeUnavailableFallsBackToTextProvider() async throws {
        let refiner = AgentComposeStubRefiner(
            result: "Fallback generated text",
            trace: LLMRefinementTrace(
                providerID: "codebuddy",
                providerName: "CodeBuddy",
                endpoint: "local://codebuddy",
                model: "deepseek-v4-flash-202605",
                temperature: 0,
                timeoutSeconds: 60,
                requestBodyJSON: "{}",
                responseText: "Fallback generated text",
                statusCode: 200
            )
        )
        let outputService = AgentComposeStubOutputService(result: .copied)
        let runtimeService = AgentComposeRuntimeServiceStub(
            availability: .unavailable(reason: "missing runtime", providerID: "codebuddy"),
            result: nil
        )
        let coordinator = makeCoordinator(
            outputService: outputService,
            agentRefiner: refiner,
            agentRuntimeService: runtimeService,
            agentRuntimeSelection: {
                AgentRuntimeProviderSelection(providerID: "codebuddy", model: "deepseek-v4-flash-202605")
            }
        )
        let task = try coordinator.startTask(mode: .agentCompose, target: nil)
        try coordinator.recordRawTranscript("帮我写一句话")

        let result = try await coordinator.processAgentComposeAndDeliver(
            context: nil,
            stylePrompt: nil
        )

        XCTAssertEqual(result, .copied)
        XCTAssertEqual(outputService.lastText, "Fallback generated text")
        XCTAssertNil(runtimeService.lastInstruction)
        let fetched = try XCTUnwrap(repository.fetch(id: task.id))
        let traceJSON = try XCTUnwrap(fetched.trace)
        let trace = try JSONDecoder().decode(TextProcessingTrace.self, from: Data(traceJSON.utf8))
        XCTAssertEqual(trace.agentAction?.executionMode, .textOnly)
        XCTAssertEqual(trace.agentAction?.resultSummary, "已退回文本模式")
        XCTAssertNotNil(trace.llm)
    }

    func testLocalAgentRuntimeFailureDoesNotFallbackToTextProvider() async throws {
        let refiner = AgentComposeStubRefiner(result: "Should not be used")
        let outputService = AgentComposeStubOutputService(result: .copied)
        let runtimeService = AgentComposeRuntimeServiceStub(
            availability: .available(),
            result: nil,
            error: AgentRuntimeClientError.failed(
                AgentActionTrace(
                    providerID: "codebuddy",
                    executionMode: .localAgentRuntime,
                    status: .failed,
                    userInstruction: "打开 Google",
                    events: [
                        AgentActionEvent(
                            kind: .error,
                            title: "任务失败",
                            detail: "runtime failed",
                            timestamp: Date(timeIntervalSince1970: 1_800_000_001),
                            isFailure: true
                        )
                    ],
                    startedAt: Date(timeIntervalSince1970: 1_800_000_000),
                    completedAt: Date(timeIntervalSince1970: 1_800_000_001),
                    failureReason: "runtime failed"
                )
            )
        )
        let coordinator = makeCoordinator(
            outputService: outputService,
            agentRefiner: refiner,
            agentRuntimeService: runtimeService,
            agentRuntimeSelection: {
                AgentRuntimeProviderSelection(providerID: "codebuddy", model: "deepseek-v4-flash-202605")
            }
        )
        let task = try coordinator.startTask(mode: .agentCompose, target: nil)
        try coordinator.recordRawTranscript("打开 Google")

        do {
            _ = try await coordinator.processAgentComposeAndDeliver(
                context: nil,
                stylePrompt: nil
            )
            XCTFail("Expected runtime failure")
        } catch {
            XCTAssertEqual(outputService.lastText, nil)
        }

        let fetched = try XCTUnwrap(repository.fetch(id: task.id))
        let traceJSON = try XCTUnwrap(fetched.trace)
        let trace = try JSONDecoder().decode(TextProcessingTrace.self, from: Data(traceJSON.utf8))
        XCTAssertEqual(trace.agentAction?.status, .failed)
        XCTAssertEqual(trace.agentAction?.failureReason, "runtime failed")
    }

    func testDefaultHandlerRecordsLastFailedTaskIDAfterRuntimeFailure() async throws {
        let runtimeService = AgentComposeRuntimeServiceStub(
            availability: .available(),
            result: nil,
            error: AgentRuntimeClientError.failed(
                AgentActionTrace(
                    providerID: "codebuddy",
                    executionMode: .localAgentRuntime,
                    status: .failed,
                    userInstruction: "打开 Google",
                    events: [
                        AgentActionEvent(
                            kind: .error,
                            title: "任务失败",
                            detail: "runtime failed",
                            timestamp: Date(timeIntervalSince1970: 1_800_000_001),
                            isFailure: true
                        )
                    ],
                    startedAt: Date(timeIntervalSince1970: 1_800_000_000),
                    completedAt: Date(timeIntervalSince1970: 1_800_000_001),
                    failureReason: "runtime failed"
                )
            )
        )
        let coordinator = makeCoordinator(
            agentRuntimeService: runtimeService,
            agentRuntimeSelection: {
                AgentRuntimeProviderSelection(providerID: "codebuddy", model: "deepseek-v4-flash-202605")
            }
        )
        let handler = DefaultAgentComposeHandler(
            coordinator: coordinator,
            styleSelector: AgentComposeNilStyleSelector()
        )
        try handler.start(target: nil)
        let taskID = try XCTUnwrap(coordinator.activeTaskID(for: .agentCompose))

        do {
            _ = try await handler.finish(rawTranscript: "打开 Google")
            XCTFail("Expected runtime failure")
        } catch {
            handler.fail(error)
        }

        XCTAssertEqual(handler.lastFailedTaskID, taskID)
        let fetched = try XCTUnwrap(repository.fetch(id: taskID))
        XCTAssertEqual(fetched.status, .failed)
    }

    // MARK: - testAgentComposeNeverSimulatesEnter

    func testAgentComposeNeverSimulatesEnter() async throws {
        let refiner = AgentComposeStubRefiner(result: "Generated message")
        let outputService = AgentComposeStubOutputService(result: .copied)
        let coordinator = makeCoordinator(
            outputService: outputService,
            agentRefiner: refiner
        )
        try coordinator.startTask(mode: .agentCompose, target: nil)
        try coordinator.recordRawTranscript("send a message")

        _ = try await coordinator.processAgentComposeAndDeliver(
            context: nil,
            stylePrompt: nil
        )

        // No Enter key simulation or app-specific send is performed by the coordinator.
        XCTAssertEqual(outputService.lastMode, .agentCompose)
        XCTAssertFalse(outputService.didInject)
    }

    // MARK: - testContextFailureFallsBackToDictationOnly

    func testContextFailureFallsBackToDictationOnly() async throws {
        let refiner = AgentComposeStubRefiner(result: "Fallback text")
        let outputService = AgentComposeStubOutputService(result: .copied)
        let coordinator = makeCoordinator(
            outputService: outputService,
            agentRefiner: refiner
        )
        try coordinator.startTask(mode: .agentCompose, target: nil)
        try coordinator.recordRawTranscript("generate something")

        // Pass nil context (simulating context collection failure)
        let result = try await coordinator.processAgentComposeAndDeliver(
            context: nil,
            stylePrompt: nil
        )

        XCTAssertEqual(result, .copied)
        XCTAssertEqual(
            refiner.lastRequest?.text,
            """
            User's dictation intent:
            <user_dictation_intent>
            generate something
            </user_dictation_intent>
            """
        )
        XCTAssertFalse(refiner.lastRequest?.text.contains("Untrusted context data") ?? true)
    }

    func testDefaultHandlerWritesOnlyAgentComposeWorkflowWhenDictationIsAlsoActive() async throws {
        let refiner = AgentComposeStubRefiner(result: "Generated text")
        let outputService = AgentComposeStubOutputService(result: .copied)
        let coordinator = makeCoordinator(
            outputService: outputService,
            agentRefiner: refiner
        )
        let dictation = try coordinator.startTask(mode: .dictation, target: nil)
        let handler = DefaultAgentComposeHandler(
            coordinator: coordinator,
            styleSelector: AgentComposeNilStyleSelector()
        )
        try handler.start(target: nil)
        let agentComposeID = try XCTUnwrap(coordinator.activeTaskID(for: .agentCompose))

        _ = try await handler.finish(rawTranscript: "compose only")

        XCTAssertNil(try repository.fetch(id: dictation.id)?.rawTranscript)
        XCTAssertEqual(try repository.fetch(id: agentComposeID)?.rawTranscript, "compose only")
        XCTAssertEqual(try repository.fetch(id: agentComposeID)?.finalText, "Generated text")
    }

    func testDefaultHandlerDoesNotPassDictationCorrectionStyleIntoAgentComposePrompt() async throws {
        let refiner = AgentComposeStubRefiner(result: "Generated text")
        let outputService = AgentComposeStubOutputService(result: .copied)
        let coordinator = makeCoordinator(
            outputService: outputService,
            agentRefiner: refiner
        )
        let handler = DefaultAgentComposeHandler(
            coordinator: coordinator,
            styleSelector: AgentComposeFixedStyleSelector(
                prompt: #"{"polished":"只用于听写纠错","corrections":[],"key_terms":[]}"#
            )
        )

        try handler.start(target: nil)
        _ = try await handler.finish(rawTranscript: "生成一个 HTML。")

        let request = try XCTUnwrap(refiner.lastRequest)
        XCTAssertFalse(request.text.contains("Style guidance:"))
        XCTAssertFalse(request.text.contains("polished"))
        XCTAssertTrue(request.text.contains("生成一个 HTML。"))
    }

    func testDefaultHandlerDoesNotFailActiveTaskWhenStartIsRejectedByRunningWorkflow() throws {
        let coordinator = makeCoordinator()
        let handler = DefaultAgentComposeHandler(
            coordinator: coordinator,
            styleSelector: AgentComposeNilStyleSelector()
        )
        try handler.start(target: nil)
        let activeTaskID = try XCTUnwrap(coordinator.activeTaskID(for: .agentCompose))

        do {
            try handler.start(target: nil)
            XCTFail("Expected workflowAlreadyRunning")
        } catch {
            handler.fail(error)
        }

        XCTAssertEqual(coordinator.activeTaskID(for: .agentCompose), activeTaskID)
        let task = try XCTUnwrap(repository.fetch(id: activeTaskID))
        XCTAssertEqual(task.status, .inProgress)
        XCTAssertNil(handler.lastFailedTaskID)
    }

    func testDefaultHandlerDoesNotReportPreRecordingContextStageOrCopiedStageWhenCopyFails() async throws {
        let refiner = AgentComposeStubRefiner(result: "Generated text")
        let outputService = AgentComposeStubOutputService(
            result: .copyFailed(reason: "Clipboard unavailable")
        )
        let coordinator = makeCoordinator(
            outputService: outputService,
            agentRefiner: refiner
        )
        let handler = DefaultAgentComposeHandler(
            coordinator: coordinator,
            styleSelector: AgentComposeNilStyleSelector()
        )
        var stages: [AgentComposeHUDStage] = []
        handler.onStageChange = { stages.append($0) }

        try handler.start(target: nil)
        let result = try await handler.finish(rawTranscript: "compose only")

        XCTAssertEqual(result, .copyFailed(reason: "Clipboard unavailable"))
        XCTAssertFalse(stages.contains(.copied))
        XCTAssertEqual(stages, [.transcribing, .generating])
    }

    func testAgentComposeCancellationDuringLLMDoesNotPersistFinalTextOrDeliverOutput() async throws {
        let refiner = AgentComposeCancellingRefiner(result: "Stale generated text")
        let outputService = AgentComposeStubOutputService(result: .copied)
        let coordinator = makeCoordinator(
            outputService: outputService,
            agentRefiner: refiner
        )
        let task = try coordinator.startTask(mode: .agentCompose, target: nil)
        try coordinator.recordRawTranscript("compose stale text")
        refiner.onRefine = {
            await MainActor.run {
                try? coordinator.cancelTask(kind: .agentCompose)
            }
        }

        let result = try await coordinator.processAgentComposeAndDeliver(
            context: nil,
            stylePrompt: nil
        )

        XCTAssertEqual(result, .cancelled)
        XCTAssertNil(outputService.lastText)
        let fetched = try repository.fetch(id: task.id)
        XCTAssertNil(fetched?.finalText)
        XCTAssertEqual(fetched?.status, .cancelled)
    }

    func testContextResultAfterAgentComposeCancellationIsDropped() async throws {
        let contextPipeline = AgentComposeImmediateContextCollector(
            snapshot: ContextSnapshot(
                windowTitle: "Old Window",
                targetAppBundleID: "com.old.app",
                targetAppName: "Old App",
                visibleText: "stale context",
                sources: [.windowMetadata],
                trimmedLength: 13
            )
        )
        let coordinator = makeCoordinator(contextPipeline: contextPipeline)
        try coordinator.startTask(mode: .agentCompose, target: nil)
        coordinator.startContextCollection(target: nil, visionSupported: true)
        try coordinator.cancelTask(kind: .agentCompose)

        let context = await coordinator.awaitContextCollection(timeoutMilliseconds: 1_000)

        XCTAssertNil(context)
    }

    // MARK: - testLLMFailureReturnsActionableError

    func testLLMFailureReturnsActionableError() async throws {
        let refiner = AgentComposeStubRefiner(error: AgentComposeStubError.networkTimeout)
        let outputService = AgentComposeStubOutputService(result: .copied)
        let coordinator = makeCoordinator(
            outputService: outputService,
            agentRefiner: refiner
        )
        try coordinator.startTask(mode: .agentCompose, target: nil)
        try coordinator.recordRawTranscript("compose something")

        do {
            _ = try await coordinator.processAgentComposeAndDeliver(
                context: nil,
                stylePrompt: nil
            )
            XCTFail("Should have thrown")
        } catch let error as CoordinatorError {
            if case .llmCallFailed = error {
                // Expected
                XCTAssertTrue(error.errorDescription?.contains("模型调用失败") ?? false)
            } else {
                XCTFail("Unexpected error type: \(error)")
            }
        }
    }

    // MARK: - testUnconfiguredLLMGuidesToConfig

    func testUnconfiguredLLMGuidesToConfig() async throws {
        let refiner = AgentComposeStubRefiner(result: "unused")
        refiner.configured = false
        let coordinator = makeCoordinator(agentRefiner: refiner)
        try coordinator.startTask(mode: .agentCompose, target: nil)
        try coordinator.recordRawTranscript("compose something")

        do {
            _ = try await coordinator.processAgentComposeAndDeliver(
                context: nil,
                stylePrompt: nil
            )
            XCTFail("Should have thrown")
        } catch let error as CoordinatorError {
            if case .llmNotConfigured = error {
                XCTAssertTrue(error.errorDescription?.contains("设置") ?? false)
            } else {
                XCTFail("Unexpected error type: \(error)")
            }
        }
    }

    // MARK: - testRegularDictationAvailableWithoutLLM

    func testRegularDictationAvailableWithoutLLM() async throws {
        // Coordinator without agent refiner should still work for dictation
        let pipeline = AgentComposeStubTextPipeline(
            result: TextProcessingResult(rawText: "raw", finalText: "processed")
        )
        let outputService = AgentComposeStubOutputService(result: .injected)
        let coordinator = makeCoordinator(
            pipeline: pipeline,
            outputService: outputService,
            agentRefiner: nil
        )
        try coordinator.startTask(mode: .dictation, target: nil)
        try coordinator.recordRawTranscript("raw")

        let result = try await coordinator.processAndDeliver()

        XCTAssertEqual(result, .injected)
    }

    // MARK: - testCopyFailureKeepsTextInTask

    func testCopyFailureKeepsTextInTask() async throws {
        let refiner = AgentComposeStubRefiner(result: "Important text")
        let outputService = AgentComposeStubOutputService(
            result: .copyFailed(reason: "Clipboard locked")
        )
        let coordinator = makeCoordinator(
            outputService: outputService,
            agentRefiner: refiner
        )
        let task = try coordinator.startTask(mode: .agentCompose, target: nil)
        try coordinator.recordRawTranscript("compose important text")

        let result = try await coordinator.processAgentComposeAndDeliver(
            context: nil,
            stylePrompt: nil
        )

        XCTAssertEqual(result, .copyFailed(reason: "Clipboard locked"))
        let fetched = try repository.fetch(id: task.id)
        // Text is preserved in task for home page retry
        XCTAssertEqual(fetched?.finalText, "Important text")
        XCTAssertEqual(fetched?.status, .partiallyCompleted)
    }

    // MARK: - testRecordsContextSnapshotInTrace

    func testRecordsContextSnapshotInTrace() async throws {
        let refiner = AgentComposeStubRefiner(result: "Generated from context")
        let outputService = AgentComposeStubOutputService(result: .copied)
        let coordinator = makeCoordinator(
            outputService: outputService,
            agentRefiner: refiner
        )
        let task = try coordinator.startTask(mode: .agentCompose, target: nil)
        try coordinator.recordRawTranscript("reply to this")

        let context = ContextSnapshot(
            windowTitle: "Chat Window",
            targetAppBundleID: "com.chat.app",
            targetAppName: "Chat",
            visibleText: "Previous message content",
            sources: [.windowMetadata, .accessibilityVisibleText],
            trimmedLength: 24
        )

        _ = try await coordinator.processAgentComposeAndDeliver(
            context: context,
            stylePrompt: nil
        )

        let fetched = try repository.fetch(id: task.id)
        XCTAssertNotNil(fetched?.contextJson)

        if let contextJson = fetched?.contextJson,
           let data = contextJson.data(using: .utf8) {
            let decoded = try JSONDecoder().decode(ContextSnapshot.self, from: data)
            XCTAssertEqual(decoded.windowTitle, "Chat Window")
            XCTAssertEqual(decoded.targetAppName, "Chat")
            XCTAssertEqual(decoded.visibleText, "Previous message content")
        } else {
            XCTFail("Failed to decode context snapshot")
        }

        // Verify agent prompt was sent to refiner with context
        XCTAssertNotNil(refiner.lastRequest)
        XCTAssertFalse(refiner.lastRequest?.systemPrompt.contains("Chat Window") ?? true)
        XCTAssertTrue(refiner.lastRequest?.text.contains("Chat Window") ?? false)
        XCTAssertTrue(refiner.lastRequest?.text.contains("Previous message content") ?? false)
    }

    // MARK: - Helpers

    private func makeCoordinator(
        pipeline: AgentComposeStubTextPipeline = AgentComposeStubTextPipeline(
            result: TextProcessingResult(rawText: "", finalText: "")
        ),
        outputService: AgentComposeStubOutputService = AgentComposeStubOutputService(result: .copied),
        agentRefiner: (any PromptAwareTextRefining)? = nil,
        contextPipeline: (any ContextCollecting)? = nil,
        agentRuntimeService: (any AgentRuntimeServing)? = nil,
        assetRepository: (any AssetRepository)? = nil,
        agentRuntimeSelection: @escaping @MainActor () -> AgentRuntimeProviderSelection? = { nil }
    ) -> VoiceTaskCoordinator {
        VoiceTaskCoordinator(
            taskRepository: repository,
            outputService: outputService,
            textPipeline: pipeline,
            targetProvider: AgentComposeStubTargetProvider(),
            clock: clock,
            contextPipeline: contextPipeline,
            agentRefiner: agentRefiner,
            agentRuntimeService: agentRuntimeService,
            agentRuntimeSelection: agentRuntimeSelection,
            assetRepository: assetRepository
        )
    }
}

// MARK: - Test Doubles

private final class AgentComposeStubRefiner: PromptAwareTextRefining, RefinementTraceProviding, @unchecked Sendable {
    let result: String?
    let error: Error?
    let trace: LLMRefinementTrace?
    var configured = true
    var lastRequest: TextRefinementRequest?
    var lastTrace: LLMRefinementTrace?

    init(result: String? = nil, error: Error? = nil, trace: LLMRefinementTrace? = nil) {
        self.result = result
        self.error = error
        self.trace = trace
        self.lastTrace = nil
    }

    var isEnabled: Bool { true }
    var isConfigured: Bool { configured }

    func refine(_ text: String) async throws -> String {
        if let error { throw error }
        lastTrace = trace
        return result ?? text
    }

    func refine(_ request: TextRefinementRequest) async throws -> String {
        lastRequest = request
        if let error { throw error }
        lastTrace = trace
        return result ?? request.text
    }

    func clearLastTrace() {
        lastTrace = nil
    }
}

@MainActor
private final class AgentComposeNilStyleSelector: StyleSelecting {
    var lastRouteTrace: StyleRouteTrace? { nil }
    func style(for target: DictationTarget?) async throws -> StyleProfileRecord? {
        nil
    }
}

@MainActor
private final class AgentComposeFixedStyleSelector: StyleSelecting {
    let prompt: String
    var lastRouteTrace: StyleRouteTrace? { nil }

    init(prompt: String) {
        self.prompt = prompt
    }

    func style(for target: DictationTarget?) async throws -> StyleProfileRecord? {
        StyleProfileRecord(
            id: "test-style",
            name: "Test Style",
            category: "test",
            subtitle: nil,
            mode: "test",
            prompt: prompt,
            sampleInput: nil,
            sampleOutput: nil,
            llmProviderID: nil,
            model: nil,
            temperature: 0.2,
            enabled: true,
            builtIn: false,
            isDefault: false,
            createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
    }
}

private enum AgentComposeStubError: Error {
    case networkTimeout
}

private final class AgentComposeImmediateContextCollector: ContextCollecting, @unchecked Sendable {
    let snapshot: ContextSnapshot

    init(snapshot: ContextSnapshot) {
        self.snapshot = snapshot
    }

    func collect(target: DictationTarget?, visionSupported: Bool) async -> ContextSnapshot {
        snapshot
    }
}

private final class AgentComposeCancellingRefiner: PromptAwareTextRefining, @unchecked Sendable {
    let result: String
    var onRefine: (() async -> Void)?

    init(result: String) {
        self.result = result
    }

    var isEnabled: Bool { true }
    var isConfigured: Bool { true }

    func refine(_ text: String) async throws -> String {
        await onRefine?()
        return result
    }

    func refine(_ request: TextRefinementRequest) async throws -> String {
        await onRefine?()
        return result
    }
}

@MainActor
private final class AgentComposeStubTextPipeline: TextProcessing {
    let result: TextProcessingResult

    init(result: TextProcessingResult) {
        self.result = result
    }

    func process(_ rawText: String) async -> TextProcessingResult {
        result
    }
}

@MainActor
private final class AgentComposeStubOutputService: OutputService {
    let result: OutputResult
    private(set) var lastText: String?
    private(set) var lastMode: VoiceTaskMode?
    private(set) var didInject = false

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
        if case .injected = result {
            didInject = true
        }
        return result
    }
}

@MainActor
private final class AgentComposeStubTargetProvider: DictationTargetProviding {
    func currentTarget() -> DictationTarget? { nil }
}

private final class AgentComposeRuntimeServiceStub: AgentRuntimeServing, @unchecked Sendable {
    let storedAvailability: AgentRuntimeAvailability
    let result: AgentRuntimeServiceResult?
    let error: Error?
    private(set) var lastInstruction: String?

    init(
        availability: AgentRuntimeAvailability,
        result: AgentRuntimeServiceResult?,
        error: Error? = nil
    ) {
        self.storedAvailability = availability
        self.result = result
        self.error = error
    }

    func availability(forceRefresh: Bool) async -> AgentRuntimeAvailability {
        storedAvailability
    }

    func runIfAvailable(
        taskID: String,
        instruction: String,
        context: ContextSnapshot?,
        target: DictationTarget?,
        model: String?,
        onEvent: @escaping @Sendable (AgentActionEvent) -> Void
    ) async throws -> AgentRuntimeServiceResult {
        lastInstruction = instruction
        onEvent(AgentActionEvent(
            kind: .turnStarted,
            title: "开始处理",
            timestamp: Date(timeIntervalSince1970: 1_800_000_001)
        ))
        if let error {
            throw error
        }
        return result ?? .unavailable(storedAvailability)
    }
}

private final class AgentComposeCapturingAssetRepository: AssetRepository {
    private(set) var savedItems: [AssetItem] = []

    func save(_ item: AssetItem) throws {
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

private extension AgentRuntimeAvailability {
    static func available(providerID: String = "codex") -> AgentRuntimeAvailability {
        AgentRuntimeAvailability(
            providerID: providerID,
            status: .available,
            detectedAt: Date(timeIntervalSince1970: 1_800_000_000),
            expiresAt: Date(timeIntervalSince1970: 1_800_000_060),
            cliPath: "/tmp/\(providerID)",
            cliVersion: "\(providerID) cli test"
        )
    }

    static func unavailable(reason: String, providerID: String = "codex") -> AgentRuntimeAvailability {
        AgentRuntimeAvailability(
            providerID: providerID,
            status: .unavailable(reason: reason),
            detectedAt: Date(timeIntervalSince1970: 1_800_000_000),
            expiresAt: Date(timeIntervalSince1970: 1_800_000_060),
            cliPath: nil,
            cliVersion: nil
        )
    }
}

private extension AgentRuntimeServiceResult {
    static func successSummary(
        _ summary: String,
        providerID: String = "codex",
        executionMode: AgentExecutionMode? = nil
    ) -> AgentRuntimeServiceResult {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let resolvedExecutionMode = executionMode ??
            (providerID == "codex" ? .codexRuntime : .localAgentRuntime)
        return .completed(AgentRuntimeResult(
            summary: summary,
            status: .completed,
            trace: AgentActionTrace(
                providerID: providerID,
                executionMode: resolvedExecutionMode,
                status: .completed,
                userInstruction: "打开 Google",
                events: [
                    AgentActionEvent(
                        kind: .turnCompleted,
                        title: "任务完成",
                        timestamp: now,
                        elapsedMS: 1200
                    )
                ],
                resultSummary: summary,
                model: providerID == "codex" ? "gpt-5.5" : "deepseek-v4-flash-202605",
                startedAt: now,
                completedAt: now.addingTimeInterval(1.2)
            )
        ))
    }
}

private final class AgentComposeTestClock: AppClock, @unchecked Sendable {
    var now: Date

    init(now: Date) {
        self.now = now
    }

    func sleep(nanoseconds: UInt64) async throws {}
}
