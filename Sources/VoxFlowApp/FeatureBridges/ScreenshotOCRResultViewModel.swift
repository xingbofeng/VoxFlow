import Foundation

enum ScreenshotOCRResultTab: Equatable, Hashable {
    case originalImage
    case ocr
    case translation
    case summary
}

struct ScreenshotOCRPlaybackState: Equatable {
    let target: ScreenshotOCRResultTab
    let text: String
}

@MainActor
final class ScreenshotOCRResultViewModel: ObservableObject {
    @Published private(set) var result: ScreenshotOCRResult
    @Published var selectedTab: ScreenshotOCRResultTab = .originalImage
    @Published private(set) var isTranslating = false
    @Published private(set) var isSummarizing = false
    @Published private(set) var statusMessage: String?
    @Published private(set) var playbackState: ScreenshotOCRPlaybackState?

    private let service: ScreenshotOCRService
    private let clipboard: any ClipboardSetting

    init(
        result: ScreenshotOCRResult,
        service: ScreenshotOCRService,
        clipboard: any ClipboardSetting
    ) {
        self.result = result
        self.service = service
        self.clipboard = clipboard
    }

    var availableTabs: [ScreenshotOCRResultTab] {
        [.originalImage, .ocr, .translation, .summary]
    }

    var displayedText: String {
        switch selectedTab {
        case .originalImage:
            return ""
        case .ocr:
            return result.originalText
        case .translation:
            return result.translatedText ?? result.originalText
        case .summary:
            return result.summaryText ?? result.translatedText ?? result.originalText
        }
    }

    var hasTranslation: Bool {
        result.translatedText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    var hasSummary: Bool {
        result.summaryText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    var hasRecognizedText: Bool {
        !result.originalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var isLoadingSelectedTab: Bool {
        switch selectedTab {
        case .translation:
            return isTranslating
        case .summary:
            return isSummarizing
        case .originalImage, .ocr:
            return false
        }
    }

    func activateSelectedTabIfNeeded() async {
        switch selectedTab {
        case .translation where !hasTranslation:
            await translate()
        case .summary where !hasSummary:
            await summarize()
        case .originalImage, .ocr, .translation, .summary:
            break
        }
    }

    func translate() async {
        guard !isTranslating else { return }
        guard hasRecognizedText else {
            statusMessage = "未识别到文字，无法翻译"
            return
        }
        isTranslating = true
        statusMessage = "正在翻译..."
        defer {
            isTranslating = false
        }

        let outcome = await service.translate(result)
        switch outcome {
        case .translated(let translatedResult):
            result = translatedResult
            selectedTab = .translation
            statusMessage = "翻译完成"
        case .translationUnavailable:
            statusMessage = "请先在设置中配置 LLM"
        case .translationFailed(_, let reason):
            statusMessage = "翻译失败：\(reason)"
        case .recognized, .summarized, .summaryUnavailable, .summaryFailed,
             .captureCancelled, .captureFailed, .ocrFailed:
            statusMessage = "翻译失败"
        }
    }

    func summarize() async {
        guard !isSummarizing else { return }
        guard hasRecognizedText || hasTranslation else {
            statusMessage = "未识别到文字，无法总结"
            return
        }
        isSummarizing = true
        statusMessage = "正在总结..."
        defer {
            isSummarizing = false
        }

        let outcome = await service.summarize(result)
        switch outcome {
        case .summarized(let summarizedResult):
            result = summarizedResult
            selectedTab = .summary
            statusMessage = "总结完成"
        case .summaryUnavailable:
            statusMessage = "请先在设置中配置 LLM"
        case .summaryFailed(_, let reason):
            statusMessage = "总结失败：\(reason)"
        case .recognized, .translated, .translationUnavailable, .translationFailed,
             .captureCancelled, .captureFailed, .ocrFailed:
            statusMessage = "总结失败"
        }
    }

    func speakSelectedText() {
        guard selectedTab != .originalImage else {
            statusMessage = "请选择 OCR、翻译或总结内容朗读"
            return
        }
        let text = displayedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            statusMessage = "没有可朗读内容"
            return
        }
        let playbackTarget = selectedTab
        service.speak(playbackTarget.speechTarget, from: result) { [weak self] in
            guard let self,
                  self.playbackState?.target == playbackTarget else {
                return
            }
            self.playbackState = nil
            self.statusMessage = "朗读完成"
        }
        playbackState = ScreenshotOCRPlaybackState(target: selectedTab, text: text)
        statusMessage = "正在朗读"
    }

    func stopSpeaking() {
        service.stopSpeaking()
        playbackState = nil
        statusMessage = "已停止朗读"
    }

    func close() {
        service.stopSpeaking()
        playbackState = nil
    }

    func copySelectedText() {
        guard selectedTab != .originalImage else {
            statusMessage = "原图已在剪切板"
            return
        }
        if clipboard.setString(displayedText) {
            statusMessage = "已复制"
        } else {
            statusMessage = "复制失败"
        }
    }
}

private extension ScreenshotOCRResultTab {
    var speechTarget: ScreenshotOCRSpeechTarget {
        switch self {
        case .originalImage, .ocr:
            return .original
        case .translation:
            return .translated
        case .summary:
            return .summary
        }
    }
}
