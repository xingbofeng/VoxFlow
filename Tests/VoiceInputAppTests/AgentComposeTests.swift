import Foundation
import XCTest
@testable import VoiceInputApp

@MainActor
final class AgentComposeTests: XCTestCase {
    private var databaseQueue: DatabaseQueue!
    private var repository: VoiceTaskRepository!
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

    // MARK: - testAgentComposeCopiesToClipboard

    func testAgentComposeCopiesToClipboard() async throws {
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

    // MARK: - testAgentComposeNeverInjects

    func testAgentComposeNeverInjects() async throws {
        let refiner = AgentComposeStubRefiner(result: "Generated text")
        // Even though the output service could inject, agent compose should request copy
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

        // Verify mode was agentCompose (output service copies, never injects)
        XCTAssertEqual(outputService.lastMode, .agentCompose)
        XCTAssertEqual(result, .copied)
        XCTAssertNotEqual(result, .injected)
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

        // The output service receives mode=.agentCompose, so it only copies
        // No Enter key simulation, no app-specific send
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
        XCTAssertEqual(refiner.lastRequest?.text, "generate something")
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
                XCTAssertTrue(error.errorDescription?.contains("retry") ?? false)
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
                XCTAssertTrue(error.errorDescription?.contains("Settings") ?? false)
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
        XCTAssertTrue(refiner.lastRequest?.systemPrompt.contains("Chat Window") ?? false)
    }

    // MARK: - Helpers

    private func makeCoordinator(
        pipeline: AgentComposeStubTextPipeline = AgentComposeStubTextPipeline(
            result: TextProcessingResult(rawText: "", finalText: "")
        ),
        outputService: AgentComposeStubOutputService = AgentComposeStubOutputService(result: .copied),
        agentRefiner: AgentComposeStubRefiner? = nil
    ) -> VoiceTaskCoordinator {
        VoiceTaskCoordinator(
            taskRepository: repository,
            outputService: outputService,
            textPipeline: pipeline,
            targetProvider: AgentComposeStubTargetProvider(),
            clock: clock,
            contextPipeline: nil,
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

private enum AgentComposeStubError: Error {
    case networkTimeout
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
