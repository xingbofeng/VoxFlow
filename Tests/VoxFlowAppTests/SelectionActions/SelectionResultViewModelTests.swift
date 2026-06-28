import CoreGraphics
import VoxFlowTextInsertion
import XCTest
@testable import VoxFlowApp

@MainActor
final class SelectionResultViewModelTests: XCTestCase {
    func testStartTransformStreamsResultAndSelectsResultTab() async {
        let refiner = SelectionResultStreamingRefiner(snapshots: ["人工智能", "人工智能正在改变工作方式。"])
        let viewModel = SelectionResultViewModel(
            selectedText: "Artificial intelligence is changing work.",
            operation: .translation,
            transformService: TextTransformService(refiner: refiner),
            clipboard: CapturingSelectionResultClipboard(),
            speech: CapturingSelectionResultSpeech(),
            textInserter: CapturingSelectionResultTextInserter()
        )

        await viewModel.startTransform()

        XCTAssertEqual(viewModel.selectedTab, .result)
        XCTAssertEqual(viewModel.resultText, "人工智能正在改变工作方式。")
        XCTAssertEqual(viewModel.displayedText, "人工智能正在改变工作方式。")
        XCTAssertEqual(viewModel.statusMessage, L10n.localize("selection.operation.translation_completed", comment: ""))
        XCTAssertFalse(viewModel.isTransforming)
        XCTAssertEqual(refiner.streamingRequestCount, 1)
    }

    func testSummaryUsesSummaryCompletionMessage() async {
        let refiner = SelectionResultStreamingRefiner(snapshots: ["- 要点"])
        let viewModel = SelectionResultViewModel(
            selectedText: "Long text",
            operation: .summary,
            transformService: TextTransformService(refiner: refiner),
            clipboard: CapturingSelectionResultClipboard(),
            speech: CapturingSelectionResultSpeech(),
            textInserter: CapturingSelectionResultTextInserter()
        )

        await viewModel.startTransform()

        XCTAssertEqual(viewModel.resultText, "- 要点")
        XCTAssertEqual(viewModel.statusMessage, L10n.localize("selection.operation.summary_completed", comment: ""))
    }

    func testCompletedTranslationRecordsSelectionHistory() async {
        let historyRecorder = CapturingSelectionHistoryRecorder()
        let viewModel = SelectionResultViewModel(
            selectedText: "Artificial intelligence is changing work.",
            operation: .translation,
            transformService: TextTransformService(refiner: SelectionResultStreamingRefiner(snapshots: ["人工智能正在改变工作。"])),
            clipboard: CapturingSelectionResultClipboard(),
            speech: CapturingSelectionResultSpeech(),
            textInserter: CapturingSelectionResultTextInserter(),
            historyRecorder: historyRecorder
        )

        await viewModel.startTransform()

        XCTAssertEqual(
            historyRecorder.records,
            [
                SelectionHistoryRecordDraft(
                    kind: .selectionTranslation,
                    selectedText: "Artificial intelligence is changing work.",
                    resultText: "人工智能正在改变工作。",
                    status: .completed,
                    failureMessage: nil
                )
            ]
        )
    }

    func testCancelledTransformRecordsPartialSelectionHistory() async {
        let historyRecorder = CapturingSelectionHistoryRecorder()
        let refiner = CancellableSelectionResultStreamingRefiner(firstSnapshot: "部分译文")
        let viewModel = SelectionResultViewModel(
            selectedText: "Long selected text",
            operation: .translation,
            transformService: TextTransformService(refiner: refiner),
            clipboard: CapturingSelectionResultClipboard(),
            speech: CapturingSelectionResultSpeech(),
            textInserter: CapturingSelectionResultTextInserter(),
            historyRecorder: historyRecorder
        )

        viewModel.startTransformTask()
        await refiner.waitUntilStreamStarted()
        await waitUntil { viewModel.resultText == "部分译文" }

        viewModel.cancelTransform()
        await refiner.waitUntilTerminated()

        XCTAssertEqual(
            historyRecorder.records,
            [
                SelectionHistoryRecordDraft(
                    kind: .selectionTranslation,
                    selectedText: "Long selected text",
                    resultText: "部分译文",
                    status: .partiallyCompleted,
                    failureMessage: nil
                )
            ]
        )
    }

    func testCopySelectedTextCopiesCurrentTabText() {
        let clipboard = CapturingSelectionResultClipboard()
        let viewModel = SelectionResultViewModel(
            selectedText: "source",
            operation: .translation,
            transformService: TextTransformService(refiner: SelectionResultStreamingRefiner(snapshots: [])),
            clipboard: clipboard,
            speech: CapturingSelectionResultSpeech(),
            textInserter: CapturingSelectionResultTextInserter()
        )
        viewModel.resultText = "result"
        viewModel.selectedTab = .result

        viewModel.copySelectedText()

        XCTAssertEqual(clipboard.copiedTexts, ["result"])
        XCTAssertEqual(viewModel.statusMessage, L10n.localize("selection.status.copied", comment: ""))
    }

    func testSpeakSelectedTextUsesCurrentTabText() {
        let speech = CapturingSelectionResultSpeech()
        let viewModel = SelectionResultViewModel(
            selectedText: "source",
            operation: .summary,
            transformService: TextTransformService(refiner: SelectionResultStreamingRefiner(snapshots: [])),
            clipboard: CapturingSelectionResultClipboard(),
            speech: speech,
            textInserter: CapturingSelectionResultTextInserter()
        )
        viewModel.resultText = "summary"
        viewModel.selectedTab = .result

        viewModel.speakSelectedText()

        XCTAssertEqual(speech.spokenTexts, ["summary"])
        XCTAssertEqual(viewModel.playbackState?.text, "summary")
        XCTAssertEqual(viewModel.statusMessage, L10n.localize("selection.status.reading", comment: ""))
    }

    func testReplaceOriginalInsertsCurrentTabText() async {
        let textInserter = CapturingSelectionResultTextInserter()
        let viewModel = SelectionResultViewModel(
            selectedText: "source",
            operation: .translation,
            transformService: TextTransformService(refiner: SelectionResultStreamingRefiner(snapshots: [])),
            clipboard: CapturingSelectionResultClipboard(),
            speech: CapturingSelectionResultSpeech(),
            textInserter: textInserter
        )
        viewModel.resultText = "译文"
        viewModel.selectedTab = .result

        await viewModel.replaceOriginal()

        XCTAssertEqual(textInserter.insertedTexts, ["译文"])
        XCTAssertEqual(viewModel.statusMessage, L10n.localize("selection.status.replaced_original", comment: ""))
    }

    func testInsertAfterSelectionPrefixesNewlineBeforeCurrentTabText() async {
        let textInserter = CapturingSelectionResultTextInserter()
        let viewModel = SelectionResultViewModel(
            selectedText: "source",
            operation: .summary,
            transformService: TextTransformService(refiner: SelectionResultStreamingRefiner(snapshots: [])),
            clipboard: CapturingSelectionResultClipboard(),
            speech: CapturingSelectionResultSpeech(),
            textInserter: textInserter
        )
        viewModel.resultText = "- 要点"
        viewModel.selectedTab = .result

        await viewModel.insertAfterSelection()

        XCTAssertEqual(textInserter.insertedTexts, ["\n- 要点"])
        XCTAssertEqual(viewModel.statusMessage, L10n.localize("selection.status.inserted_newline", comment: ""))
    }

    func testInsertFailureFallsBackToCopyingCurrentTabText() async {
        let clipboard = CapturingSelectionResultClipboard()
        let textInserter = CapturingSelectionResultTextInserter(result: .permissionDenied)
        let viewModel = SelectionResultViewModel(
            selectedText: "source",
            operation: .translation,
            transformService: TextTransformService(refiner: SelectionResultStreamingRefiner(snapshots: [])),
            clipboard: clipboard,
            speech: CapturingSelectionResultSpeech(),
            textInserter: textInserter
        )
        viewModel.resultText = "译文"
        viewModel.selectedTab = .result

        await viewModel.replaceOriginal()

        XCTAssertEqual(textInserter.insertedTexts, ["译文"])
        XCTAssertEqual(clipboard.copiedTexts, ["译文"])
        XCTAssertEqual(viewModel.statusMessage, L10n.localize("selection.status.write_fallback_copied", comment: ""))
    }

    func testCancelTransformKeepsPartialResultAndStopsStreaming() async {
        let refiner = CancellableSelectionResultStreamingRefiner(firstSnapshot: "部分译文")
        let viewModel = SelectionResultViewModel(
            selectedText: "Long selected text",
            operation: .translation,
            transformService: TextTransformService(refiner: refiner),
            clipboard: CapturingSelectionResultClipboard(),
            speech: CapturingSelectionResultSpeech(),
            textInserter: CapturingSelectionResultTextInserter()
        )

        viewModel.startTransformTask()
        await refiner.waitUntilStreamStarted()
        await waitUntil { viewModel.resultText == "部分译文" }

        XCTAssertEqual(viewModel.resultText, "部分译文")
        XCTAssertTrue(viewModel.isTransforming)

        viewModel.cancelTransform()
        await refiner.waitUntilTerminated()

        XCTAssertEqual(viewModel.resultText, "部分译文")
        XCTAssertFalse(viewModel.isTransforming)
        XCTAssertEqual(viewModel.statusMessage, L10n.localize("selection.operation.translation_cancelled", comment: ""))
    }

    func testSwitchingAwayFromResultTabCancelsActiveTransform() async {
        let refiner = CancellableSelectionResultStreamingRefiner(firstSnapshot: "部分译文")
        let viewModel = SelectionResultViewModel(
            selectedText: "Long selected text",
            operation: .translation,
            transformService: TextTransformService(refiner: refiner),
            clipboard: CapturingSelectionResultClipboard(),
            speech: CapturingSelectionResultSpeech(),
            textInserter: CapturingSelectionResultTextInserter()
        )

        viewModel.startTransformTask()
        await refiner.waitUntilStreamStarted()
        await waitUntil { viewModel.resultText == "部分译文" }

        viewModel.selectedTab = .source
        await waitUntil { refiner.didTerminateStream }

        XCTAssertEqual(viewModel.resultText, "部分译文")
        XCTAssertFalse(viewModel.isTransforming)
        XCTAssertEqual(viewModel.statusMessage, L10n.localize("selection.operation.translation_cancelled", comment: ""))
    }

    private func waitUntil(
        timeoutNanoseconds: UInt64 = 1_000_000_000,
        condition: @escaping @MainActor () -> Bool
    ) async {
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
        while !condition(), DispatchTime.now().uptimeNanoseconds < deadline {
            await Task.yield()
        }
    }
}

private final class SelectionResultStreamingRefiner: StreamingPromptAwareTextRefining, @unchecked Sendable {
    var isEnabled = true
    var isConfigured = true
    private let snapshots: [String]
    private(set) var streamingRequestCount = 0

    init(snapshots: [String]) {
        self.snapshots = snapshots
    }

    func refine(_ text: String) async throws -> String {
        snapshots.last ?? text
    }

    func refine(_ request: TextRefinementRequest) async throws -> String {
        snapshots.last ?? request.text
    }

    func refineStream(_ request: TextRefinementRequest) -> AsyncThrowingStream<String, Error> {
        streamingRequestCount += 1
        let snapshots = snapshots
        return AsyncThrowingStream { continuation in
            for snapshot in snapshots {
                continuation.yield(snapshot)
            }
            continuation.finish()
        }
    }
}

private final class CapturingSelectionResultClipboard: ClipboardSetting {
    private(set) var copiedTexts: [String] = []

    func setString(_ text: String) -> Bool {
        copiedTexts.append(text)
        return true
    }

    func setImage(_ image: CGImage) -> Bool {
        false
    }
}

private final class CapturingSelectionResultSpeech: ScreenshotSpeechSpeaking {
    private(set) var spokenTexts: [String] = []
    private(set) var stopCount = 0

    func speak(_ text: String, completion: ScreenshotSpeechCompletion?) {
        spokenTexts.append(text)
    }

    func stop() {
        stopCount += 1
    }
}

private final class CapturingSelectionResultTextInserter: TextInserting {
    private let result: TextInsertionResult
    private(set) var insertedTexts: [String] = []

    init(result: TextInsertionResult = .success) {
        self.result = result
    }

    func insert(_ text: String) async -> TextInsertionResult {
        insertedTexts.append(text)
        return result
    }
}

private final class CapturingSelectionHistoryRecorder: SelectionHistoryRecording {
    private(set) var records: [SelectionHistoryRecordDraft] = []

    func record(_ draft: SelectionHistoryRecordDraft) {
        records.append(draft)
    }
}

private final class CancellableSelectionResultStreamingRefiner: StreamingPromptAwareTextRefining, @unchecked Sendable {
    var isEnabled = true
    var isConfigured = true
    private let firstSnapshot: String
    private var streamStartedContinuation: CheckedContinuation<Void, Never>?
    private var streamTerminatedContinuation: CheckedContinuation<Void, Never>?
    private let lock = NSLock()
    private var didStart = false
    private var didTerminate = false

    init(firstSnapshot: String) {
        self.firstSnapshot = firstSnapshot
    }

    func refine(_ text: String) async throws -> String {
        firstSnapshot
    }

    func refine(_ request: TextRefinementRequest) async throws -> String {
        firstSnapshot
    }

    func refineStream(_ request: TextRefinementRequest) -> AsyncThrowingStream<String, Error> {
        let firstSnapshot = firstSnapshot
        return AsyncThrowingStream { continuation in
            continuation.yield(firstSnapshot)
            signalStarted()
            continuation.onTermination = { [weak self] _ in
                self?.signalTerminated()
            }
        }
    }

    func waitUntilStreamStarted() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if didStart {
                lock.unlock()
                continuation.resume()
            } else {
                streamStartedContinuation = continuation
                lock.unlock()
            }
        }
    }

    func waitUntilTerminated() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if didTerminate {
                lock.unlock()
                continuation.resume()
            } else {
                streamTerminatedContinuation = continuation
                lock.unlock()
            }
        }
    }

    var didTerminateStream: Bool {
        lock.lock()
        defer { lock.unlock() }
        return didTerminate
    }

    private func signalStarted() {
        lock.lock()
        didStart = true
        let continuation = streamStartedContinuation
        streamStartedContinuation = nil
        lock.unlock()
        continuation?.resume()
    }

    private func signalTerminated() {
        lock.lock()
        didTerminate = true
        let continuation = streamTerminatedContinuation
        streamTerminatedContinuation = nil
        lock.unlock()
        continuation?.resume()
    }
}
