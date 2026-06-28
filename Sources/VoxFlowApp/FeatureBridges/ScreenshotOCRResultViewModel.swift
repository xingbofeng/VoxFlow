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
    private let configRequiredMessage = L10n.localize(
        "screenshot.refine.unavailable.config_required",
        comment: ""
    )

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
            statusMessage = L10n.localize(
                "screenshot.result.translation_cancelled",
                comment: ""
            )
        }
        if isSummarizing {
            isSummarizing = false
            statusMessage = L10n.localize("screenshot.result.summary_cancelled", comment: "")
        }
    }

    func translate() async {
        Self.logger.debug("ScreenshotOCRResultViewModel translate requested tab=\(selectedTab)")
        guard !isTranslating else { return }
        guard hasRecognizedText else {
            statusMessage = L10n.localize(
                "screenshot.result.no_text_for_translation",
                comment: ""
            )
            Self.logger.debug("ScreenshotOCRResultViewModel translate aborted: no recognized text")
            return
        }
        isTranslating = true
        statusMessage = L10n.localize("screenshot.result.translating", comment: "")
        defer {
            isTranslating = false
        }

        selectedTab = .translation
        for await event in service.translationEvents(for: result) {
            switch event {
            case .started:
                statusMessage = L10n.localize("screenshot.result.translating", comment: "")
            case .partialText(let text):
                result.translatedText = text
            case .unitCompleted:
                break
            case .completed(let text):
                result.translatedText = text
                statusMessage = L10n.localize("screenshot.result.translation_completed", comment: "")
                Self.logger.info("ScreenshotOCRResultViewModel translate succeeded length=\(text.count)")
            case .cancelled(let partialText):
                if !partialText.isEmpty {
                    result.translatedText = partialText
                }
                statusMessage = L10n.localize(
                    "screenshot.result.translation_cancelled",
                    comment: ""
                )
                Self.logger.debug("ScreenshotOCRResultViewModel translate cancelled")
            case .failed(let message, let partialText):
                if !partialText.isEmpty {
                    result.translatedText = partialText
                }
                statusMessage = message == configRequiredMessage
                    ? message
                    : String(
                        format: L10n.localize(
                            partialText.isEmpty
                                ? "screenshot.result.translation_failed_format"
                                : "screenshot.result.translation_partial_format",
                            comment: ""
                        ),
                        message
                    )
                Self.logger.warning("ScreenshotOCRResultViewModel translate failed reason=\(message)")
            }
        }
    }

    func summarize() async {
        Self.logger.debug("ScreenshotOCRResultViewModel summarize requested tab=\(selectedTab)")
        guard !isSummarizing else { return }
        guard hasRecognizedText || hasTranslation else {
            statusMessage = L10n.localize(
                "screenshot.result.no_text_for_summary",
                comment: ""
            )
            Self.logger.debug("ScreenshotOCRResultViewModel summarize aborted: no text")
            return
        }
        isSummarizing = true
        statusMessage = L10n.localize("screenshot.result.summarizing", comment: "")
        defer {
            isSummarizing = false
        }

        selectedTab = .summary
        for await event in service.summaryEvents(for: result) {
            switch event {
            case .started:
                statusMessage = L10n.localize("screenshot.result.summarizing", comment: "")
            case .partialText(let text):
                result.summaryText = text
            case .unitCompleted:
                break
            case .completed(let text):
                result.summaryText = text
                statusMessage = L10n.localize("screenshot.result.summary_completed", comment: "")
                Self.logger.info("ScreenshotOCRResultViewModel summarize succeeded length=\(text.count)")
            case .cancelled(let partialText):
                if !partialText.isEmpty {
                    result.summaryText = partialText
                }
                statusMessage = L10n.localize("screenshot.result.summary_cancelled", comment: "")
                Self.logger.debug("ScreenshotOCRResultViewModel summarize cancelled")
            case .failed(let message, let partialText):
                if !partialText.isEmpty {
                    result.summaryText = partialText
                }
                statusMessage = message == configRequiredMessage
                    ? message
                    : String(
                        format: L10n.localize(
                            partialText.isEmpty
                                ? "screenshot.result.summary_failed_format"
                                : "screenshot.result.summary_partial_format",
                            comment: ""
                        ),
                        message
                    )
                Self.logger.warning("ScreenshotOCRResultViewModel summarize failed reason=\(message)")
            }
        }
    }

    func speakSelectedText() {
        guard selectedTab != .originalImage else {
            statusMessage = L10n.localize("screenshot.result.read_select_prompt", comment: "")
            Self.logger.debug("ScreenshotOCRResultViewModel speak skipped: no selectable text")
            return
        }
        let text = displayedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            statusMessage = L10n.localize("screenshot.result.read_no_content", comment: "")
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
            self.statusMessage = L10n.localize("screenshot.result.read_complete", comment: "")
        }
        playbackState = ScreenshotOCRPlaybackState(target: selectedTab, text: text)
        statusMessage = L10n.localize("screenshot.result.reading", comment: "")
    }

    func stopSpeaking() {
        Self.logger.debug("ScreenshotOCRResultViewModel stopSpeaking")
        service.stopSpeaking()
        playbackState = nil
        statusMessage = L10n.localize("screenshot.result.read_stopped", comment: "")
    }

    func close() {
        Self.logger.debug("ScreenshotOCRResultViewModel close")
        cancelActiveTransformTasks()
        service.stopSpeaking()
        playbackState = nil
    }

    func copySelectedText() {
        guard selectedTab != .originalImage else {
            statusMessage = L10n.localize("screenshot.result.original_in_clipboard", comment: "")
            Self.logger.debug("ScreenshotOCRResultViewModel copy skipped: originalImage tab")
            return
        }
        if clipboard.setString(displayedText) {
            statusMessage = L10n.localize("screenshot.result.copied", comment: "")
            Self.logger.info("ScreenshotOCRResultViewModel copy succeeded tab=\(selectedTab)")
        } else {
            statusMessage = L10n.localize("screenshot.result.copy_failed", comment: "")
            Self.logger.warning("ScreenshotOCRResultViewModel copy failed tab=\(selectedTab)")
        }
    }

    func copySelectedImage() {
        guard let image = selectedImage else {
            statusMessage = L10n.localize("screenshot.result.no_copyable_image", comment: "")
            Self.logger.debug("ScreenshotOCRResultViewModel image copy skipped: no image")
            return
        }
        if clipboard.setImage(image) {
            statusMessage = L10n.localize("screenshot.result.copied_image", comment: "")
            Self.logger.info("ScreenshotOCRResultViewModel image copy succeeded tab=\(selectedTab)")
        } else {
            statusMessage = L10n.localize("screenshot.result.copy_image_failed", comment: "")
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
