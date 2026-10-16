import Foundation
import XCTest
@testable import VoxFlowApp

@MainActor
final class CommandTests: XCTestCase {
    nonisolated(unsafe) private var databaseQueue: DatabaseQueue!
    nonisolated(unsafe) private var repository: VoiceTaskRepository!
    private let clock = CommandTestClock(now: Date(timeIntervalSince1970: 1_800_000_000))

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

    private static let target = DictationTarget(
        bundleID: "com.example.editor",
        appName: "Editor",
        pid: 4242
    )

    // MARK: - Coordinator: instruction + existing text -> rewritten input area

    func testCommandEditSendsSpokenInstructionWithExistingTextToModel() async throws {
        let refiner = CommandStubRefiner(result: "改写后的内容")
        let coordinator = makeCoordinator(agentRefiner: refiner)
        _ = try coordinator.startTask(mode: .command, target: Self.target)
        try coordinator.recordRawTranscript("把这句话改成过去时")

        _ = try await coordinator.processCommandAndDeliver(
            instruction: "把这句话改成过去时",
            editingText: "他今天去了公司"
        )

        let request = try XCTUnwrap(refiner.lastRequest)
        XCTAssertEqual(request.purpose, .commandEdit)
        XCTAssertEqual(request.text, "他今天去了公司")
        XCTAssertTrue(request.systemPrompt.contains("把这句话改成过去时"))
    }

    func testCommandDeliversRewrittenTextWithTheSnapshotItRead() async throws {
        let refiner = CommandStubRefiner(result: "他昨天去了公司")
        let outputService = CommandStubOutputService(result: .injected)
        let coordinator = makeCoordinator(outputService: outputService, agentRefiner: refiner)
        _ = try coordinator.startTask(mode: .command, target: Self.target)
        try coordinator.recordRawTranscript("改成过去时")

        let result = try await coordinator.processCommandAndDeliver(
            instruction: "改成过去时",
            editingText: "他今天去了公司"
        )

        XCTAssertEqual(result, .injected)
        let delivery = try XCTUnwrap(outputService.replacementDeliveries.last)
        XCTAssertEqual(delivery.text, "他昨天去了公司")
        XCTAssertEqual(delivery.mode, .command)
        XCTAssertEqual(delivery.expectedInputText, "他今天去了公司")
        XCTAssertEqual(delivery.originalTarget, Self.target)
        XCTAssertEqual(delivery.target, Self.target)
        XCTAssertTrue(outputService.deliveries.isEmpty)
    }

    func testCommandKeepsExistingTextWhenModelReturnsNothingUsable() async throws {
        let refiner = CommandStubRefiner(result: "   ")
        let outputService = CommandStubOutputService(result: .injected)
        let coordinator = makeCoordinator(outputService: outputService, agentRefiner: refiner)
        _ = try coordinator.startTask(mode: .command, target: Self.target)
        try coordinator.recordRawTranscript("整理一下")

        _ = try await coordinator.processCommandAndDeliver(
            instruction: "整理一下",
            editingText: "他今天去了公司"
        )

        XCTAssertEqual(outputService.replacementDeliveries.last?.text, "他今天去了公司")
    }

    func testCommandCompletesTaskWithEditedTextAndRawInstruction() async throws {
        let refiner = CommandStubRefiner(result: "他昨天去了公司")
        let coordinator = makeCoordinator(agentRefiner: refiner)
        let task = try coordinator.startTask(mode: .command, target: Self.target)
        try coordinator.recordRawTranscript("改成过去时")

        _ = try await coordinator.processCommandAndDeliver(
            instruction: "改成过去时",
            editingText: "他今天去了公司"
        )

        let fetched = try XCTUnwrap(repository.fetch(id: task.id))
        XCTAssertEqual(fetched.status, .completed)
        XCTAssertEqual(fetched.finalText, "他昨天去了公司")
        XCTAssertEqual(fetched.rawTranscript, "改成过去时")
    }

    func testCommandModelFailureRecordsWarningAndThrows() async throws {
        let refiner = CommandStubRefiner(error: CommandStubError.timeout)
        let coordinator = makeCoordinator(agentRefiner: refiner)
        let task = try coordinator.startTask(mode: .command, target: Self.target)
        try coordinator.recordRawTranscript("改成过去时")

        do {
            _ = try await coordinator.processCommandAndDeliver(
                instruction: "改成过去时",
                editingText: "他今天去了公司"
            )
            XCTFail("Expected llmCallFailed")
        } catch let error as CoordinatorError {
            guard case .llmCallFailed = error else {
                return XCTFail("Expected llmCallFailed, got \(error)")
            }
        }

        let fetched = try XCTUnwrap(repository.fetch(id: task.id))
        XCTAssertEqual(fetched.warnings, ["command_llm_failed"])
    }

    func testCommandWithoutConfiguredModelFailsBeforeCalling() async throws {
        let refiner = CommandStubRefiner(result: "改写后的内容")
        refiner.configured = false
        let coordinator = makeCoordinator(agentRefiner: refiner)
        _ = try coordinator.startTask(mode: .command, target: Self.target)

        do {
            _ = try await coordinator.processCommandAndDeliver(
                instruction: "改成过去时",
                editingText: "他今天去了公司"
            )
            XCTFail("Expected llmNotConfigured")
        } catch let error as CoordinatorError {
            guard case .llmNotConfigured = error else {
                return XCTFail("Expected llmNotConfigured, got \(error)")
            }
        }

        XCTAssertNil(refiner.lastRequest)
    }

    // MARK: - Handler: snapshot on start, write back on finish

    func testCommandHandlerReportsEditableTextOnlyForFocusableTextFieldWithContent() {
        let handler = makeHandler(inputAreaText: "有内容")
        XCTAssertTrue(handler.hasEditableText())

        XCTAssertFalse(makeHandler(inputAreaText: "   ").hasEditableText())
        XCTAssertFalse(makeHandler(inputAreaText: nil).hasEditableText())
        XCTAssertFalse(makeHandler(inputAreaText: "有内容", isSecure: true).hasEditableText())
        XCTAssertFalse(makeHandler(inputAreaText: "有内容", target: nil).hasEditableText())
    }

    func testCommandHandlerIsConfiguredFollowsRefiner() {
        XCTAssertTrue(makeHandler(agentRefiner: CommandStubRefiner(result: "x")).isConfigured)

        let unconfigured = CommandStubRefiner(result: "x")
        unconfigured.configured = false
        XCTAssertFalse(makeHandler(agentRefiner: unconfigured).isConfigured)
        XCTAssertFalse(makeHandler(agentRefiner: nil).isConfigured)
    }

    func testCommandHandlerStartSnapshotsFieldTextAndStartsCommandTask() throws {
        let coordinator = makeCoordinator(agentRefiner: CommandStubRefiner(result: "x"))
        let handler = makeHandler(coordinator: coordinator, inputAreaText: "原文内容")

        try handler.start(target: Self.target, asrMetadata: nil)

        let taskID = try XCTUnwrap(coordinator.activeTaskID(for: .command))
        XCTAssertEqual(coordinator.currentTaskID, taskID)
    }

    func testCommandHandlerStartRejectsEmptyField() {
        let handler = makeHandler(inputAreaText: "   ")

        XCTAssertThrowsError(try handler.start(target: Self.target, asrMetadata: nil)) { error in
            XCTAssertEqual(error as? CommandEditError, .noEditableText)
        }
    }

    func testCommandHandlerStartRejectsSecondCommandWhileRunning() throws {
        let coordinator = makeCoordinator(agentRefiner: CommandStubRefiner(result: "x"))
        let handler = makeHandler(coordinator: coordinator, inputAreaText: "原文内容")
        try handler.start(target: Self.target, asrMetadata: nil)

        XCTAssertThrowsError(try handler.start(target: Self.target, asrMetadata: nil)) { error in
            guard case .workflowAlreadyRunning(let kind)? = error as? CoordinatorError else {
                return XCTFail("Expected workflowAlreadyRunning, got \(error)")
            }
            XCTAssertEqual(kind, VoiceWorkflowKind.command.rawValue)
        }
    }

    func testCommandHandlerFinishWithoutStartThrows() async {
        let handler = makeHandler()

        do {
            _ = try await handler.finish(rawTranscript: "改成过去时")
            XCTFail("Expected noActiveTask")
        } catch let error as CoordinatorError {
            guard case .noActiveTask = error else {
                return XCTFail("Expected noActiveTask, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testCommandHandlerFinishTwiceIsRejected() async throws {
        let coordinator = makeCoordinator(agentRefiner: CommandStubRefiner(result: "他昨天去了公司"))
        let handler = makeHandler(coordinator: coordinator, inputAreaText: "他今天去了公司")
        try handler.start(target: Self.target, asrMetadata: nil)

        _ = try await handler.finish(rawTranscript: "改成过去时")

        do {
            _ = try await handler.finish(rawTranscript: "再改一次")
            XCTFail("Expected noActiveTask")
        } catch let error as CoordinatorError {
            guard case .noActiveTask = error else {
                return XCTFail("Expected noActiveTask, got \(error)")
            }
        }
    }

    func testCommandHandlerCancelReleasesTaskSoANewCommandCanStart() async throws {
        let coordinator = makeCoordinator(agentRefiner: CommandStubRefiner(result: "x"))
        let handler = makeHandler(coordinator: coordinator, inputAreaText: "原文内容")
        try handler.start(target: Self.target, asrMetadata: nil)

        handler.cancel()

        XCTAssertNil(coordinator.activeTaskID(for: .command))
        XCTAssertNil(coordinator.currentTaskID)
        XCTAssertNoThrow(try handler.start(target: Self.target, asrMetadata: nil))
    }

    func testCommandHandlerFailRecordsFailureForTheActiveTask() async throws {
        let coordinator = makeCoordinator(agentRefiner: CommandStubRefiner(result: "x"))
        let handler = makeHandler(coordinator: coordinator, inputAreaText: "原文内容")
        try handler.start(target: Self.target, asrMetadata: nil)
        let taskID = try XCTUnwrap(coordinator.activeTaskID(for: .command))

        handler.fail(CommandStubError.timeout)

        let fetched = try XCTUnwrap(repository.fetch(id: taskID))
        XCTAssertEqual(fetched.status, .failed)
    }

    func testCommandHandlerIgnoresAlreadyRunningErrorWhenFailing() async throws {
        let coordinator = makeCoordinator(agentRefiner: CommandStubRefiner(result: "x"))
        let handler = makeHandler(coordinator: coordinator, inputAreaText: "原文内容")
        try handler.start(target: Self.target, asrMetadata: nil)
        let taskID = try XCTUnwrap(coordinator.activeTaskID(for: .command))

        handler.fail(CoordinatorError.workflowAlreadyRunning(VoiceWorkflowKind.command.rawValue))

        let fetched = try XCTUnwrap(repository.fetch(id: taskID))
        XCTAssertEqual(fetched.status, .inProgress)
    }

    // MARK: - Helpers

    private func makeCoordinator(
        outputService: CommandStubOutputService = CommandStubOutputService(result: .injected),
        agentRefiner: (any PromptAwareTextRefining)? = nil
    ) -> VoiceTaskCoordinator {
        VoiceTaskCoordinator(
            taskRepository: repository,
            outputService: outputService,
            textPipeline: CommandStubTextPipeline(),
            targetProvider: CommandStubTargetProvider(target: Self.target),
            clock: clock,
            agentRefiner: agentRefiner
        )
    }

    private func makeHandler(
        coordinator: VoiceTaskCoordinator? = nil,
        agentRefiner: (any PromptAwareTextRefining)? = CommandStubRefiner(result: "改写后的内容"),
        inputAreaText: String? = "原文内容",
        isSecure: Bool = false,
        target: DictationTarget? = CommandTests.target
    ) -> DefaultCommandHandler {
        DefaultCommandHandler(
            coordinator: coordinator ?? makeCoordinator(agentRefiner: agentRefiner),
            refiner: agentRefiner,
            inputAreaTextProvider: { _ in inputAreaText },
            isSecureTextField: { _ in isSecure },
            currentTarget: { target }
        )
    }
}

// MARK: - Test Doubles

private enum CommandStubError: Error {
    case timeout
}

private final class CommandStubRefiner: PromptAwareTextRefining, RefinementTraceProviding, @unchecked Sendable {
    let result: String?
    let error: Error?
    var configured = true
    var lastRequest: TextRefinementRequest?
    var lastTrace: LLMRefinementTrace?

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

    func clearLastTrace() {
        lastTrace = nil
    }
}

@MainActor
private final class CommandStubOutputService: OutputService {
    struct Delivery: Equatable {
        let text: String
        let mode: VoiceTaskMode
        let target: DictationTarget?
        let originalTarget: DictationTarget?
        let expectedInputText: String
    }

    let result: OutputResult
    private(set) var deliveries: [Delivery] = []
    private(set) var replacementDeliveries: [Delivery] = []

    init(result: OutputResult) {
        self.result = result
    }

    func deliver(
        text: String,
        mode: VoiceTaskMode,
        target: DictationTarget?,
        originalTarget: DictationTarget?
    ) async -> OutputResult {
        deliveries.append(
            Delivery(
                text: text,
                mode: mode,
                target: target,
                originalTarget: originalTarget,
                expectedInputText: ""
            )
        )
        return result
    }

    func deliverReplacingInputArea(
        text: String,
        mode: VoiceTaskMode,
        target: DictationTarget?,
        originalTarget: DictationTarget?,
        expectedInputText: String
    ) async -> OutputResult {
        replacementDeliveries.append(
            Delivery(
                text: text,
                mode: mode,
                target: target,
                originalTarget: originalTarget,
                expectedInputText: expectedInputText
            )
        )
        return result
    }
}

@MainActor
private final class CommandStubTextPipeline: TextProcessing {
    func process(_ rawText: String) async -> TextProcessingResult {
        TextProcessingResult(rawText: rawText, finalText: rawText)
    }
}

@MainActor
private final class CommandStubTargetProvider: DictationTargetProviding {
    let target: DictationTarget?

    init(target: DictationTarget?) {
        self.target = target
    }

    func currentTarget() -> DictationTarget? {
        target
    }
}

private final class CommandTestClock: AppClock, @unchecked Sendable {
    var now: Date

    init(now: Date) {
        self.now = now
    }

    func sleep(nanoseconds: UInt64) async throws {}
}
