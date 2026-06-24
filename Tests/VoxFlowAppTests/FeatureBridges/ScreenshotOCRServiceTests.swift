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

    func testCaptureAndRecognizeWritesScreenshotAssetWithOCRText() async {
        let assets = CapturingScreenshotAssetRepository()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScreenshotOCRServiceTests-\(UUID().uuidString)", isDirectory: true)
        let recorder = ScreenshotOCRRecorder(
            recognizedText: "  Error 404 - Page Not Found  ",
            assetRepository: assets,
            assetImageDirectory: directory
        )

        _ = await recorder.service.captureAndRecognize()

        XCTAssertEqual(assets.savedItems.count, 1)
        let asset = try! XCTUnwrap(assets.savedItems.first)
        XCTAssertEqual(asset.source, .screenshot)
        XCTAssertEqual(asset.contentType, .image)
        XCTAssertEqual(asset.title, "Image (1x1)")
        XCTAssertEqual(asset.text, "Error 404 - Page Not Found")
        XCTAssertEqual(asset.captureReason, .screenshotCaptured)
        XCTAssertNotNil(asset.imagePath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: asset.imagePath ?? ""))
    }

    func testCaptureAndRecognizePreservesTextRecognitionCompletionKind() async {
        let recorder = ScreenshotOCRRecorder(
            recognizedText: "  Error 404 - Page Not Found  ",
            captureCompletionKind: .textRecognition
        )

        let outcome = await recorder.service.captureAndRecognize()

        XCTAssertEqual(
            outcome,
            .recognized(
                ScreenshotOCRResult(
                    originalText: "Error 404 - Page Not Found",
                    originalImage: recorder.imageProvider.image,
                    captureCompletionKind: .textRecognition
                )
            )
        )
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

    func testTranslationEventsUseStreamingRefinerAndStoreCompletedText() async {
        let recorder = ScreenshotOCRRecorder(
            recognizedText: "Error 404",
            translatedText: "unused"
        )
        recorder.translator.streamSnapshots = ["错误", "错误 404"]

        let events = await collectTextTransformEvents(
            recorder.service.translationEvents(
                for: ScreenshotOCRResult(originalText: "Error 404")
            )
        )

        XCTAssertEqual(events, [
            .started(totalUnits: nil),
            .partialText("错误"),
            .partialText("错误 404"),
            .completed("错误 404"),
        ])
        XCTAssertEqual(recorder.translator.requests.map(\.text), ["Error 404"])
        XCTAssertTrue(recorder.translator.requests[0].systemPrompt.contains("截图文字翻译助手"))
        XCTAssertEqual(recorder.store.lastResultText, "错误 404")
    }

    func testSummaryEventsUseStreamingRefinerAndStoreCompletedText() async {
        let recorder = ScreenshotOCRRecorder(
            recognizedText: "Error 404",
            translatedText: "unused"
        )
        recorder.translator.streamSnapshots = ["- 错误", "- 错误 404"]

        let events = await collectTextTransformEvents(
            recorder.service.summaryEvents(
                for: ScreenshotOCRResult(originalText: "Error 404")
            )
        )

        XCTAssertEqual(events, [
            .started(totalUnits: nil),
            .partialText("- 错误"),
            .partialText("- 错误 404"),
            .completed("- 错误 404"),
        ])
        XCTAssertEqual(recorder.translator.requests.map(\.text), ["Error 404"])
        XCTAssertTrue(recorder.translator.requests[0].systemPrompt.contains("截图文字总结助手"))
        XCTAssertEqual(recorder.store.lastResultText, "- 错误 404")
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

    func testInlineSelectionTranslatorBuildsTranslatedOverlayFromOCRLines() async throws {
        let recorder = ScreenshotOCRRecorder(
            recognizedText: "Name\nAge",
            translatedText: """
            [{"index":0,"translated":"姓名"},{"index":1,"translated":"年龄"}]
            """
        )
        let translator = ScreenshotInlineSelectionTranslator(
            ocrRecognizer: recorder.ocr,
            translator: recorder.translator,
            lastResultStore: recorder.store
        )

        let overlay = try await translator.translatedOverlay(for: recorder.imageProvider.image)

        XCTAssertEqual(overlay.lines.map(\.text), ["姓名", "年龄"])
        XCTAssertEqual(overlay.lines.map(\.bounds), [
            CGRect(x: 0, y: 0, width: 1, height: 20),
            CGRect(x: 0, y: 20, width: 1, height: 20),
        ])
        XCTAssertEqual(recorder.store.lastResultText, "Name\nAge")
    }

    func testInlineSelectionTranslatorSkipsJSONModeWhenTranslatorDoesNotSupportStructuredLines() async throws {
        let recorder = ScreenshotOCRRecorder(
            recognizedText: "Name\nAge",
            translatedText: "unused"
        )
        recorder.translator.supportsStructuredLineTranslation = false
        recorder.translator.responsesByText = [
            "Name": "姓名",
            "Age": "年龄",
        ]
        let translator = ScreenshotInlineSelectionTranslator(
            ocrRecognizer: recorder.ocr,
            translator: recorder.translator,
            lastResultStore: recorder.store
        )

        let overlay = try await translator.translatedOverlay(for: recorder.imageProvider.image)

        XCTAssertEqual(overlay.lines.map(\.text), ["姓名", "年龄"])
        XCTAssertEqual(recorder.translator.requests.map(\.text), ["Name", "Age"])
        XCTAssertTrue(recorder.translator.requests[0].systemPrompt.contains("截图文字翻译助手"))
    }

    func testInlineSelectionTranslatorReportsLineTranslationProgress() async throws {
        let recorder = ScreenshotOCRRecorder(
            recognizedText: "Name\nAge",
            translatedText: "unused"
        )
        recorder.translator.supportsStructuredLineTranslation = false
        recorder.translator.responsesByText = [
            "Name": "姓名",
            "Age": "年龄",
        ]
        var events: [LineTransformEvent] = []
        let translator = ScreenshotInlineSelectionTranslator(
            ocrRecognizer: recorder.ocr,
            translator: recorder.translator,
            lastResultStore: recorder.store,
            onLineTranslationEvent: { event in
                events.append(event)
            }
        )

        _ = try await translator.translatedOverlay(for: recorder.imageProvider.image)

        XCTAssertEqual(events, [
            LineTransformEvent(completedLines: [0: "姓名"], totalLineCount: 2, isFinal: false),
            LineTransformEvent(completedLines: [0: "姓名", 1: "年龄"], totalLineCount: 2, isFinal: true),
        ])
    }

    func testLineTranslationEventsEmitProgressForIndividualFallback() async {
        let recorder = ScreenshotOCRRecorder(
            recognizedText: "Name\nAge",
            translatedText: "unused"
        )
        recorder.translator.supportsStructuredLineTranslation = false
        recorder.translator.responsesByText = [
            "Name": "姓名",
            "Age": "年龄",
        ]
        let lines = [
            OCRLine(text: "Name", boundingBox: CGRect(x: 0, y: 0, width: 1, height: 20)),
            OCRLine(text: "Age", boundingBox: CGRect(x: 0, y: 20, width: 1, height: 20)),
        ]

        let events = await collectLineTransformEvents(
            ScreenshotOCRService.lineTranslationEvents(lines, translator: recorder.translator)
        )

        XCTAssertEqual(events, [
            LineTransformEvent(completedLines: [0: "姓名"], totalLineCount: 2, isFinal: false),
            LineTransformEvent(completedLines: [0: "姓名", 1: "年龄"], totalLineCount: 2, isFinal: true),
        ])
    }

    func testLineTranslationEventsEmitBatchProgressForStructuredTranslation() async {
        let recorder = ScreenshotOCRRecorder(
            recognizedText: (0..<12).map { "Line \($0)" }.joined(separator: "\n"),
            translatedText: "unused"
        )
        let lines = (0..<12).map { index in
            OCRLine(
                text: "Line \(index)",
                boundingBox: CGRect(x: 0, y: CGFloat(index) * 20, width: 1, height: 20)
            )
        }
        let firstBatchRequest = lineTranslationRequestJSON(for: 0..<8)
        let secondBatchRequest = lineTranslationRequestJSON(for: 8..<12)
        recorder.translator.responsesByText = [
            firstBatchRequest: lineTranslationResponseJSON(for: 0..<8),
            secondBatchRequest: lineTranslationResponseJSON(for: 8..<12),
        ]

        let events = await collectLineTransformEvents(
            ScreenshotOCRService.lineTranslationEvents(lines, translator: recorder.translator)
        )

        XCTAssertEqual(events, [
            LineTransformEvent(
                completedLines: Dictionary(uniqueKeysWithValues: (0..<8).map { ($0, "译文 \($0)") }),
                totalLineCount: 12,
                isFinal: false
            ),
            LineTransformEvent(
                completedLines: Dictionary(uniqueKeysWithValues: (0..<12).map { ($0, "译文 \($0)") }),
                totalLineCount: 12,
                isFinal: true
            ),
        ])
        XCTAssertEqual(recorder.translator.requests.map(\.text), [
            firstBatchRequest,
            secondBatchRequest,
        ])
    }

    func testInlineSelectionTranslatorFallsBackToIndividualLinesWhenStructuredResponseIsInvalid() async throws {
        let recorder = ScreenshotOCRRecorder(
            recognizedText: "Address\nNew York No. 1 Lake Park\nLondon No. 1 Lake Park\nSydney No. 1 Lake Park",
            translatedText: "not json"
        )
        recorder.translator.responsesByText = [
            "Address": "地址",
            "New York No. 1 Lake Park": "纽约一号湖公园",
            "London No. 1 Lake Park": "伦敦一号湖公园",
            "Sydney No. 1 Lake Park": "悉尼一号湖公园",
        ]
        let translator = ScreenshotInlineSelectionTranslator(
            ocrRecognizer: recorder.ocr,
            translator: recorder.translator,
            lastResultStore: recorder.store
        )

        let overlay = try await translator.translatedOverlay(for: recorder.imageProvider.image)

        XCTAssertEqual(overlay.lines.map(\.text), [
            "地址",
            "纽约一号湖公园",
            "伦敦一号湖公园",
            "悉尼一号湖公园",
        ])
        XCTAssertEqual(overlay.lines.map(\.bounds.origin.y), [0, 20, 40, 60])
        XCTAssertEqual(recorder.translator.requests.map(\.text), [
            """
            [{"index":0,"text":"Address"},{"index":1,"text":"New York No. 1 Lake Park"},{"index":2,"text":"London No. 1 Lake Park"},{"index":3,"text":"Sydney No. 1 Lake Park"}]
            """,
            "Address",
            "New York No. 1 Lake Park",
            "London No. 1 Lake Park",
            "Sydney No. 1 Lake Park",
        ])
    }

    func testInlineSelectionTranslatorFallsBackWhenStructuredResponseHasDuplicateIndexes() async throws {
        let recorder = ScreenshotOCRRecorder(
            recognizedText: "Name\nAge",
            translatedText: """
            [{"index":0,"translated":"姓名"},{"index":0,"translated":"年龄"}]
            """
        )
        recorder.translator.responsesByText = [
            "Name": "姓名",
            "Age": "年龄",
        ]
        let translator = ScreenshotInlineSelectionTranslator(
            ocrRecognizer: recorder.ocr,
            translator: recorder.translator,
            lastResultStore: recorder.store
        )

        let overlay = try await translator.translatedOverlay(for: recorder.imageProvider.image)

        XCTAssertEqual(overlay.lines.map(\.text), ["姓名", "年龄"])
        XCTAssertEqual(recorder.translator.requests.map(\.text), [
            """
            [{"index":0,"text":"Name"},{"index":1,"text":"Age"}]
            """,
            "Name",
            "Age",
        ])
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

    func testSummarizeFallsBackWhenLLMIsDisabled() async {
        let recorder = ScreenshotOCRRecorder(
            recognizedText: "Error 404",
            translatedText: "页面不存在，请检查 URL。",
            translatorConfigured: true,
            summaryConfigured: true
        )
        recorder.translator.isEnabled = false
        let original = ScreenshotOCRResult(originalText: "Error 404")

        let outcome = await recorder.service.summarize(original)

        XCTAssertEqual(outcome, .summaryUnavailable(original))
        XCTAssertTrue(recorder.translator.requests.isEmpty)
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

    func testAVAudioPlayerReconnectsToPlaybackSampleRate() {
        let player = AVAudioScreenshotPlayer()

        player.reconnectForPlayback(sampleRate: 16_000)

        XCTAssertEqual(player.connectedSampleRate, 16_000)
    }
}

private func collectTextTransformEvents(_ stream: AsyncStream<TextTransformEvent>) async -> [TextTransformEvent] {
    var events: [TextTransformEvent] = []
    for await event in stream {
        events.append(event)
    }
    return events
}

private func collectLineTransformEvents(_ stream: AsyncStream<LineTransformEvent>) async -> [LineTransformEvent] {
    var events: [LineTransformEvent] = []
    for await event in stream {
        events.append(event)
    }
    return events
}

private func lineTranslationRequestJSON(for indexes: Range<Int>) -> String {
    let items = indexes.map { index in
        "{\"index\":\(index),\"text\":\"Line \(index)\"}"
    }.joined(separator: ",")
    return "[\(items)]"
}

private func lineTranslationResponseJSON(for indexes: Range<Int>) -> String {
    let items = indexes.map { index in
        "{\"index\":\(index),\"translated\":\"译文 \(index)\"}"
    }.joined(separator: ",")
    return "[\(items)]"
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
        captureCompletionKind: ScreenshotCaptureCompletionKind = .complete,
        assetRepository: (any AssetRepository)? = nil,
        assetImageDirectory: URL? = nil,
        isCancelled: @escaping @MainActor () -> Bool = { Task.isCancelled }
    ) {
        imageProvider = StubScreenshotImageProvider(
            image: ScreenshotOCRTestImage.make(),
            completionKind: captureCompletionKind
        )
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
            assetRepository: assetRepository,
            assetImageDirectory: assetImageDirectory,
            isCancelled: isCancelled
        )
    }
}

@MainActor
private final class StubScreenshotImageProvider: ScreenshotImageProviding {
    let image: CGImage
    let completionKind: ScreenshotCaptureCompletionKind
    var error: Error?
    private(set) var captureCount = 0

    init(image: CGImage, completionKind: ScreenshotCaptureCompletionKind = .complete) {
        self.image = image
        self.completionKind = completionKind
    }

    func captureImage() async throws -> CGImage {
        try await capture().image
    }

    func capture() async throws -> ScreenshotImageCaptureResult {
        captureCount += 1
        if let error {
            throw error
        }
        return ScreenshotImageCaptureResult(image: image, completionKind: completionKind)
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

    func recognizeTextLines(in image: CGImage) async throws -> [OCRLine] {
        requestCount += 1
        return text
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

private final class StubScreenshotTranslator: StreamingPromptAwareTextRefining, ScreenshotTextRefiningCapabilities, StructuredLineTranslationSupporting, @unchecked Sendable {
    var isEnabled = true
    var isConfigured: Bool
    var isTranslationConfigured: Bool
    var isSummaryConfigured: Bool
    var supportsStructuredLineTranslation = true
    var responsesByText: [String: String] = [:]
    var streamSnapshots: [String]?
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
        return responsesByText[request.text] ?? text
    }

    func refineStream(_ request: TextRefinementRequest) -> AsyncThrowingStream<String, Error> {
        requests.append(request)
        let snapshots = streamSnapshots ?? [responsesByText[request.text] ?? text]
        return AsyncThrowingStream { continuation in
            for snapshot in snapshots {
                continuation.yield(snapshot)
            }
            continuation.finish()
        }
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

private final class CapturingScreenshotAssetRepository: AssetRepository {
    private(set) var savedItems: [AssetItem] = []

    func save(_ item: AssetItem) throws {
        savedItems.removeAll { $0.id == item.id }
        savedItems.append(item)
    }

    func asset(id: String) throws -> AssetItem? {
        savedItems.first { $0.id == id && $0.deletedAt == nil }
    }

    func page(query: AssetQuery) throws -> AssetPage {
        AssetPage(items: savedItems, totalCount: savedItems.count)
    }

    func softDelete(id: String, deletedAt: Date) throws {}
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
