import Foundation
import VoxFlowTextInsertion

enum SelectionResultTab: Equatable, Hashable {
    case source
    case result
}

struct SelectionResultPlaybackState: Equatable {
    let text: String
}

@MainActor
final class SelectionResultViewModel: ObservableObject {
    let selectedText: String
    let operation: TextTransformOperation
    @Published var selectedTab: SelectionResultTab = .result {
        didSet {
            guard selectedTab != oldValue,
                  selectedTab != .result else {
                return
            }
            cancelTransform()
        }
    }
    @Published var resultText = ""
    @Published private(set) var isTransforming = false
    @Published private(set) var statusMessage: String?
    @Published private(set) var playbackState: SelectionResultPlaybackState?

    private let transformService: TextTransformService
    private let clipboard: any ClipboardSetting
    private let speech: any ScreenshotSpeechSpeaking
    private let textInserter: any TextInserting
    private let historyRecorder: any SelectionHistoryRecording
    private var activeTransformTask: Task<Void, Never>?
    private var transformGeneration = 0
    private var didRecordHistory = false

    init(
        selectedText: String,
        operation: TextTransformOperation,
        transformService: TextTransformService,
        clipboard: any ClipboardSetting,
        speech: any ScreenshotSpeechSpeaking,
        textInserter: any TextInserting,
        historyRecorder: any SelectionHistoryRecording = NoopSelectionHistoryRecorder()
    ) {
        self.selectedText = selectedText
        self.operation = operation
        self.transformService = transformService
        self.clipboard = clipboard
        self.speech = speech
        self.textInserter = textInserter
        self.historyRecorder = historyRecorder
    }

    var displayedText: String {
        switch selectedTab {
        case .source:
            return selectedText
        case .result:
            return resultText
        }
    }

    func startTransformTask() {
        activeTransformTask?.cancel()
        transformGeneration += 1
        let generation = transformGeneration
        activeTransformTask = Task { [weak self] in
            await self?.startTransform(generation: generation)
            guard self?.transformGeneration == generation else { return }
            self?.activeTransformTask = nil
        }
    }

    func cancelTransform() {
        transformGeneration += 1
        activeTransformTask?.cancel()
        activeTransformTask = nil
        guard isTransforming else { return }
        isTransforming = false
        statusMessage = operation.cancelledMessage
        recordSelectionHistory(status: .partiallyCompleted, resultText: resultText)
    }

    func startTransform() async {
        transformGeneration += 1
        await startTransform(generation: transformGeneration)
    }

    private func startTransform(generation: Int) async {
        guard !isTransforming else { return }
        let text = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            statusMessage = L10n.localize("selection.status.no_processable_text", comment: "")
            return
        }

        selectedTab = .result
        isTransforming = true
        statusMessage = operation.runningMessage
        defer {
            if transformGeneration == generation {
                isTransforming = false
            }
        }

        let request = TextTransformRequest(text: selectedText, operation: operation)
        for await event in transformService.events(for: request) {
            guard transformGeneration == generation, !Task.isCancelled else { return }
            switch event {
            case .started:
                statusMessage = operation.runningMessage
            case .partialText(let text):
                resultText = text
            case .unitCompleted:
                break
            case .completed(let text):
                resultText = text
                statusMessage = operation.completedMessage
                recordSelectionHistory(status: .completed, resultText: text)
            case .cancelled(let partialText):
                if !partialText.isEmpty {
                    resultText = partialText
                }
                statusMessage = operation.cancelledMessage
                recordSelectionHistory(status: .partiallyCompleted, resultText: resultText)
            case .failed(let message, let partialText):
                if !partialText.isEmpty {
                    resultText = partialText
                }
                statusMessage = "\(operation.failedPrefix)：\(message)"
                recordSelectionHistory(
                    status: .partiallyCompleted,
                    resultText: resultText,
                    failureMessage: message
                )
            }
        }
    }

    func copySelectedText() {
        if clipboard.setString(displayedText) {
            statusMessage = L10n.localize("selection.status.copied", comment: "")
        } else {
            statusMessage = L10n.localize("selection.status.copy_failed", comment: "")
        }
    }

    func replaceOriginal() async {
        await insertDisplayedText(prefix: "", successMessage: L10n.localize("selection.status.replaced_original", comment: ""))
    }

    func insertAfterSelection() async {
        await insertDisplayedText(prefix: "\n", successMessage: L10n.localize("selection.status.inserted_newline", comment: ""))
    }

    func speakSelectedText() {
        let text = displayedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            statusMessage = L10n.localize("selection.status.no_text_to_read", comment: "")
            return
        }
        speech.speak(text) { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.playbackState = nil
                self.statusMessage = L10n.localize("selection.status.read_complete", comment: "")
            }
        }
        playbackState = SelectionResultPlaybackState(text: text)
        statusMessage = L10n.localize("selection.status.reading", comment: "")
    }

    func stopSpeaking() {
        speech.stop()
        playbackState = nil
        statusMessage = L10n.localize("selection.status.stop_reading", comment: "")
    }

    func close() {
        cancelTransform()
        speech.stop()
        playbackState = nil
    }

    private func insertDisplayedText(prefix: String, successMessage: String) async {
        let text = displayedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            statusMessage = L10n.localize("selection.status.no_text_to_write", comment: "")
            return
        }

        let result = await textInserter.insert(prefix + displayedText)
        if result == .success {
            statusMessage = successMessage
            return
        }

        if clipboard.setString(displayedText) {
            statusMessage = L10n.localize("selection.status.write_fallback_copied", comment: "")
        } else {
            statusMessage = L10n.localize("selection.status.write_failed", comment: "")
        }
    }

    private func recordSelectionHistory(
        status: VoiceTaskStatus,
        resultText: String,
        failureMessage: String? = nil
    ) {
        guard !didRecordHistory else { return }
        let trimmedResult = resultText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedResult.isEmpty else { return }

        didRecordHistory = true
        historyRecorder.record(
            SelectionHistoryRecordDraft(
                kind: operation.selectionHistoryKind,
                selectedText: selectedText,
                resultText: trimmedResult,
                status: status,
                failureMessage: failureMessage
            )
        )
    }
}

private extension TextTransformOperation {
    var runningMessage: String {
        switch self {
        case .translation:
            return L10n.localize("selection.operation.translation_running", comment: "")
        case .summary:
            return L10n.localize("selection.operation.summary_running", comment: "")
        }
    }

    var completedMessage: String {
        switch self {
        case .translation:
            return L10n.localize("selection.operation.translation_completed", comment: "")
        case .summary:
            return L10n.localize("selection.operation.summary_completed", comment: "")
        }
    }

    var cancelledMessage: String {
        switch self {
        case .translation:
            return L10n.localize("selection.operation.translation_cancelled", comment: "")
        case .summary:
            return L10n.localize("selection.operation.summary_cancelled", comment: "")
        }
    }

    var failedPrefix: String {
        switch self {
        case .translation:
            return L10n.localize("selection.operation.translation_failed_prefix", comment: "")
        case .summary:
            return L10n.localize("selection.operation.summary_failed_prefix", comment: "")
        }
    }

    var selectionHistoryKind: VoiceAssetKind {
        switch self {
        case .translation:
            return .selectionTranslation
        case .summary:
            return .selectionSummary
        }
    }
}
