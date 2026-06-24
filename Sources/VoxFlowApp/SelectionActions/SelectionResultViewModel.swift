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
        activeTransformTask = Task { [weak self] in
            await self?.startTransform()
            self?.activeTransformTask = nil
        }
    }

    func cancelTransform() {
        activeTransformTask?.cancel()
        activeTransformTask = nil
        guard isTransforming else { return }
        isTransforming = false
        statusMessage = operation.cancelledMessage
        recordSelectionHistory(status: .partiallyCompleted, resultText: resultText)
    }

    func startTransform() async {
        guard !isTransforming else { return }
        let text = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            statusMessage = "没有可处理的文本"
            return
        }

        selectedTab = .result
        isTransforming = true
        statusMessage = operation.runningMessage
        defer {
            isTransforming = false
        }

        let request = TextTransformRequest(text: selectedText, operation: operation)
        for await event in transformService.events(for: request) {
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
            statusMessage = "已复制"
        } else {
            statusMessage = "复制失败"
        }
    }

    func replaceOriginal() async {
        await insertDisplayedText(prefix: "", successMessage: "已替换原文")
    }

    func insertAfterSelection() async {
        await insertDisplayedText(prefix: "\n", successMessage: "已插入下一行")
    }

    func speakSelectedText() {
        let text = displayedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            statusMessage = "没有可朗读内容"
            return
        }
        speech.speak(text) { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.playbackState = nil
                self.statusMessage = "朗读完成"
            }
        }
        playbackState = SelectionResultPlaybackState(text: text)
        statusMessage = "正在朗读"
    }

    func stopSpeaking() {
        speech.stop()
        playbackState = nil
        statusMessage = "已停止朗读"
    }

    func close() {
        cancelTransform()
        speech.stop()
        playbackState = nil
    }

    private func insertDisplayedText(prefix: String, successMessage: String) async {
        let text = displayedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            statusMessage = "没有可写入内容"
            return
        }

        let result = await textInserter.insert(prefix + displayedText)
        if result == .success {
            statusMessage = successMessage
            return
        }

        if clipboard.setString(displayedText) {
            statusMessage = "无法写入，已复制"
        } else {
            statusMessage = "写入失败"
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
            return "正在翻译..."
        case .summary:
            return "正在总结..."
        }
    }

    var completedMessage: String {
        switch self {
        case .translation:
            return "翻译完成"
        case .summary:
            return "总结完成"
        }
    }

    var cancelledMessage: String {
        switch self {
        case .translation:
            return "已取消翻译"
        case .summary:
            return "已取消总结"
        }
    }

    var failedPrefix: String {
        switch self {
        case .translation:
            return "翻译失败"
        case .summary:
            return "总结失败"
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
