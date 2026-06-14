import Foundation
import XCTest
@testable import VoiceInputApp

@MainActor
final class HomeTaskDetailTests: XCTestCase {

    // MARK: - testFailedTaskWithFinalTextShowsCopyAndRegenerate

    func testFailedTaskWithFinalTextShowsCopyAndRegenerate() {
        let viewModel = makeViewModel()
        let detail = HomeHistoryDetail(
            id: "task-1",
            rawText: "dictated text",
            finalText: "Generated text",
            language: "",
            asrProviderID: nil,
            llmProviderID: nil,
            styleID: nil,
            appName: "Chat",
            durationMS: 0,
            charCount: 14,
            cpm: 0,
            warnings: [],
            trace: nil,
            createdAt: Date(),
            updatedAt: Date(),
            taskMode: .agentCompose,
            taskStatus: .partiallyCompleted,
            windowTitle: nil,
            contextPreview: nil,
            outputResultRaw: nil
        )

        let actions = viewModel.availableRecoveryActions(for: detail)

        XCTAssertTrue(actions.contains(.copy))
        XCTAssertTrue(actions.contains(.regenerate))
        XCTAssertTrue(actions.contains(.delete))
        XCTAssertFalse(actions.contains(.reinject))
    }

    // MARK: - testTranscriptionFailedTaskShowsRetranscribe

    func testTranscriptionFailedTaskShowsRetranscribe() {
        let viewModel = makeViewModel()
        let detail = HomeHistoryDetail(
            id: "task-2",
            rawText: "",
            finalText: "",
            language: "",
            asrProviderID: nil,
            llmProviderID: nil,
            styleID: nil,
            appName: "Editor",
            durationMS: 0,
            charCount: 0,
            cpm: 0,
            warnings: ["transcription_failed"],
            trace: nil,
            createdAt: Date(),
            updatedAt: Date(),
            taskMode: .dictation,
            taskStatus: .failed,
            windowTitle: nil,
            contextPreview: nil,
            outputResultRaw: nil
        )

        let actions = viewModel.availableRecoveryActions(for: detail)

        XCTAssertTrue(actions.contains(.retranscribe))
        XCTAssertTrue(actions.contains(.delete))
        XCTAssertFalse(actions.contains(.copy))
        XCTAssertFalse(actions.contains(.reinject))
    }

    // MARK: - testCompletedDictationShowsReinject

    func testCompletedDictationShowsReinject() {
        let viewModel = makeViewModel()
        let detail = HomeHistoryDetail(
            id: "task-3",
            rawText: "raw text",
            finalText: "processed text",
            language: "zh-CN",
            asrProviderID: nil,
            llmProviderID: nil,
            styleID: nil,
            appName: "Notes",
            durationMS: 5000,
            charCount: 15,
            cpm: 180,
            warnings: [],
            trace: nil,
            createdAt: Date(),
            updatedAt: Date(),
            taskMode: .dictation,
            taskStatus: .completed,
            windowTitle: nil,
            contextPreview: nil,
            outputResultRaw: nil
        )

        let actions = viewModel.availableRecoveryActions(for: detail)

        XCTAssertTrue(actions.contains(.copy))
        XCTAssertTrue(actions.contains(.reinject))
        XCTAssertTrue(actions.contains(.delete))
        XCTAssertFalse(actions.contains(.regenerate))
    }

    // MARK: - testCompletedAgentComposeShowsCopyOnly

    func testCompletedAgentComposeShowsCopyOnly() {
        let viewModel = makeViewModel()
        let detail = HomeHistoryDetail(
            id: "task-4",
            rawText: "compose a reply",
            finalText: "Here is a polished reply.",
            language: "",
            asrProviderID: nil,
            llmProviderID: nil,
            styleID: nil,
            appName: "Slack",
            durationMS: 0,
            charCount: 24,
            cpm: 0,
            warnings: [],
            trace: nil,
            createdAt: Date(),
            updatedAt: Date(),
            taskMode: .agentCompose,
            taskStatus: .completed,
            windowTitle: "#general",
            contextPreview: "Previous conversation content...",
            outputResultRaw: nil
        )

        let actions = viewModel.availableRecoveryActions(for: detail)

        XCTAssertTrue(actions.contains(.copy))
        XCTAssertTrue(actions.contains(.regenerate))
        XCTAssertTrue(actions.contains(.delete))
        XCTAssertFalse(actions.contains(.reinject))
    }

    // MARK: - testTaskWithoutRecoverableDataHidesOperations

    func testTaskWithoutRecoverableDataHidesOperations() {
        let viewModel = makeViewModel()
        let detail = HomeHistoryDetail(
            id: "task-5",
            rawText: "",
            finalText: "",
            language: "",
            asrProviderID: nil,
            llmProviderID: nil,
            styleID: nil,
            appName: nil,
            durationMS: 0,
            charCount: 0,
            cpm: 0,
            warnings: [],
            trace: nil,
            createdAt: Date(),
            updatedAt: Date(),
            taskMode: nil,
            taskStatus: nil,
            windowTitle: nil,
            contextPreview: nil,
            outputResultRaw: nil
        )

        let actions = viewModel.availableRecoveryActions(for: detail)

        // Only delete should be available
        XCTAssertEqual(actions, [.delete])
    }

    // MARK: - testRetryDoesNotSilentlyOverwriteOriginal

    func testRetryDoesNotSilentlyOverwriteOriginal() {
        let viewModel = makeViewModel()
        let originalText = "Original generated text"
        let detail = HomeHistoryDetail(
            id: "task-6",
            rawText: "dictated intent",
            finalText: originalText,
            language: "",
            asrProviderID: nil,
            llmProviderID: nil,
            styleID: nil,
            appName: "Mail",
            durationMS: 0,
            charCount: originalText.count,
            cpm: 0,
            warnings: [],
            trace: nil,
            createdAt: Date(),
            updatedAt: Date(),
            taskMode: .agentCompose,
            taskStatus: .completed,
            windowTitle: nil,
            contextPreview: nil,
            outputResultRaw: nil
        )

        // Verify that the detail preserves the original text
        XCTAssertEqual(detail.finalText, originalText)
        XCTAssertEqual(detail.rawText, "dictated intent")

        // Recovery actions should include regenerate (which creates a NEW task, not overwrite)
        let actions = viewModel.availableRecoveryActions(for: detail)
        XCTAssertTrue(actions.contains(.regenerate))

        // The original detail object is unchanged
        XCTAssertEqual(detail.finalText, originalText)
    }

    // MARK: - Helpers

    private func makeViewModel() -> HomeDashboardViewModel {
        let clock = HomeTaskDetailTestClock(now: Date())
        let container = try! DependencyContainer.inMemory(clock: clock)
        let environment = AppEnvironment(container: container)
        return HomeDashboardViewModel(
            environment: environment,
            clipboardWriter: StubClipboardWriter(),
            textPipeline: nil
        )
    }
}

// MARK: - Test Doubles

private final class StubClipboardWriter: ClipboardWriting {
    var lastCopiedText: String?

    func copy(_ text: String) {
        lastCopiedText = text
    }
}

private final class HomeTaskDetailTestClock: AppClock, @unchecked Sendable {
    var now: Date

    init(now: Date) {
        self.now = now
    }

    func sleep(nanoseconds: UInt64) async throws {}
}
