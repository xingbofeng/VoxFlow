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
        try coordinator.startTask(mode: .agentCompose, target: nil)
        try coordinator.recordRawTranscript("compose something")

        let result = try await coordinator.processAgentComposeAndDeliver(
            context: nil,
            stylePrompt: nil
        )

        XCTAssertEqual(outputService.lastMode, .agentCompose)
        XCTAssertEqual(result, .copied)
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
        contextPipeline: (any ContextCollecting)? = nil
    ) -> VoiceTaskCoordinator {
        VoiceTaskCoordinator(
            taskRepository: repository,
            outputService: outputService,
            textPipeline: pipeline,
            targetProvider: AgentComposeStubTargetProvider(),
            clock: clock,
            contextPipeline: contextPipeline,
            agentRefiner: agentRefiner
        )
    }
}

// MARK: - Test Doubles

private final class AgentComposeStubRefiner: PromptAwareTextRefining, @unchecked Sendable {
    let result: String?
    let error: Error?
    var configured = true
    var lastRequest: TextRefinementRequest?

    init(result: String? = nil, error: Error? = nil) {
        self.result = result
        self.error = error
    }

    var isEnabled: Bool { true }
    var isConfigured: Bool { configured }

    func refine(_ text: String) async throws -> String {
        if let error { throw error }
        return result ?? text
    }

    func refine(_ request: TextRefinementRequest) async throws -> String {
        lastRequest = request
        if let error { throw error }
        return result ?? request.text
    }
}

@MainActor
private final class AgentComposeNilStyleSelector: StyleSelecting {
    var lastRouteTrace: StyleRouteTrace? { nil }
    func style(for target: DictationTarget?) async throws -> StyleProfileRecord? {
        nil
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

private final class AgentComposeTestClock: AppClock, @unchecked Sendable {
    var now: Date

    init(now: Date) {
        self.now = now
    }

    func sleep(nanoseconds: UInt64) async throws {}
}
