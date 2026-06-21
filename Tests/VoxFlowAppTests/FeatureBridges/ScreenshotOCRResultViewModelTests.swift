import CoreGraphics
import XCTest
@testable import VoxFlowApp

@MainActor
final class ScreenshotOCRResultViewModelTests: XCTestCase {
    func testDefaultTabShowsOriginalScreenshotBeforeOCRText() {
        let recorder = ScreenshotOCRResultRecorder(translatedText: "ignored")
        let viewModel = recorder.makeViewModel(
            result: ScreenshotOCRResult(
                originalText: "Error 404",
                originalImage: ScreenshotOCRViewModelImage.make()
            )
        )

        XCTAssertEqual(viewModel.selectedTab, .originalImage)
        XCTAssertEqual(viewModel.availableTabs, [.originalImage, .ocr, .translation, .summary])
        XCTAssertEqual(viewModel.displayedText, "")
        XCTAssertNotNil(viewModel.result.originalImage)
    }

    func testTranslateUpdatesResultAndSelectsTranslationTab() async {
        let recorder = ScreenshotOCRResultRecorder(translatedText: "错误 404")
        let viewModel = recorder.makeViewModel(
            result: ScreenshotOCRResult(originalText: "Error 404")
        )

        await viewModel.translate()

        XCTAssertEqual(viewModel.result.translatedText, "错误 404")
        XCTAssertEqual(viewModel.selectedTab, .translation)
        XCTAssertEqual(viewModel.displayedText, "错误 404")
        XCTAssertEqual(viewModel.statusMessage, "翻译完成")
    }

    func testCopySelectedTextUsesClipboard() {
        let recorder = ScreenshotOCRResultRecorder(translatedText: "ignored")
        let viewModel = recorder.makeViewModel(
            result: ScreenshotOCRResult(
                originalText: "Error 404",
                translatedText: "错误 404"
            )
        )
        viewModel.selectedTab = .translation

        viewModel.copySelectedText()

        XCTAssertEqual(recorder.clipboard.copiedTexts, ["错误 404"])
        XCTAssertEqual(viewModel.statusMessage, "已复制")
    }

    func testSummarizeUpdatesResultAndSelectsSummaryTab() async {
        let recorder = ScreenshotOCRResultRecorder(translatedText: "检查 URL 或返回首页。")
        let viewModel = recorder.makeViewModel(
            result: ScreenshotOCRResult(
                originalText: "Error 404 - Page Not Found",
                translatedText: "错误 404 - 页面未找到"
            )
        )

        await viewModel.summarize()

        XCTAssertEqual(viewModel.result.summaryText, "检查 URL 或返回首页。")
        XCTAssertEqual(viewModel.selectedTab, .summary)
        XCTAssertEqual(viewModel.displayedText, "检查 URL 或返回首页。")
        XCTAssertEqual(viewModel.statusMessage, "总结完成")
    }

    func testActivatingSummaryTabSummarizesWhenNeeded() async {
        let recorder = ScreenshotOCRResultRecorder(translatedText: "检查 URL 或返回首页。")
        let viewModel = recorder.makeViewModel(
            result: ScreenshotOCRResult(originalText: "Error 404 - Page Not Found")
        )
        viewModel.selectedTab = .summary

        await viewModel.activateSelectedTabIfNeeded()

        XCTAssertEqual(viewModel.result.summaryText, "检查 URL 或返回首页。")
        XCTAssertEqual(viewModel.selectedTab, .summary)
    }

    func testCopySelectedTextUsesSummaryTab() {
        let recorder = ScreenshotOCRResultRecorder(translatedText: "ignored")
        let viewModel = recorder.makeViewModel(
            result: ScreenshotOCRResult(
                originalText: "Error 404",
                translatedText: "错误 404",
                summaryText: "检查 URL。"
            )
        )
        viewModel.selectedTab = .summary

        viewModel.copySelectedText()

        XCTAssertEqual(recorder.clipboard.copiedTexts, ["检查 URL。"])
    }

    func testSpeakSelectedTextUsesCurrentTabText() {
        let recorder = ScreenshotOCRResultRecorder(translatedText: "ignored")
        let viewModel = recorder.makeViewModel(
            result: ScreenshotOCRResult(
                originalText: "Error 404",
                translatedText: "错误 404"
            )
        )
        viewModel.selectedTab = .translation

        viewModel.speakSelectedText()

        XCTAssertEqual(recorder.speech.spokenTexts, ["错误 404"])
        XCTAssertEqual(viewModel.playbackState?.target, .translation)
        XCTAssertEqual(viewModel.playbackState?.text, "错误 404")
    }

    func testNaturalSpeechCompletionClearsPlaybackState() {
        let recorder = ScreenshotOCRResultRecorder(translatedText: "ignored")
        let viewModel = recorder.makeViewModel(
            result: ScreenshotOCRResult(
                originalText: "Error 404",
                translatedText: "错误 404"
            )
        )
        viewModel.selectedTab = .translation

        viewModel.speakSelectedText()
        recorder.speech.finishSpeech()

        XCTAssertNil(viewModel.playbackState)
        XCTAssertEqual(viewModel.statusMessage, "朗读完成")
    }

    func testSpeakSelectedTextUsesSummaryTabText() {
        let recorder = ScreenshotOCRResultRecorder(translatedText: "ignored")
        let viewModel = recorder.makeViewModel(
            result: ScreenshotOCRResult(
                originalText: "Error 404",
                translatedText: "错误 404",
                summaryText: "检查 URL。"
            )
        )
        viewModel.selectedTab = .summary

        viewModel.speakSelectedText()

        XCTAssertEqual(recorder.speech.spokenTexts, ["检查 URL。"])
    }

    func testCloseStopsActiveSpeechAndClearsPlaybackState() {
        let recorder = ScreenshotOCRResultRecorder(translatedText: "ignored")
        let viewModel = recorder.makeViewModel(
            result: ScreenshotOCRResult(originalText: "Error 404")
        )

        viewModel.speakSelectedText()
        viewModel.close()

        XCTAssertEqual(recorder.speech.stopCount, 1)
        XCTAssertNil(viewModel.playbackState)
    }

    func testTranslateWithoutRecognizedTextKeepsLoadingStateOffAndShowsMessage() async {
        let recorder = ScreenshotOCRResultRecorder(translatedText: "ignored")
        let viewModel = recorder.makeViewModel(
            result: ScreenshotOCRResult(
                originalText: "",
                originalImage: ScreenshotOCRViewModelImage.make(),
                ocrStatusMessage: "未识别到截图文字"
            )
        )

        await viewModel.translate()

        XCTAssertFalse(viewModel.isTranslating)
        XCTAssertEqual(viewModel.statusMessage, "未识别到文字，无法翻译")
        XCTAssertEqual(viewModel.selectedTab, .originalImage)
    }

    func testSelectedTabLoadingDoesNotLeakTranslationSpinnerIntoSummaryTab() async {
        let translator = SuspendedScreenshotOCRViewModelTranslator()
        let recorder = ScreenshotOCRResultRecorder(translator: translator)
        let viewModel = recorder.makeViewModel(
            result: ScreenshotOCRResult(originalText: "需要翻译的文本")
        )
        viewModel.selectedTab = .translation

        let task = Task { await viewModel.translate() }
        await translator.waitUntilStarted()

        XCTAssertTrue(viewModel.isLoadingSelectedTab)

        viewModel.selectedTab = .summary

        XCTAssertFalse(viewModel.isLoadingSelectedTab)

        translator.finish(with: "Translated text")
        await task.value
    }
}

@MainActor
private final class ScreenshotOCRResultRecorder {
    let service: ScreenshotOCRService
    let speech: ScreenshotOCRViewModelSpeech
    let clipboard: CapturingScreenshotClipboard

    convenience init(translatedText: String) {
        self.init(translator: ScreenshotOCRViewModelTranslator(text: translatedText))
    }

    init(translator: any PromptAwareTextRefining) {
        let imageProvider = ScreenshotOCRViewModelImageProvider(image: ScreenshotOCRViewModelImage.make())
        let ocr = ScreenshotOCRViewModelOCR(text: "recognized")
        speech = ScreenshotOCRViewModelSpeech()
        clipboard = CapturingScreenshotClipboard()
        service = ScreenshotOCRService(
            imageProvider: imageProvider,
            ocrRecognizer: ocr,
            translator: translator,
            speechService: speech,
            clipboard: ScreenshotOCRViewModelImageClipboard(),
            lastResultStore: InMemoryLastResultStore()
        )
    }

    func makeViewModel(result: ScreenshotOCRResult) -> ScreenshotOCRResultViewModel {
        ScreenshotOCRResultViewModel(
            result: result,
            service: service,
            clipboard: clipboard
        )
    }
}

@MainActor
private final class CapturingScreenshotClipboard: ClipboardSetting {
    private(set) var copiedTexts: [String] = []

    func setString(_ text: String) -> Bool {
        copiedTexts.append(text)
        return true
    }
}

@MainActor
private final class ScreenshotOCRViewModelImageProvider: ScreenshotImageProviding {
    let image: CGImage

    init(image: CGImage) {
        self.image = image
    }

    func captureImage() async throws -> CGImage {
        image
    }
}

@MainActor
private final class ScreenshotOCRViewModelOCR: TextOCRRecognizing, @unchecked Sendable {
    let text: String

    init(text: String) {
        self.text = text
    }

    func recognizeText(in image: CGImage) async throws -> String {
        text
    }
}

private final class ScreenshotOCRViewModelTranslator: PromptAwareTextRefining, @unchecked Sendable {
    var isEnabled = true
    var isConfigured = true
    let text: String

    init(text: String) {
        self.text = text
    }

    func refine(_ text: String) async throws -> String {
        self.text
    }

    func refine(_ request: TextRefinementRequest) async throws -> String {
        text
    }
}

private final class SuspendedScreenshotOCRViewModelTranslator: PromptAwareTextRefining, @unchecked Sendable {
    var isEnabled = true
    var isConfigured = true

    private let lock = NSLock()
    private var startContinuation: CheckedContinuation<Void, Never>?
    private var finishContinuation: CheckedContinuation<String, Never>?
    private var hasStarted = false

    func refine(_ text: String) async throws -> String {
        await withCheckedContinuation { continuation in
            lock.withLock {
                hasStarted = true
                startContinuation?.resume()
                startContinuation = nil
                finishContinuation = continuation
            }
        }
    }

    func refine(_ request: TextRefinementRequest) async throws -> String {
        try await refine(request.text)
    }

    func waitUntilStarted() async {
        await withCheckedContinuation { continuation in
            lock.withLock {
                if hasStarted {
                    continuation.resume()
                } else {
                    startContinuation = continuation
                }
            }
        }
    }

    func finish(with text: String) {
        lock.withLock {
            finishContinuation?.resume(returning: text)
            finishContinuation = nil
        }
    }
}

@MainActor
private final class ScreenshotOCRViewModelSpeech: ScreenshotSpeechSpeaking {
    private(set) var spokenTexts: [String] = []
    private(set) var stopCount = 0

    private var completion: ScreenshotSpeechCompletion?

    func speak(_ text: String, completion: ScreenshotSpeechCompletion?) {
        spokenTexts.append(text)
        self.completion = completion
    }

    func finishSpeech() {
        completion?()
        completion = nil
    }

    func stop() {
        stopCount += 1
    }
}

@MainActor
private final class ScreenshotOCRViewModelImageClipboard: ScreenshotImageClipboardWriting {
    func setImage(_ image: CGImage) -> Bool {
        true
    }
}

private enum ScreenshotOCRViewModelImage {
    static func make() -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        return context.makeImage()!
    }
}
