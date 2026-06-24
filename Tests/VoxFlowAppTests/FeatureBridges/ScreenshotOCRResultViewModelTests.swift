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

    func testInitialTabCanOpenRecognizedTextDirectly() {
        let recorder = ScreenshotOCRResultRecorder(translatedText: "ignored")
        let viewModel = ScreenshotOCRResultViewModel(
            result: ScreenshotOCRResult(
                originalText: "Error 404",
                originalImage: ScreenshotOCRViewModelImage.make()
            ),
            service: recorder.service,
            clipboard: recorder.clipboard,
            initialTab: .ocr
        )

        XCTAssertEqual(viewModel.selectedTab, .ocr)
        XCTAssertEqual(viewModel.displayedText, "Error 404")
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

    func testTranslateConsumesStreamingEventsFromService() async {
        let translator = ScreenshotOCRViewModelStreamingTranslator(
            blockingText: "blocking result",
            snapshots: ["错误", "错误 404"]
        )
        let recorder = ScreenshotOCRResultRecorder(translator: translator)
        let viewModel = recorder.makeViewModel(
            result: ScreenshotOCRResult(originalText: "Error 404")
        )

        await viewModel.translate()

        XCTAssertEqual(viewModel.result.translatedText, "错误 404")
        XCTAssertEqual(viewModel.selectedTab, .translation)
        XCTAssertEqual(viewModel.displayedText, "错误 404")
        XCTAssertEqual(viewModel.statusMessage, "翻译完成")
        XCTAssertEqual(translator.blockingRequestCount, 0)
        XCTAssertEqual(translator.streamingRequestCount, 1)
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

    func testCopySelectedImageUsesOriginalScreenshot() {
        let recorder = ScreenshotOCRResultRecorder(translatedText: "ignored")
        let image = ScreenshotOCRViewModelImage.make(width: 3, height: 5)
        let viewModel = recorder.makeViewModel(
            result: ScreenshotOCRResult(
                originalText: "Error 404",
                originalImage: image
            )
        )

        viewModel.copySelectedImage()

        XCTAssertEqual(recorder.clipboard.copiedImageSizes, [CGSize(width: 3, height: 5)])
        XCTAssertEqual(viewModel.statusMessage, "已复制图片")
    }

    func testCopySelectedImageUsesTranslatedOverlayWhenVisible() {
        let recorder = ScreenshotOCRResultRecorder(translatedText: "ignored")
        let originalImage = ScreenshotOCRViewModelImage.make(width: 3, height: 5)
        let overlayImage = ScreenshotOCRViewModelImage.make(width: 7, height: 9)
        let viewModel = ScreenshotOCRResultViewModel(
            result: ScreenshotOCRResult(
                originalText: "Error 404",
                originalImage: originalImage
            ),
            service: recorder.service,
            clipboard: recorder.clipboard,
            initialTab: .translatedOverlay,
            translatedOverlayImage: overlayImage
        )

        viewModel.copySelectedImage()

        XCTAssertEqual(recorder.clipboard.copiedImageSizes, [CGSize(width: 7, height: 9)])
        XCTAssertEqual(viewModel.statusMessage, "已复制图片")
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

    func testCloseCancelsActiveTranslationTaskAndKeepsPartialResult() async {
        let translator = CancellableScreenshotOCRViewModelStreamingTranslator(firstSnapshot: "partial translation")
        let recorder = ScreenshotOCRResultRecorder(translator: translator)
        let viewModel = recorder.makeViewModel(
            result: ScreenshotOCRResult(originalText: "Long recognized text")
        )

        viewModel.startTranslationTask()
        await translator.waitUntilStreamStarted()
        await waitUntil { viewModel.result.translatedText == "partial translation" }

        XCTAssertTrue(viewModel.isTranslating)

        viewModel.close()
        await translator.waitUntilTerminated()

        XCTAssertEqual(viewModel.result.translatedText, "partial translation")
        XCTAssertFalse(viewModel.isTranslating)
        XCTAssertEqual(recorder.speech.stopCount, 1)
    }

    func testTranslateFailureKeepsPartialResultAndShowsPartialCompletionMessage() async {
        let translator = FailingAfterPartialScreenshotOCRViewModelTranslator(
            snapshot: "partial translation",
            errorMessage: "network dropped"
        )
        let recorder = ScreenshotOCRResultRecorder(translator: translator)
        let viewModel = recorder.makeViewModel(
            result: ScreenshotOCRResult(originalText: "Long recognized text")
        )

        await viewModel.translate()

        XCTAssertEqual(viewModel.result.translatedText, "partial translation")
        XCTAssertEqual(viewModel.statusMessage, "翻译部分完成：network dropped")
        XCTAssertFalse(viewModel.isTranslating)
    }

    func testSummarizeFailureKeepsPartialResultAndShowsPartialCompletionMessage() async {
        let translator = FailingAfterPartialScreenshotOCRViewModelTranslator(
            snapshot: "partial summary",
            errorMessage: "network dropped"
        )
        let recorder = ScreenshotOCRResultRecorder(translator: translator)
        let viewModel = recorder.makeViewModel(
            result: ScreenshotOCRResult(originalText: "Long recognized text")
        )

        await viewModel.summarize()

        XCTAssertEqual(viewModel.result.summaryText, "partial summary")
        XCTAssertEqual(viewModel.statusMessage, "总结部分完成：network dropped")
        XCTAssertFalse(viewModel.isSummarizing)
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
private final class CapturingScreenshotClipboard: ScreenshotOCRResultClipboard {
    private(set) var copiedTexts: [String] = []
    private(set) var copiedImageSizes: [CGSize] = []

    func setString(_ text: String) -> Bool {
        copiedTexts.append(text)
        return true
    }

    func setImage(_ image: CGImage) -> Bool {
        copiedImageSizes.append(CGSize(width: image.width, height: image.height))
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

    func recognizeTextLines(in image: CGImage) async throws -> [OCRLine] {
        text
            .split(separator: "\n")
            .enumerated()
            .map { index, line in
                OCRLine(
                    text: String(line),
                    boundingBox: CGRect(x: 0, y: CGFloat(index) * 20, width: CGFloat(image.width), height: 20)
                )
            }
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

private final class ScreenshotOCRViewModelStreamingTranslator: StreamingPromptAwareTextRefining, @unchecked Sendable {
    var isEnabled = true
    var isConfigured = true
    let blockingText: String
    let snapshots: [String]
    private(set) var blockingRequestCount = 0
    private(set) var streamingRequestCount = 0

    init(blockingText: String, snapshots: [String]) {
        self.blockingText = blockingText
        self.snapshots = snapshots
    }

    func refine(_ text: String) async throws -> String {
        blockingRequestCount += 1
        return blockingText
    }

    func refine(_ request: TextRefinementRequest) async throws -> String {
        blockingRequestCount += 1
        return blockingText
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

private final class CancellableScreenshotOCRViewModelStreamingTranslator: StreamingPromptAwareTextRefining, @unchecked Sendable {
    var isEnabled = true
    var isConfigured = true
    private let firstSnapshot: String
    private let lock = NSLock()
    private var streamStartedContinuation: CheckedContinuation<Void, Never>?
    private var streamTerminatedContinuation: CheckedContinuation<Void, Never>?
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
            lock.withLock {
                if didStart {
                    continuation.resume()
                } else {
                    streamStartedContinuation = continuation
                }
            }
        }
    }

    func waitUntilTerminated() async {
        await withCheckedContinuation { continuation in
            lock.withLock {
                if didTerminate {
                    continuation.resume()
                } else {
                    streamTerminatedContinuation = continuation
                }
            }
        }
    }

    private func signalStarted() {
        lock.withLock {
            didStart = true
            streamStartedContinuation?.resume()
            streamStartedContinuation = nil
        }
    }

    private func signalTerminated() {
        lock.withLock {
            didTerminate = true
            streamTerminatedContinuation?.resume()
            streamTerminatedContinuation = nil
        }
    }
}

private final class FailingAfterPartialScreenshotOCRViewModelTranslator: StreamingPromptAwareTextRefining, @unchecked Sendable {
    var isEnabled = true
    var isConfigured = true
    private let snapshot: String
    private let errorMessage: String

    init(snapshot: String, errorMessage: String) {
        self.snapshot = snapshot
        self.errorMessage = errorMessage
    }

    func refine(_ text: String) async throws -> String {
        throw Failure(message: errorMessage)
    }

    func refine(_ request: TextRefinementRequest) async throws -> String {
        throw Failure(message: errorMessage)
    }

    func refineStream(_ request: TextRefinementRequest) -> AsyncThrowingStream<String, Error> {
        let snapshot = snapshot
        let errorMessage = errorMessage
        return AsyncThrowingStream { continuation in
            continuation.yield(snapshot)
            continuation.finish(throwing: Failure(message: errorMessage))
        }
    }

    private struct Failure: LocalizedError {
        let message: String

        var errorDescription: String? {
            message
        }
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
    static func make(width: Int = 1, height: Int = 1) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }
}
