import CoreGraphics
import XCTest
@testable import VoxFlowApp

@MainActor
final class ScreenshotOCRServiceTests: XCTestCase {
    func testCaptureAndRecognizeReturnsTrimmedOriginalTextAndStoresLastResult() async {
        let recorder = ScreenshotOCRRecorder(
            recognizedText: "  Error 404 - Page Not Found  "
        )

        let outcome = await recorder.service.captureAndRecognize()

        XCTAssertEqual(outcome, .recognized(ScreenshotOCRResult(originalText: "Error 404 - Page Not Found", originalImage: recorder.imageProvider.image)))
        XCTAssertEqual(recorder.imageProvider.captureCount, 1)
        XCTAssertEqual(recorder.ocr.requestCount, 1)
        XCTAssertEqual(recorder.clipboard.copiedImageWidths, [1])
        XCTAssertEqual(recorder.store.lastResultText, "Error 404 - Page Not Found")
    }

    func testCaptureCancellationDoesNotRunOCROrOverwriteLastResult() async {
        let recorder = ScreenshotOCRRecorder(
            recognizedText: "ignored",
            lastResult: "previous text"
        )
        recorder.imageProvider.error = ScreenshotOCRServiceError.captureCancelled

        let outcome = await recorder.service.captureAndRecognize()

        XCTAssertEqual(outcome, .captureCancelled)
        XCTAssertEqual(recorder.ocr.requestCount, 0)
        XCTAssertEqual(recorder.store.lastResultText, "previous text")
    }

    func testCancellationAfterCaptureDoesNotWriteClipboardOrLastResult() async {
        var cancellationChecks = 0
        let recorder = ScreenshotOCRRecorder(
            recognizedText: "ignored",
            lastResult: "previous text",
            isCancelled: {
                cancellationChecks += 1
                return cancellationChecks >= 2
            }
        )

        let outcome = await recorder.service.captureAndRecognize()

        XCTAssertEqual(outcome, .captureCancelled)
        XCTAssertEqual(recorder.clipboard.copiedImageWidths, [])
        XCTAssertEqual(recorder.ocr.requestCount, 0)
        XCTAssertEqual(recorder.store.lastResultText, "previous text")
    }

    func testEmptyOCRTextStillReturnsDisplayableScreenshotResultAndDoesNotOverwriteLastResult() async {
        let recorder = ScreenshotOCRRecorder(
            recognizedText: " \n ",
            lastResult: "previous text"
        )

        let outcome = await recorder.service.captureAndRecognize()

        XCTAssertEqual(
            outcome,
            .recognized(
                ScreenshotOCRResult(
                    originalText: "",
                    originalImage: recorder.imageProvider.image,
                    ocrStatusMessage: "未识别到截图文字"
                )
            )
        )
        XCTAssertEqual(recorder.clipboard.copiedImageWidths, [1])
        XCTAssertEqual(recorder.store.lastResultText, "previous text")
    }

    func testTranslateUsesPromptAwareRefinerAndStoresTranslatedText() async {
        let recorder = ScreenshotOCRRecorder(
            recognizedText: "Error 404",
            translatedText: "错误 404"
        )
        let original = ScreenshotOCRResult(originalText: "Error 404")

        let outcome = await recorder.service.translate(original)

        XCTAssertEqual(
            outcome,
            .translated(
                ScreenshotOCRResult(
                    originalText: "Error 404",
                    translatedText: "错误 404"
                )
            )
        )
        XCTAssertEqual(recorder.translator.requests.map(\.text), ["Error 404"])
        XCTAssertTrue(recorder.translator.requests[0].systemPrompt.contains("截图文字翻译助手"))
        XCTAssertEqual(recorder.store.lastResultText, "错误 404")
    }

    func testTranslateFallsBackWhenLLMIsNotConfigured() async {
        let recorder = ScreenshotOCRRecorder(
            recognizedText: "Error 404",
            translatedText: "ignored",
            translatorConfigured: false
        )
        let original = ScreenshotOCRResult(originalText: "Error 404")

        let outcome = await recorder.service.translate(original)

        XCTAssertEqual(outcome, .translationUnavailable(original))
        XCTAssertTrue(recorder.translator.requests.isEmpty)
    }

    func testSummarizeUsesOCRTextInsteadOfTranslatedTextAndStoresSummaryText() async {
        let recorder = ScreenshotOCRRecorder(
            recognizedText: "Error 404",
            translatedText: "页面不存在，请检查 URL。"
        )
        let result = ScreenshotOCRResult(
            originalText: "Error 404 - Page Not Found",
            translatedText: "错误 404 - 页面未找到"
        )

        let outcome = await recorder.service.summarize(result)

        XCTAssertEqual(
            outcome,
            .summarized(
                ScreenshotOCRResult(
                    originalText: "Error 404 - Page Not Found",
                    translatedText: "错误 404 - 页面未找到",
                    summaryText: "页面不存在，请检查 URL。"
                )
            )
        )
        XCTAssertEqual(recorder.translator.requests.map(\.text), ["Error 404 - Page Not Found"])
        XCTAssertTrue(recorder.translator.requests[0].systemPrompt.contains("截图文字总结助手"))
        XCTAssertEqual(recorder.store.lastResultText, "页面不存在，请检查 URL。")
    }

    func testSummarizeDoesNotRequireDictationCorrectionToggleWhenLLMIsConfigured() async {
        let recorder = ScreenshotOCRRecorder(
            recognizedText: "Error 404",
            translatedText: "页面不存在，请检查 URL。",
            translatorConfigured: true,
            summaryConfigured: true
        )
        recorder.translator.isEnabled = false
        let original = ScreenshotOCRResult(originalText: "Error 404")

        let outcome = await recorder.service.summarize(original)

        XCTAssertEqual(
            outcome,
            .summarized(
                ScreenshotOCRResult(
                    originalText: "Error 404",
                    summaryText: "页面不存在，请检查 URL。"
                )
            )
        )
        XCTAssertEqual(recorder.translator.requests.map(\.text), ["Error 404"])
    }

    func testSummarizeFallsBackWhenLLMIsNotConfigured() async {
        let recorder = ScreenshotOCRRecorder(
            recognizedText: "Error 404",
            translatedText: "ignored",
            translationConfigured: true,
            summaryConfigured: false
        )
        let original = ScreenshotOCRResult(originalText: "Error 404")

        let outcome = await recorder.service.summarize(original)

        XCTAssertEqual(outcome, .summaryUnavailable(original))
        XCTAssertTrue(recorder.translator.requests.isEmpty)
    }

    func testSpeakOriginalTextUsesSystemSpeechService() {
        let recorder = ScreenshotOCRRecorder(recognizedText: "Error 404")
        let result = ScreenshotOCRResult(originalText: "Error 404")

        recorder.service.speak(.original, from: result)

        XCTAssertEqual(recorder.speech.spokenTexts, ["Error 404"])
    }

    func testSpeakTranslatedTextUsesTranslatedTextWhenAvailable() {
        let recorder = ScreenshotOCRRecorder(recognizedText: "Error 404")
        let result = ScreenshotOCRResult(
            originalText: "Error 404",
            translatedText: "错误 404"
        )

        recorder.service.speak(.translated, from: result)

        XCTAssertEqual(recorder.speech.spokenTexts, ["错误 404"])
    }

    func testSpeakSummaryTextUsesSummaryWhenAvailable() {
        let recorder = ScreenshotOCRRecorder(recognizedText: "Error 404")
        let result = ScreenshotOCRResult(
            originalText: "Error 404",
            originalImage: ScreenshotOCRTestImage.make(),
            translatedText: "错误 404",
            summaryText: "检查 URL。"
        )

        recorder.service.speak(.summary, from: result)

        XCTAssertEqual(recorder.speech.spokenTexts, ["检查 URL。"])
    }

    func testStopSpeakingDelegatesToSpeechService() {
        let recorder = ScreenshotOCRRecorder(recognizedText: "Error 404")

        recorder.service.stopSpeaking()

        XCTAssertEqual(recorder.speech.stopCount, 1)
    }

    func testSystemSpeechServiceUsesLocalTTSAudioWhenAvailable() async {
        let localTTS = StubLocalTTSSynthesizer(audio: ScreenshotTTSAudio(samples: [0, 0], sampleRate: 24_000))
        let audioPlayer = CapturingScreenshotAudioPlayer()
        let service = SystemScreenshotSpeechService(
            localSynthesizer: localTTS,
            audioPlayer: audioPlayer,
            systemSpeaker: CapturingSystemSpeechSpeaker()
        )

        service.speak("你好")
        await drainMainActorTasks()

        let requestedTexts = await localTTS.requests()
        XCTAssertEqual(requestedTexts, ["你好"])
        XCTAssertEqual(audioPlayer.playedAudio, [ScreenshotTTSAudio(samples: [0, 0], sampleRate: 24_000)])
    }

    func testSystemSpeechServiceFallsBackToAppleSpeechWhenLocalTTSIsUnavailable() async {
        let localTTS = StubLocalTTSSynthesizer(audio: nil)
        let systemSpeaker = CapturingSystemSpeechSpeaker()
        let service = SystemScreenshotSpeechService(
            localSynthesizer: localTTS,
            audioPlayer: CapturingScreenshotAudioPlayer(),
            systemSpeaker: systemSpeaker
        )

        service.speak("Error 404")
        await drainMainActorTasks()

        XCTAssertEqual(systemSpeaker.spokenTexts, ["Error 404"])
    }

    func testSystemSpeechServiceDoesNotMuteOutputForScreenshotReading() async {
        let systemSpeaker = CapturingSystemSpeechSpeaker()
        var mutedStates: [Bool] = []
        let service = SystemScreenshotSpeechService(
            localSynthesizer: nil,
            audioPlayer: CapturingScreenshotAudioPlayer(),
            systemSpeaker: systemSpeaker,
            setSystemOutputMuted: { mutedStates.append($0) }
        )

        service.speak("Error 404")
        await drainMainActorTasks()
        systemSpeaker.finishSpeech()

        XCTAssertEqual(systemSpeaker.spokenTexts, ["Error 404"])
        XCTAssertEqual(mutedStates, [])
    }

    func testSystemSpeechServiceStopDoesNotTouchOutputMuteForScreenshotReading() async {
        let systemSpeaker = CapturingSystemSpeechSpeaker()
        var mutedStates: [Bool] = []
        let service = SystemScreenshotSpeechService(
            localSynthesizer: nil,
            audioPlayer: CapturingScreenshotAudioPlayer(),
            systemSpeaker: systemSpeaker,
            setSystemOutputMuted: { mutedStates.append($0) }
        )

        service.speak("Error 404")
        await drainMainActorTasks()
        service.stop()

        XCTAssertEqual(mutedStates, [])
    }

    func testSystemSpeechServiceDoesNotPlaySynthesizedAudioAfterStop() async {
        let localTTS = SuspendingLocalTTSSynthesizer()
        let audioPlayer = CapturingScreenshotAudioPlayer()
        let systemSpeaker = CapturingSystemSpeechSpeaker()
        let service = SystemScreenshotSpeechService(
            localSynthesizer: localTTS,
            audioPlayer: audioPlayer,
            systemSpeaker: systemSpeaker
        )

        service.speak("你好")
        await drainMainActorTasks()
        service.stop()
        await localTTS.finish(with: ScreenshotTTSAudio(samples: [0, 0], sampleRate: 24_000))
        await drainMainActorTasks()

        XCTAssertEqual(audioPlayer.playedAudio, [])
        XCTAssertEqual(systemSpeaker.spokenTexts, [])
    }

    func testSystemSpeechServiceFinishesWhenLocalAudioPlayerThrows() async {
        let localTTS = StubLocalTTSSynthesizer(audio: ScreenshotTTSAudio(samples: [0, 0], sampleRate: 24_000))
        let audioPlayer = ThrowingScreenshotAudioPlayer()
        let systemSpeaker = CapturingSystemSpeechSpeaker()
        var completionCount = 0
        let service = SystemScreenshotSpeechService(
            localSynthesizer: localTTS,
            audioPlayer: audioPlayer,
            systemSpeaker: systemSpeaker
        )

        service.speak("你好") {
            completionCount += 1
        }
        await drainMainActorTasks()
        systemSpeaker.finishSpeech()

        XCTAssertEqual(audioPlayer.playCount, 1)
        XCTAssertEqual(systemSpeaker.spokenTexts, ["你好"])
        XCTAssertEqual(completionCount, 1)
    }
}

@MainActor
private final class ScreenshotOCRRecorder {
    let imageProvider: StubScreenshotImageProvider
    let ocr: StubScreenshotOCRRecognizer
    let translator: StubScreenshotTranslator
    let speech: CapturingSpeechService
    let clipboard: CapturingScreenshotImageClipboard
    let store: InMemoryLastResultStore
    let service: ScreenshotOCRService

    init(
        recognizedText: String,
        translatedText: String = "translated text",
        lastResult: String? = nil,
        translatorConfigured: Bool = true,
        translationConfigured: Bool? = nil,
        summaryConfigured: Bool? = nil,
        isCancelled: @escaping @MainActor () -> Bool = { Task.isCancelled }
    ) {
        imageProvider = StubScreenshotImageProvider(image: ScreenshotOCRTestImage.make())
        ocr = StubScreenshotOCRRecognizer(text: recognizedText)
        translator = StubScreenshotTranslator(
            text: translatedText,
            configured: translatorConfigured,
            translationConfigured: translationConfigured ?? translatorConfigured,
            summaryConfigured: summaryConfigured ?? translatorConfigured
        )
        speech = CapturingSpeechService()
        clipboard = CapturingScreenshotImageClipboard()
        store = InMemoryLastResultStore()
        store.setLastResultText(lastResult)
        service = ScreenshotOCRService(
            imageProvider: imageProvider,
            ocrRecognizer: ocr,
            translator: translator,
            speechService: speech,
            clipboard: clipboard,
            lastResultStore: store,
            isCancelled: isCancelled
        )
    }
}

@MainActor
private final class StubScreenshotImageProvider: ScreenshotImageProviding {
    let image: CGImage
    var error: Error?
    private(set) var captureCount = 0

    init(image: CGImage) {
        self.image = image
    }

    func captureImage() async throws -> CGImage {
        captureCount += 1
        if let error {
            throw error
        }
        return image
    }
}

@MainActor
private final class StubScreenshotOCRRecognizer: TextOCRRecognizing, @unchecked Sendable {
    private let text: String
    private(set) var requestCount = 0

    init(text: String) {
        self.text = text
    }

    func recognizeText(in image: CGImage) async throws -> String {
        requestCount += 1
        return text
    }
}

private final class StubScreenshotTranslator: PromptAwareTextRefining, ScreenshotTextRefiningCapabilities, @unchecked Sendable {
    var isEnabled = true
    var isConfigured: Bool
    var isTranslationConfigured: Bool
    var isSummaryConfigured: Bool
    let text: String
    private(set) var requests: [TextRefinementRequest] = []

    init(
        text: String,
        configured: Bool,
        translationConfigured: Bool,
        summaryConfigured: Bool
    ) {
        self.text = text
        self.isConfigured = configured
        self.isTranslationConfigured = translationConfigured
        self.isSummaryConfigured = summaryConfigured
    }

    func refine(_ text: String) async throws -> String {
        self.text
    }

    func refine(_ request: TextRefinementRequest) async throws -> String {
        requests.append(request)
        return text
    }
}

@MainActor
private final class CapturingSpeechService: ScreenshotSpeechSpeaking {
    private(set) var spokenTexts: [String] = []
    private(set) var stopCount = 0

    func speak(_ text: String, completion: ScreenshotSpeechCompletion?) {
        spokenTexts.append(text)
        completion?()
    }

    func stop() {
        stopCount += 1
    }
}

@MainActor
private final class ThrowingScreenshotAudioPlayer: ScreenshotAudioPlaying {
    private(set) var playCount = 0

    func play(_ audio: ScreenshotTTSAudio, completion: @escaping ScreenshotSpeechCompletion) throws {
        playCount += 1
        throw ScreenshotAudioPlaybackError.invalidBuffer
    }

    func stop() {}
}

private actor StubLocalTTSSynthesizer: ScreenshotLocalTTSSynthesizing {
    private let audio: ScreenshotTTSAudio?
    private(set) var requestedTexts: [String] = []

    init(audio: ScreenshotTTSAudio?) {
        self.audio = audio
    }

    func synthesizeIfAvailable(text: String) async throws -> ScreenshotTTSAudio? {
        requestedTexts.append(text)
        return audio
    }

    func requests() -> [String] {
        requestedTexts
    }
}

private actor SuspendingLocalTTSSynthesizer: ScreenshotLocalTTSSynthesizing {
    private var continuation: CheckedContinuation<ScreenshotTTSAudio?, Never>?

    func synthesizeIfAvailable(text: String) async throws -> ScreenshotTTSAudio? {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func finish(with audio: ScreenshotTTSAudio?) {
        continuation?.resume(returning: audio)
        continuation = nil
    }
}

@MainActor
private final class CapturingScreenshotAudioPlayer: ScreenshotAudioPlaying {
    private(set) var playedAudio: [ScreenshotTTSAudio] = []
    private(set) var stopCount = 0
    private var completion: ScreenshotSpeechCompletion?

    func play(_ audio: ScreenshotTTSAudio, completion: @escaping ScreenshotSpeechCompletion) throws {
        playedAudio.append(audio)
        self.completion = completion
    }

    func finishPlayback() {
        completion?()
        completion = nil
    }

    func stop() {
        stopCount += 1
        completion = nil
    }
}

@MainActor
private final class CapturingSystemSpeechSpeaker: ScreenshotSystemSpeechSpeaking {
    private(set) var spokenTexts: [String] = []
    private(set) var stopCount = 0
    private var completion: ScreenshotSpeechCompletion?

    func speak(_ text: String, completion: @escaping ScreenshotSpeechCompletion) {
        spokenTexts.append(text)
        self.completion = completion
    }

    func finishSpeech() {
        completion?()
        completion = nil
    }

    func stop() {
        stopCount += 1
        completion = nil
    }
}

@MainActor
private final class CapturingScreenshotImageClipboard: ScreenshotImageClipboardWriting {
    private(set) var copiedImageWidths: [Int] = []

    func setImage(_ image: CGImage) -> Bool {
        copiedImageWidths.append(image.width)
        return true
    }
}

private enum ScreenshotOCRTestImage {
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

private func drainMainActorTasks() async {
    for _ in 0..<10 {
        await Task.yield()
    }
    try? await Task.sleep(nanoseconds: 10_000_000)
}
