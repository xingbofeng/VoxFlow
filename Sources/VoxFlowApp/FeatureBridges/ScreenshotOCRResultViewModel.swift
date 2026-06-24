import CoreGraphics
import Foundation

enum ScreenshotOCRResultTab: Equatable, Hashable {
    case originalImage
    case ocr
    case translation
    case summary
    case translatedOverlay
}

struct ScreenshotOCRPlaybackState: Equatable {
    let target: ScreenshotOCRResultTab
    let text: String
}

@MainActor
final class ScreenshotOCRResultViewModel: ObservableObject {
    private static let logger = AppLogger.general

    @Published private(set) var result: ScreenshotOCRResult
    @Published var selectedTab: ScreenshotOCRResultTab = .originalImage
    @Published private(set) var isTranslating = false
    @Published private(set) var isSummarizing = false
    @Published private(set) var statusMessage: String?
    @Published private(set) var playbackState: ScreenshotOCRPlaybackState?
    /// 翻译覆盖图（工具栏一键翻译流程产生）。非空时 translatedOverlay tab 可用。
    @Published private(set) var translatedOverlayImage: CGImage?

    private let service: ScreenshotOCRService
    private let clipboard: any ScreenshotOCRResultClipboard
    private var activeTranslationTask: Task<Void, Never>?
    private var activeSummaryTask: Task<Void, Never>?

    init(
        result: ScreenshotOCRResult,
        service: ScreenshotOCRService,
        clipboard: any ScreenshotOCRResultClipboard,
        initialTab: ScreenshotOCRResultTab = .originalImage,
        translatedOverlayImage: CGImage? = nil
    ) {
        self.result = result
        self.service = service
        self.clipboard = clipboard
        self.selectedTab = initialTab
        self.translatedOverlayImage = translatedOverlayImage
    }

    var availableTabs: [ScreenshotOCRResultTab] {
        var tabs: [ScreenshotOCRResultTab] = [.originalImage, .ocr, .translation, .summary]
        if translatedOverlayImage != nil {
            tabs.append(.translatedOverlay)
        }
        return tabs
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
        case .translatedOverlay:
            return ""
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
        case .originalImage, .ocr, .translatedOverlay:
            return false
        }
    }

    var selectedImage: CGImage? {
        switch selectedTab {
        case .translatedOverlay:
            return translatedOverlayImage ?? result.originalImage
        case .originalImage, .ocr, .translation, .summary:
            return result.originalImage
        }
    }

    func activateSelectedTabIfNeeded() async {
        Self.logger.debug("ScreenshotOCRResultViewModel activateSelectedTabIfNeeded tab=\(selectedTab)")
        switch selectedTab {
        case .translation where !hasTranslation:
            await translate()
        case .summary where !hasSummary:
            await summarize()
        case .originalImage, .ocr, .translation, .summary, .translatedOverlay:
            break
        }
    }

    func activateSelectedTabTaskIfNeeded() {
        Self.logger.debug("ScreenshotOCRResultViewModel activateSelectedTabTaskIfNeeded tab=\(selectedTab)")
        switch selectedTab {
        case .translation where !hasTranslation:
            startTranslationTask()
        case .summary where !hasSummary:
            startSummaryTask()
        case .originalImage, .ocr, .translation, .summary, .translatedOverlay:
            break
        }
    }

    func startTranslationTask() {
        activeTranslationTask?.cancel()
        activeTranslationTask = Task { [weak self] in
            await self?.translate()
            self?.activeTranslationTask = nil
        }
    }

    func startSummaryTask() {
        activeSummaryTask?.cancel()
        activeSummaryTask = Task { [weak self] in
            await self?.summarize()
            self?.activeSummaryTask = nil
        }
    }

    func cancelActiveTransformTasks() {
        activeTranslationTask?.cancel()
        activeTranslationTask = nil
        activeSummaryTask?.cancel()
        activeSummaryTask = nil
        if isTranslating {
            isTranslating = false
            statusMessage = "已取消翻译"
        }
        if isSummarizing {
            isSummarizing = false
            statusMessage = "已取消总结"
        }
    }

    func translate() async {
        Self.logger.debug("ScreenshotOCRResultViewModel translate requested tab=\(selectedTab)")
        guard !isTranslating else { return }
        guard hasRecognizedText else {
            statusMessage = "未识别到文字，无法翻译"
            Self.logger.debug("ScreenshotOCRResultViewModel translate aborted: no recognized text")
            return
        }
        isTranslating = true
        statusMessage = "正在翻译..."
        defer {
            isTranslating = false
        }

        selectedTab = .translation
        for await event in service.translationEvents(for: result) {
            switch event {
            case .started:
                statusMessage = "正在翻译..."
            case .partialText(let text):
                result.translatedText = text
            case .unitCompleted:
                break
            case .completed(let text):
                result.translatedText = text
                statusMessage = "翻译完成"
                Self.logger.info("ScreenshotOCRResultViewModel translate succeeded length=\(text.count)")
            case .cancelled(let partialText):
                if !partialText.isEmpty {
                    result.translatedText = partialText
                }
                statusMessage = "已取消翻译"
                Self.logger.debug("ScreenshotOCRResultViewModel translate cancelled")
            case .failed(let message, let partialText):
                if !partialText.isEmpty {
                    result.translatedText = partialText
                }
                statusMessage = message == "请先在设置中配置模型"
                    ? message
                    : (partialText.isEmpty ? "翻译失败：\(message)" : "翻译部分完成：\(message)")
                Self.logger.warning("ScreenshotOCRResultViewModel translate failed reason=\(message)")
            }
        }
    }

    func summarize() async {
        Self.logger.debug("ScreenshotOCRResultViewModel summarize requested tab=\(selectedTab)")
        guard !isSummarizing else { return }
        guard hasRecognizedText || hasTranslation else {
            statusMessage = "未识别到文字，无法总结"
            Self.logger.debug("ScreenshotOCRResultViewModel summarize aborted: no text")
            return
        }
        isSummarizing = true
        statusMessage = "正在总结..."
        defer {
            isSummarizing = false
        }

        selectedTab = .summary
        for await event in service.summaryEvents(for: result) {
            switch event {
            case .started:
                statusMessage = "正在总结..."
            case .partialText(let text):
                result.summaryText = text
            case .unitCompleted:
                break
            case .completed(let text):
                result.summaryText = text
                statusMessage = "总结完成"
                Self.logger.info("ScreenshotOCRResultViewModel summarize succeeded length=\(text.count)")
            case .cancelled(let partialText):
                if !partialText.isEmpty {
                    result.summaryText = partialText
                }
                statusMessage = "已取消总结"
                Self.logger.debug("ScreenshotOCRResultViewModel summarize cancelled")
            case .failed(let message, let partialText):
                if !partialText.isEmpty {
                    result.summaryText = partialText
                }
                statusMessage = message == "请先在设置中配置模型"
                    ? message
                    : (partialText.isEmpty ? "总结失败：\(message)" : "总结部分完成：\(message)")
                Self.logger.warning("ScreenshotOCRResultViewModel summarize failed reason=\(message)")
            }
        }
    }

    func speakSelectedText() {
        guard selectedTab != .originalImage else {
            statusMessage = "请选择识别结果、翻译或总结内容朗读"
            Self.logger.debug("ScreenshotOCRResultViewModel speak skipped: no selectable text")
            return
        }
        let text = displayedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            statusMessage = "没有可朗读内容"
            Self.logger.debug("ScreenshotOCRResultViewModel speak skipped: selected text empty")
            return
        }
        Self.logger.info("ScreenshotOCRResultViewModel speak selected tab=\(selectedTab) textLength=\(text.count)")
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
        Self.logger.debug("ScreenshotOCRResultViewModel stopSpeaking")
        service.stopSpeaking()
        playbackState = nil
        statusMessage = "已停止朗读"
    }

    func close() {
        Self.logger.debug("ScreenshotOCRResultViewModel close")
        cancelActiveTransformTasks()
        service.stopSpeaking()
        playbackState = nil
    }

    func copySelectedText() {
        guard selectedTab != .originalImage else {
            statusMessage = "原图已在剪切板"
            Self.logger.debug("ScreenshotOCRResultViewModel copy skipped: originalImage tab")
            return
        }
        if clipboard.setString(displayedText) {
            statusMessage = "已复制"
            Self.logger.info("ScreenshotOCRResultViewModel copy succeeded tab=\(selectedTab)")
        } else {
            statusMessage = "复制失败"
            Self.logger.warning("ScreenshotOCRResultViewModel copy failed tab=\(selectedTab)")
        }
    }

    func copySelectedImage() {
        guard let image = selectedImage else {
            statusMessage = "暂无可复制图片"
            Self.logger.debug("ScreenshotOCRResultViewModel image copy skipped: no image")
            return
        }
        if clipboard.setImage(image) {
            statusMessage = "已复制图片"
            Self.logger.info("ScreenshotOCRResultViewModel image copy succeeded tab=\(selectedTab)")
        } else {
            statusMessage = "复制图片失败"
            Self.logger.warning("ScreenshotOCRResultViewModel image copy failed tab=\(selectedTab)")
        }
    }
}

private extension ScreenshotOCRResultTab {
    var speechTarget: ScreenshotOCRSpeechTarget {
        switch self {
        case .originalImage, .ocr, .translatedOverlay:
            return .original
        case .translation:
            return .translated
        case .summary:
            return .summary
        }
    }
}
