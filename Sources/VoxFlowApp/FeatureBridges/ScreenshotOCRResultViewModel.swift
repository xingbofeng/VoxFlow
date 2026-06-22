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

        let outcome = await service.translate(result)
        switch outcome {
        case .translated(let translatedResult):
            result = translatedResult
            selectedTab = .translation
            statusMessage = "翻译完成"
            Self.logger.info("ScreenshotOCRResultViewModel translate succeeded length=\(translatedResult.translatedText?.count ?? 0)")
        case .translationUnavailable:
            statusMessage = "请先在设置中配置模型"
            Self.logger.debug("ScreenshotOCRResultViewModel translate unavailable")
        case .translationFailed(_, let reason):
            statusMessage = "翻译失败：\(reason)"
            Self.logger.warning("ScreenshotOCRResultViewModel translate failed reason=\(reason)")
        case .recognized, .summarized, .summaryUnavailable, .summaryFailed,
             .captureCancelled, .captureFailed, .ocrFailed, .translatedOverlay:
            statusMessage = "翻译失败"
            Self.logger.warning("ScreenshotOCRResultViewModel translate unexpected state result=\(outcome)")
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

        let outcome = await service.summarize(result)
        switch outcome {
        case .summarized(let summarizedResult):
            result = summarizedResult
            selectedTab = .summary
            statusMessage = "总结完成"
            Self.logger.info("ScreenshotOCRResultViewModel summarize succeeded length=\(summarizedResult.summaryText?.count ?? 0)")
        case .summaryUnavailable:
            statusMessage = "请先在设置中配置模型"
            Self.logger.debug("ScreenshotOCRResultViewModel summarize unavailable")
        case .summaryFailed(_, let reason):
            statusMessage = "总结失败：\(reason)"
            Self.logger.warning("ScreenshotOCRResultViewModel summarize failed reason=\(reason)")
        case .recognized, .translated, .translationUnavailable, .translationFailed,
             .captureCancelled, .captureFailed, .ocrFailed, .translatedOverlay:
            statusMessage = "总结失败"
            Self.logger.warning("ScreenshotOCRResultViewModel summarize unexpected state result=\(outcome)")
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
