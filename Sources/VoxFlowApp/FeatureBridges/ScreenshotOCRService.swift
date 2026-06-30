import AppKit
import AVFoundation
import CoreGraphics
@preconcurrency import CosyVoiceTTS
import Foundation
@preconcurrency import KokoroTTS
@preconcurrency import Qwen3TTS
import VoxFlowPromptKit
import VoxFlowScreenshotKit

struct ScreenshotOCRResult: Equatable {
    let originalText: String
    let originalImage: CGImage?
    let ocrStatusMessage: String?
    let captureCompletionKind: ScreenshotCaptureCompletionKind
    var translatedText: String?
    var summaryText: String?

    init(
        originalText: String,
        originalImage: CGImage? = nil,
        ocrStatusMessage: String? = nil,
        captureCompletionKind: ScreenshotCaptureCompletionKind = .complete,
        translatedText: String? = nil,
        summaryText: String? = nil
    ) {
        self.originalText = originalText
        self.originalImage = originalImage
        self.ocrStatusMessage = ocrStatusMessage
        self.captureCompletionKind = captureCompletionKind
        self.translatedText = translatedText
        self.summaryText = summaryText
    }

    static func == (lhs: ScreenshotOCRResult, rhs: ScreenshotOCRResult) -> Bool {
        lhs.originalText == rhs.originalText &&
            lhs.ocrStatusMessage == rhs.ocrStatusMessage &&
            lhs.captureCompletionKind == rhs.captureCompletionKind &&
            lhs.translatedText == rhs.translatedText &&
            lhs.summaryText == rhs.summaryText &&
            lhs.originalImage?.width == rhs.originalImage?.width &&
            lhs.originalImage?.height == rhs.originalImage?.height
    }
}

enum ScreenshotOCRServiceOutcome: Equatable {
    case recognized(ScreenshotOCRResult)
    case translated(ScreenshotOCRResult)
    case summarized(ScreenshotOCRResult)
    case translationUnavailable(ScreenshotOCRResult)
    case summaryUnavailable(ScreenshotOCRResult)
    case captureCancelled
    case captureFailed(String)
    case ocrFailed(String)
    case translationFailed(ScreenshotOCRResult, String)
    case summaryFailed(ScreenshotOCRResult, String)
    case translatedOverlay(originalResult: ScreenshotOCRResult, overlayImage: TranslatedOverlayImage)
}

/// 译文覆盖图：原图 + 译文按行覆盖后的结果。Equatable 只比 width/height，跟 ScreenshotOCRResult 一致。
struct TranslatedOverlayImage: Equatable {
    let image: CGImage

    static func == (lhs: TranslatedOverlayImage, rhs: TranslatedOverlayImage) -> Bool {
        lhs.image.width == rhs.image.width && lhs.image.height == rhs.image.height
    }
}

enum ScreenshotOCRServiceError: LocalizedError, Equatable {
    case captureCancelled
    case captureFailed(String)

    var errorDescription: String? {
        switch self {
        case .captureCancelled:
            return L10n.localize("screenshot.capture.error.cancelled", comment: "")
        case .captureFailed(let reason):
            return reason
        }
    }
}

enum ScreenshotCaptureCompletionKind: Equatable {
    case complete
    case scrollingScreenshot
    case textRecognition
    case translate
}

struct ScreenshotImageCaptureResult: Equatable {
    let image: CGImage
    let completionKind: ScreenshotCaptureCompletionKind

    init(
        image: CGImage,
        completionKind: ScreenshotCaptureCompletionKind = .complete
    ) {
        self.image = image
        self.completionKind = completionKind
    }

    static func == (
        lhs: ScreenshotImageCaptureResult,
        rhs: ScreenshotImageCaptureResult
    ) -> Bool {
        lhs.image.width == rhs.image.width &&
            lhs.image.height == rhs.image.height &&
            lhs.completionKind == rhs.completionKind
    }
}

enum ScreenshotAudioPlaybackError: LocalizedError, Equatable {
    case invalidBuffer

    var errorDescription: String? {
        switch self {
        case .invalidBuffer:
            return L10n.localize(
                "screenshot.audio.error.create_buffer_failed",
                comment: ""
            )
        }
    }
}

enum ScreenshotOCRSpeechTarget {
    case original
    case translated
    case summary
}

@MainActor
protocol ScreenshotImageProviding: AnyObject {
    func captureImage() async throws -> CGImage
    func capture() async throws -> ScreenshotImageCaptureResult
}

extension ScreenshotImageProviding {
    func capture() async throws -> ScreenshotImageCaptureResult {
        let image = try await captureImage()
        return ScreenshotImageCaptureResult(image: image)
    }
}

@MainActor
protocol ScreenshotSpeechSpeaking: AnyObject {
    func speak(_ text: String, completion: ScreenshotSpeechCompletion?)
    func stop()
}

extension ScreenshotSpeechSpeaking {
    func speak(_ text: String) {
        speak(text, completion: nil)
    }
}

struct ScreenshotTTSAudio: Equatable, Sendable {
    let samples: [Float]
    let sampleRate: Double
}

protocol ScreenshotLocalTTSSynthesizing: Sendable {
    func synthesizeIfAvailable(text: String) async throws -> ScreenshotTTSAudio?
}

typealias ScreenshotSpeechCompletion = @MainActor @Sendable () -> Void

@MainActor
protocol ScreenshotAudioPlaying: AnyObject {
    func play(_ audio: ScreenshotTTSAudio, completion: @escaping ScreenshotSpeechCompletion) throws
    func stop()
}

@MainActor
protocol ScreenshotSystemSpeechSpeaking: AnyObject {
    func speak(_ text: String, completion: @escaping ScreenshotSpeechCompletion)
    func stop()
}

@MainActor
final class ScreenshotOCRService {
    private let imageProvider: any ScreenshotImageProviding
    private let ocrRecognizer: any TextOCRRecognizing
    private let translator: (any PromptAwareTextRefining)?
    private let speechService: any ScreenshotSpeechSpeaking
    private let clipboard: any ScreenshotImageClipboardWriting
    private let lastResultStore: any LastResultStoring
    private let assetRepository: (any AssetRepository)?
    private let assetImageDirectory: URL?
    private let isCancelled: @MainActor () -> Bool

    init(
        imageProvider: any ScreenshotImageProviding,
        ocrRecognizer: any TextOCRRecognizing,
        translator: (any PromptAwareTextRefining)?,
        speechService: any ScreenshotSpeechSpeaking,
        clipboard: any ScreenshotImageClipboardWriting,
        lastResultStore: any LastResultStoring,
        assetRepository: (any AssetRepository)? = nil,
        assetImageDirectory: URL? = nil,
        isCancelled: @escaping @MainActor () -> Bool = { Task.isCancelled }
    ) {
        self.imageProvider = imageProvider
        self.ocrRecognizer = ocrRecognizer
        self.translator = translator
        self.speechService = speechService
        self.clipboard = clipboard
        self.lastResultStore = lastResultStore
        self.assetRepository = assetRepository
        self.assetImageDirectory = assetImageDirectory
        self.isCancelled = isCancelled
    }

    func captureAndRecognize() async -> ScreenshotOCRServiceOutcome {
        guard !isCancelled() else { return .captureCancelled }
        let capture: ScreenshotImageCaptureResult
        do {
            capture = try await imageProvider.capture()
            AppLogger.general.debug("Screenshot capture completed kind=\(capture.completionKind) size=\(capture.image.width)x\(capture.image.height)")
        } catch ScreenshotOCRServiceError.captureCancelled {
            AppLogger.general.info("Screenshot capture cancelled by user")
            return .captureCancelled
        } catch ScreenshotOCRServiceError.captureFailed(let reason) {
            AppLogger.general.warning("Screenshot capture failed: \(reason)")
            return .captureFailed(reason)
        } catch {
            AppLogger.general.warning("Screenshot capture unknown error: \(error.localizedDescription)")
            return .captureFailed(error.localizedDescription)
        }

        guard !isCancelled() else { return .captureCancelled }
        let image = capture.image
        AppLogger.general.debug("Screenshot capture image copied to clipboard for recognize")
        clipboard.setImage(image)

        // 兼容旧截图翻译完成模式；新工具栏翻译优先在选区内原位完成。
        if capture.completionKind == .translate {
            AppLogger.general.info("Screenshot completion mode translate, starting translate flow")
            return await translateCaptured(image: image)
        }

        do {
            let text = try await ocrRecognizer
                .recognizeText(in: image)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            AppLogger.general.debug("Screenshot OCR completed. textLength=\(text.count), cancelled=\(isCancelled())")
            guard !isCancelled() else { return .captureCancelled }
            guard !text.isEmpty else {
                AppLogger.general.warning("Screenshot OCR returned empty text")
                saveScreenshotAsset(image: image, ocrText: nil)
                return .recognized(
                    ScreenshotOCRResult(
                        originalText: "",
                        originalImage: image,
                        ocrStatusMessage: L10n.localize(
                            "screenshot.ocr.no_text_for_screenshot",
                            comment: ""
                        ),
                        captureCompletionKind: capture.completionKind
                    )
                )
            }
            lastResultStore.setLastResultText(text)
            saveScreenshotAsset(image: image, ocrText: text)
            AppLogger.general.debug("Screenshot OCR result saved to last result cache")
            return .recognized(
                ScreenshotOCRResult(
                    originalText: text,
                    originalImage: image,
                    captureCompletionKind: capture.completionKind
                )
            )
        } catch {
            AppLogger.general.warning("Screenshot OCR failed: \(error.localizedDescription)")
            saveScreenshotAsset(image: image, ocrText: nil)
            return .ocrFailed(error.localizedDescription)
        }
    }

    /// 微信截图式一键翻译：OCR（保留每行 bbox）→ 按行翻译 → 译文覆盖原图。
    /// 返回 .translatedOverlay(originalResult, overlayImage)。
    func captureAndTranslate() async -> ScreenshotOCRServiceOutcome {
        guard !isCancelled() else { return .captureCancelled }
        let capture: ScreenshotImageCaptureResult
        do {
            capture = try await imageProvider.capture()
            AppLogger.general.debug("Screenshot translate capture completed kind=\(capture.completionKind) size=\(capture.image.width)x\(capture.image.height)")
        } catch ScreenshotOCRServiceError.captureCancelled {
            AppLogger.general.info("Screenshot translate capture cancelled by user")
            return .captureCancelled
        } catch ScreenshotOCRServiceError.captureFailed(let reason) {
            AppLogger.general.warning("Screenshot translate capture failed: \(reason)")
            return .captureFailed(reason)
        } catch {
            AppLogger.general.warning("Screenshot translate capture error: \(error.localizedDescription)")
            return .captureFailed(error.localizedDescription)
        }

        guard !isCancelled() else { return .captureCancelled }
        clipboard.setImage(capture.image)
        AppLogger.general.debug("Screenshot translate capture image copied to clipboard")
        return await translateCaptured(image: capture.image)
    }

    /// 对已捕获的图片做 OCR + 翻译 + 覆盖渲染。供 captureAndRecognize 在 completionKind == .translate 时复用。
    private func translateCaptured(image: CGImage) async -> ScreenshotOCRServiceOutcome {
        // 1. OCR 保留每行 bbox
        let ocrLines: [OCRLine]
        do {
            ocrLines = try await ocrRecognizer.recognizeTextLines(in: image)
            AppLogger.general.debug("Screenshot line OCR completed lines=\(ocrLines.count)")
            guard !isCancelled() else { return .captureCancelled }
        } catch {
            AppLogger.general.warning("Screenshot line OCR failed: \(error.localizedDescription)")
            return .ocrFailed(error.localizedDescription)
        }

        guard !ocrLines.isEmpty else {
            AppLogger.general.warning("Screenshot line OCR returned empty lines")
            let original = ScreenshotOCRResult(
                originalText: "",
                originalImage: image,
                ocrStatusMessage: L10n.localize(
                    "screenshot.ocr.no_text_for_screenshot",
                    comment: ""
                ),
                captureCompletionKind: .translate
            )
            return .recognized(original)
        }

        let originalText = ocrLines.map(\.text).joined(separator: "\n")
        lastResultStore.setLastResultText(originalText)

        let originalResult = ScreenshotOCRResult(
            originalText: originalText,
            originalImage: image,
            captureCompletionKind: .translate
        )

        // 2. 翻译（需要 translator 配置好）
        guard let translator,
              translator.isEnabled,
              Self.translationIsConfigured(translator) else {
            AppLogger.general.warning("Screenshot translation unavailable: missing translator")
            return .translationUnavailable(originalResult)
        }

        AppLogger.general.info("Screenshot translate flow using translator: \(type(of: translator))")
        let translatedLines = await Self.translateLines(ocrLines, translator: translator)
        guard !isCancelled() else { return .captureCancelled }

        guard !translatedLines.isEmpty else {
            AppLogger.general.warning("Screenshot line translation produced no results")
            return .translationFailed(
                originalResult,
                L10n.localize(
                    "screenshot.result.error.translation_empty",
                    comment: ""
                )
            )
        }

        // 3. 构建 TranslatedOverlayAnnotationElement 并渲染
        let lines = zip(ocrLines, translatedLines).map { ocrLine, translated in
            TranslatedOverlayAnnotationElement.Line(bounds: ocrLine.boundingBox, text: translated)
        }
        var document = AnnotationDocument()
        document.add(.translatedOverlay(TranslatedOverlayAnnotationElement(lines: lines)))
        let renderer = AnnotationRenderer()
        do {
            let renderedImage = try renderer.render(image: image, document: document)
            AppLogger.general.info("Screenshot translated overlay rendered lines=\(lines.count)")
            return .translatedOverlay(
                originalResult: originalResult,
                overlayImage: TranslatedOverlayImage(image: renderedImage)
            )
        } catch {
            AppLogger.general.warning("Screenshot overlay render failed: \(error.localizedDescription)")
            return .translationFailed(originalResult, error.localizedDescription)
        }
    }

    private func saveScreenshotAsset(image: CGImage, ocrText: String?) {
        guard let assetRepository else { return }
        let id = UUID().uuidString
        let imagePath: String?
        if let assetImageDirectory {
            do {
                try FileManager.default.createDirectory(
                    at: assetImageDirectory,
                    withIntermediateDirectories: true
                )
                imagePath = try ScreenshotImageStorage.save(
                    image: image,
                    id: id,
                    directory: assetImageDirectory
                )
            } catch {
                AppLogger.general.error("Failed to save screenshot asset image: \(error.localizedDescription)")
                imagePath = nil
            }
        } else {
            imagePath = nil
        }

        let now = Date()
        let text = ocrText?.trimmingCharacters(in: .whitespacesAndNewlines)
        let searchableText = text?.isEmpty == false ? text : nil
        guard let imagePath else {
            AppLogger.general.warning("Skipping screenshot asset because image path is unavailable")
            return
        }
        do {
            let asset = try AssetItem.makeImage(
                id: "screenshot-\(id)",
                source: .screenshot,
                title: "Image (\(image.width)x\(image.height))",
                imagePath: imagePath,
                previewText: searchableText,
                text: searchableText,
                contentHash: "screenshot-\(id)",
                captureReason: .screenshotCaptured,
                createdAt: now,
                updatedAt: now
            )
            try assetRepository.save(asset)
        } catch {
            AppLogger.general.error("Failed to save screenshot asset: \(error.localizedDescription)")
        }
    }

    /// 按行翻译：优先走 JSON 模式（云 LLM），失败后逐行翻译，保证译文能回到对应 OCR bbox。
    static func translateLines(
        _ lines: [OCRLine],
        translator: any PromptAwareTextRefining
    ) async -> [String] {
        AppLogger.general.debug("Screenshot line translation request count=\(lines.count)")
        let supportsStructuredLineTranslation = (translator as? StructuredLineTranslationSupporting)?
            .supportsStructuredLineTranslation ?? true

        if supportsStructuredLineTranslation {
            // JSON 模式：构造 [{index, text}] 输入。只给真正理解 prompt 的翻译器使用；
            // 本地直译模型会把 JSON 当普通文本翻译，耗时且通常无法解析。
            let inputItems = lines.enumerated().map { index, line in
                "{\"index\":\(index),\"text\":\(Self.escapeJSON(line.text))}"
            }.joined(separator: ",")
            let inputJSON = "[\(inputItems)]"

            do {
                AppLogger.general.debug("Screenshot line translation try JSON mode")
                let raw = try await translator.refine(
                    TextRefinementRequest(
                        text: inputJSON,
                        systemPrompt: Self.lineTranslationSystemPrompt,
                        model: nil,
                        temperature: 0.2,
                        purpose: .directTask
                    )
                )
                if let parsed = Self.parseLineTranslationResponse(raw, expectedCount: lines.count) {
                    AppLogger.general.debug("Screenshot line translation JSON mode success count=\(parsed.count)")
                    return parsed
                }
                AppLogger.general.warning("Screenshot line translation JSON parse failed, fallback to individual line mode")
            } catch {
                AppLogger.general.warning("Screenshot line translation JSON mode error: \(error.localizedDescription)")
            }
        } else {
            AppLogger.general.debug("Screenshot line translation skip JSON mode: translator does not support structured prompts")
            return await translateLinesIndividually(lines, translator: translator)
        }

        return await translateLinesIndividually(lines, translator: translator)
    }

    static func lineTranslationEvents(
        _ lines: [OCRLine],
        translator: any PromptAwareTextRefining
    ) -> AsyncStream<LineTransformEvent> {
        AsyncStream<LineTransformEvent> { continuation in
            let task = Task {
                let supportsStructuredLineTranslation = (translator as? StructuredLineTranslationSupporting)?
                    .supportsStructuredLineTranslation ?? true
                if supportsStructuredLineTranslation {
                    var completed: [Int: String] = [:]
                    let batches = structuredLineTranslationBatches(for: lines)
                    for (batchIndex, batch) in batches.enumerated() {
                        let translated = await translateStructuredLineBatch(
                            batch,
                            translator: translator
                        )
                        for (index, text) in translated {
                            completed[index] = text
                        }
                        continuation.yield(
                            LineTransformEvent(
                                completedLines: completed,
                                totalLineCount: lines.count,
                                isFinal: batchIndex == batches.indices.last
                            )
                        )
                    }
                    continuation.finish()
                    return
                }

                var completed: [Int: String] = [:]
                for (index, line) in lines.enumerated() {
                    do {
                        let translated = try await translator.refine(
                            TextRefinementRequest(
                                text: line.text,
                                systemPrompt: Self.translationSystemPrompt,
                                model: nil,
                                temperature: 0.2,
                                purpose: .directTask
                            )
                        )
                        completed[index] = translated.trimmingCharacters(in: .whitespacesAndNewlines)
                    } catch {
                        AppLogger.general.warning("Screenshot line translation event failed index=\(index): \(error.localizedDescription)")
                        completed[index] = ""
                    }
                    continuation.yield(
                        LineTransformEvent(
                            completedLines: completed,
                            totalLineCount: lines.count,
                            isFinal: index == lines.indices.last
                        )
                    )
                }
                continuation.finish()
            }
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    private static let structuredLineTranslationBatchSize = 8

    private static func structuredLineTranslationBatches(
        for lines: [OCRLine]
    ) -> [[(index: Int, line: OCRLine)]] {
        var batches: [[(index: Int, line: OCRLine)]] = []
        var batch: [(index: Int, line: OCRLine)] = []
        batch.reserveCapacity(structuredLineTranslationBatchSize)
        for (index, line) in lines.enumerated() {
            batch.append((index, line))
            if batch.count == structuredLineTranslationBatchSize {
                batches.append(batch)
                batch = []
                batch.reserveCapacity(structuredLineTranslationBatchSize)
            }
        }
        if !batch.isEmpty {
            batches.append(batch)
        }
        return batches
    }

    private static func translateStructuredLineBatch(
        _ batch: [(index: Int, line: OCRLine)],
        translator: any PromptAwareTextRefining
    ) async -> [Int: String] {
        let inputItems = batch.map { index, line in
            "{\"index\":\(index),\"text\":\(Self.escapeJSON(line.text))}"
        }.joined(separator: ",")
        let inputJSON = "[\(inputItems)]"
        let allowedIndexes = Set(batch.map(\.index))
        do {
            let raw = try await translator.refine(
                TextRefinementRequest(
                    text: inputJSON,
                    systemPrompt: Self.lineTranslationSystemPrompt,
                    model: nil,
                    temperature: 0.2,
                    purpose: .directTask
                )
            )
            if let parsed = Self.parseLineTranslationResponseMap(
                raw,
                allowedIndexes: allowedIndexes,
                expectedItemCount: batch.count
            ) {
                return parsed
            }
            AppLogger.general.warning("Screenshot line translation batch parse failed, fallback to individual line mode")
        } catch {
            AppLogger.general.warning("Screenshot line translation batch error: \(error.localizedDescription)")
        }

        let translated = await translateLinesIndividually(batch.map(\.line), translator: translator)
        return Dictionary(
            uniqueKeysWithValues: zip(batch.map(\.index), translated)
        )
    }

    private static func translateLinesIndividually(
        _ lines: [OCRLine],
        translator: any PromptAwareTextRefining
    ) async -> [String] {
        var translatedLines: [String] = []
        translatedLines.reserveCapacity(lines.count)
        for line in lines {
            do {
                let translated = try await translator.refine(
                    TextRefinementRequest(
                        text: line.text,
                        systemPrompt: Self.translationSystemPrompt,
                        model: nil,
                        temperature: 0.2,
                        purpose: .directTask
                    )
                )
                translatedLines.append(translated.trimmingCharacters(in: .whitespacesAndNewlines))
            } catch {
                AppLogger.general.warning("Screenshot individual line translation failed: \(error.localizedDescription)")
                translatedLines.append("")
            }
        }
        AppLogger.general.debug("Screenshot individual line translation completed count=\(translatedLines.count)")
        return translatedLines
    }

    private static func escapeJSON(_ string: String) -> String {
        // 简易 JSON 字符串转义，足够处理 OCR 文本
        var escaped = string
        escaped = escaped.replacingOccurrences(of: "\\", with: "\\\\")
        escaped = escaped.replacingOccurrences(of: "\"", with: "\\\"")
        escaped = escaped.replacingOccurrences(of: "\n", with: "\\n")
        escaped = escaped.replacingOccurrences(of: "\r", with: "\\r")
        escaped = escaped.replacingOccurrences(of: "\t", with: "\\t")
        return "\"\(escaped)\""
    }

    /// 解析 LLM 返回的 JSON 数组 [{index, translated}]，要求行数匹配。
    static func parseLineTranslationResponse(_ raw: String, expectedCount: Int) -> [String]? {
        guard let parsed = parseLineTranslationResponseMap(
            raw,
            allowedIndexes: Set(0..<expectedCount),
            expectedItemCount: expectedCount
        ) else {
            return nil
        }
        return (0..<expectedCount).map { parsed[$0] ?? "" }
    }

    private static func parseLineTranslationResponseMap(
        _ raw: String,
        allowedIndexes: Set<Int>,
        expectedItemCount: Int
    ) -> [Int: String]? {
        // 尝试解析为 [{index, translated}]
        struct TranslationItem: Decodable {
            let index: Int?
            let translated: String?
        }
        // 容忍 LLM 在 JSON 前后加了无关字符，先抽出第一个 JSON 数组片段
        guard let arrayStart = raw.firstIndex(of: "["),
              let arrayEnd = raw.lastIndex(of: "]"),
              arrayStart < arrayEnd else {
            return nil
        }
        let jsonSubstring = String(raw[arrayStart...arrayEnd])
        guard let jsonData = jsonSubstring.data(using: .utf8),
              let items = try? JSONDecoder().decode([TranslationItem].self, from: jsonData) else {
            return nil
        }
        guard items.count == expectedItemCount else { return nil }
        var result: [Int: String] = [:]
        for item in items {
            guard let index = item.index,
                  allowedIndexes.contains(index),
                  result[index] == nil,
                  let translated = item.translated else {
                return nil
            }
            result[index] = translated
        }
        return result.count == expectedItemCount ? result : nil
    }

    func translate(_ result: ScreenshotOCRResult) async -> ScreenshotOCRServiceOutcome {
        guard let translator,
              translator.isEnabled,
              Self.translationIsConfigured(translator) else {
            AppLogger.general.warning("Manual translation unavailable: translator not ready")
            return .translationUnavailable(result)
        }

        do {
            AppLogger.general.info("Manual screenshot translate started")
            let translated = try await translator.refine(
                TextRefinementRequest(
                    text: result.originalText,
                    systemPrompt: Self.translationSystemPrompt,
                    model: nil,
                    temperature: 0.2,
                    purpose: .directTask
                )
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !translated.isEmpty else {
                AppLogger.general.warning("Manual translation produced empty result")
                return .translationUnavailable(result)
            }

            var updated = result
            updated.translatedText = translated
            lastResultStore.setLastResultText(translated)
            AppLogger.general.info("Manual screenshot translation completed length=\(translated.count)")
            return .translated(updated)
        } catch {
            AppLogger.general.warning("Manual screenshot translation failed: \(error.localizedDescription)")
            return .translationFailed(result, error.localizedDescription)
        }
    }

    func translationEvents(for result: ScreenshotOCRResult) -> AsyncStream<TextTransformEvent> {
        let message = (translator as? any TextTransformAvailabilityMessaging)?
            .unavailableMessage(for: .translation)
            ?? L10n.localize("screenshot.refine.unavailable.config_required", comment: "")
        return transformEvents(
            for: result,
            operation: .translation,
            systemPrompt: Self.translationSystemPrompt,
            unavailableMessage: message
        )
    }

    func summarize(_ result: ScreenshotOCRResult) async -> ScreenshotOCRServiceOutcome {
        guard let translator,
              translator.isEnabled,
              summaryIsConfigured(translator) else {
            AppLogger.general.warning("Summary unavailable: translator not ready")
            return .summaryUnavailable(result)
        }

        do {
            AppLogger.general.info("Screenshot summary started")
            let summary = try await translator.refine(
                TextRefinementRequest(
                    text: result.originalText,
                    systemPrompt: Self.summarySystemPrompt,
                    model: nil,
                    temperature: 0.2,
                    purpose: .directTask
                )
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !summary.isEmpty else {
                AppLogger.general.warning("Screenshot summary produced empty result")
                return .summaryUnavailable(result)
            }

            var updated = result
            updated.summaryText = summary
            lastResultStore.setLastResultText(summary)
            AppLogger.general.info("Screenshot summary completed length=\(summary.count)")
            return .summarized(updated)
        } catch {
            AppLogger.general.warning("Screenshot summary failed: \(error.localizedDescription)")
            return .summaryFailed(result, error.localizedDescription)
        }
    }

    func summaryEvents(for result: ScreenshotOCRResult) -> AsyncStream<TextTransformEvent> {
        let message = (translator as? any TextTransformAvailabilityMessaging)?
            .unavailableMessage(for: .summary)
            ?? L10n.localize("screenshot.refine.unavailable.config_required", comment: "")
        return transformEvents(
            for: result,
            operation: .summary,
            systemPrompt: Self.summarySystemPrompt,
            unavailableMessage: message
        )
    }

    private func transformEvents(
        for result: ScreenshotOCRResult,
        operation: TextTransformOperation,
        systemPrompt: String,
        unavailableMessage: String
    ) -> AsyncStream<TextTransformEvent> {
        guard let translator,
              translator.isEnabled,
              transformIsConfigured(translator, operation: operation) else {
            return AsyncStream<TextTransformEvent> { continuation in
                continuation.yield(.failed(message: unavailableMessage, partialText: ""))
                continuation.finish()
            }
        }

        let sourceEvents = TextTransformService(refiner: translator).events(
            for: TextTransformRequest(
                text: result.originalText,
                operation: operation,
                systemPrompt: systemPrompt,
                temperature: 0.2
            )
        )
        let lastResultStore = self.lastResultStore
        return AsyncStream<TextTransformEvent> { continuation in
            let task = Task { @MainActor in
                for await event in sourceEvents {
                    if case .completed(let text) = event {
                        lastResultStore.setLastResultText(text)
                    }
                    continuation.yield(event)
                }
                continuation.finish()
            }
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    private func transformIsConfigured(
        _ refiner: any PromptAwareTextRefining,
        operation: TextTransformOperation
    ) -> Bool {
        switch operation {
        case .translation:
            return Self.translationIsConfigured(refiner)
        case .summary:
            return summaryIsConfigured(refiner)
        }
    }

    func speak(_ target: ScreenshotOCRSpeechTarget, from result: ScreenshotOCRResult) {
        speak(target, from: result, completion: nil)
    }

    func speak(
        _ target: ScreenshotOCRSpeechTarget,
        from result: ScreenshotOCRResult,
        completion: ScreenshotSpeechCompletion?
    ) {
        let text: String
        switch target {
        case .original:
            text = result.originalText
        case .translated:
            text = result.translatedText ?? result.originalText
        case .summary:
            text = result.summaryText ?? result.translatedText ?? result.originalText
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        speechService.speak(trimmed, completion: completion)
    }

    func stopSpeaking() {
        speechService.stop()
    }

    static func translationIsConfigured(_ refiner: any PromptAwareTextRefining) -> Bool {
        if let capabilities = refiner as? ScreenshotTextRefiningCapabilities {
            return capabilities.isTranslationConfigured
        }
        return refiner.isConfigured
    }

    private func summaryIsConfigured(_ refiner: any PromptAwareTextRefining) -> Bool {
        if let capabilities = refiner as? ScreenshotTextRefiningCapabilities {
            return capabilities.isSummaryConfigured
        }
        return refiner.isConfigured
    }

    nonisolated static var translationSystemPrompt: String {
        PromptRenderer().render(ScreenshotOCRPromptCatalog.translation).renderedText
    }

    /// 按行翻译的 prompt：输入 [{index, text}] JSON，要求输出 [{index, translated}] JSON。
    /// index 必须一一对应，禁止合并/拆分/重排。这样译文能按 index 回填到 OCR bbox。
    nonisolated static var lineTranslationSystemPrompt: String {
        PromptRenderer().render(ScreenshotOCRPromptCatalog.lineTranslation).renderedText
    }

    nonisolated static var summarySystemPrompt: String {
        PromptRenderer().render(ScreenshotOCRPromptCatalog.summary).renderedText
    }
}

@MainActor
final class ScreenshotInlineSelectionTranslator: InlineSelectionTranslating {
    private let ocrRecognizer: any TextOCRRecognizing
    private let translator: (any PromptAwareTextRefining)?
    private let lastResultStore: any LastResultStoring
    private let onLineTranslationEvent: ((LineTransformEvent) -> Void)?

    init(
        ocrRecognizer: any TextOCRRecognizing,
        translator: (any PromptAwareTextRefining)?,
        lastResultStore: any LastResultStoring,
        onLineTranslationEvent: ((LineTransformEvent) -> Void)? = nil
    ) {
        self.ocrRecognizer = ocrRecognizer
        self.translator = translator
        self.lastResultStore = lastResultStore
        self.onLineTranslationEvent = onLineTranslationEvent
    }

    func translatedOverlay(for image: CGImage) async throws -> TranslatedOverlayAnnotationElement {
        try await translatedOverlay(for: image, progress: { _ in })
    }

    func translatedOverlay(
        for image: CGImage,
        progress: @escaping @MainActor (InlineSelectionTranslationProgress) -> Void
    ) async throws -> TranslatedOverlayAnnotationElement {
        let startedAt = Date()
        AppLogger.general.info("screenshot_inline_translation_started imageWidth=\(image.width) imageHeight=\(image.height)")
        let ocrLines: [OCRLine]
        do {
            ocrLines = try await ocrRecognizer.recognizeTextLines(in: image)
            AppLogger.general.info("screenshot_inline_translation_ocr_completed lineCount=\(ocrLines.count)")
        } catch {
            AppLogger.general.error("screenshot_inline_translation_ocr_failed error=\(error.localizedDescription)")
            throw error
        }
        guard !ocrLines.isEmpty else {
            AppLogger.general.warning("screenshot_inline_translation_no_text")
            throw ScreenshotInlineTranslationError.noRecognizedText
        }

        let originalText = ocrLines.map(\.text).joined(separator: "\n")
        lastResultStore.setLastResultText(originalText)

        guard let translator,
              translator.isEnabled,
              ScreenshotOCRService.translationIsConfigured(translator) else {
            AppLogger.general.warning("screenshot_inline_translation_unavailable translatorPresent=\(translator != nil)")
            throw ScreenshotInlineTranslationError.translationUnavailable
        }

        AppLogger.general.info("screenshot_inline_translation_refine_started lineCount=\(ocrLines.count)")
        var completedLines: [Int: String] = [:]
        let lineTranslationService = LineMappedTranslationService(translator: translator)
        for await event in lineTranslationService.events(for: ocrLines) {
            completedLines = event.completedLines
            onLineTranslationEvent?(event)
            progress(
                InlineSelectionTranslationProgress(
                    completed: event.completedLines.count,
                    total: event.totalLineCount,
                    partialOverlay: Self.translatedOverlay(
                        from: event.completedLines,
                        ocrLines: ocrLines
                    )
                )
            )
        }
        let translatedLines = ocrLines.indices.map { completedLines[$0] ?? "" }
        guard !translatedLines.isEmpty else {
            AppLogger.general.error("screenshot_inline_translation_empty_result lineCount=\(ocrLines.count)")
            throw ScreenshotInlineTranslationError.emptyTranslation
        }

        let lines = zip(ocrLines, translatedLines).map { ocrLine, translated in
            TranslatedOverlayAnnotationElement.Line(
                bounds: ocrLine.boundingBox,
                text: translated
            )
        }
        let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)
        AppLogger.general.info("screenshot_inline_translation_completed lineCount=\(lines.count) durationMs=\(durationMs)")
        return TranslatedOverlayAnnotationElement(lines: lines)
    }

    private static func translatedOverlay(
        from completedLines: [Int: String],
        ocrLines: [OCRLine]
    ) -> TranslatedOverlayAnnotationElement? {
        let lines = completedLines.keys.sorted().compactMap { index -> TranslatedOverlayAnnotationElement.Line? in
            guard ocrLines.indices.contains(index) else {
                return nil
            }
            return TranslatedOverlayAnnotationElement.Line(
                bounds: ocrLines[index].boundingBox,
                text: completedLines[index] ?? ""
            )
        }
        guard !lines.isEmpty else {
            return nil
        }
        return TranslatedOverlayAnnotationElement(lines: lines)
    }
}

private enum ScreenshotInlineTranslationError: LocalizedError {
    case noRecognizedText
    case translationUnavailable
    case emptyTranslation

    var errorDescription: String? {
        switch self {
        case .noRecognizedText:
            return L10n.localize("screenshot.ocr.no_text_for_screenshot", comment: "")
        case .translationUnavailable:
            return L10n.localize("screenshot.refine.unavailable.config_required", comment: "")
        case .emptyTranslation:
            return L10n.localize("screenshot.result.error.translation_empty", comment: "")
        }
    }
}

@MainActor
final class SystemInteractiveScreenshotImageProvider: ScreenshotImageProviding {
    private let temporaryDirectory: URL
    private let processRunner: @MainActor (URL) async throws -> Void

    init(
        temporaryDirectory: URL = FileManager.default.temporaryDirectory,
        processRunner: @escaping @MainActor (URL) async throws -> Void = SystemInteractiveScreenshotImageProvider.runSystemScreenshot
    ) {
        self.temporaryDirectory = temporaryDirectory
        self.processRunner = processRunner
    }

    func captureImage() async throws -> CGImage {
        let captureURL = temporaryDirectory
            .appendingPathComponent("voxflow-screenshot-ocr-\(UUID().uuidString).png")
        defer {
            try? FileManager.default.removeItem(at: captureURL)
        }

        try await processRunner(captureURL)
        guard let image = NSImage(contentsOf: captureURL) else {
            throw ScreenshotOCRServiceError.captureFailed(
                L10n.localize("screenshot.capture.error.reading_failure", comment: "")
            )
        }

        var proposedRect = CGRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) else {
            throw ScreenshotOCRServiceError.captureFailed(
                L10n.localize("screenshot.capture.error.decode_failure", comment: "")
            )
        }
        return cgImage
    }

    static func runSystemScreenshot(outputURL: URL) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-i", "-x", outputURL.path]

        do {
            try process.run()
        } catch {
            throw ScreenshotOCRServiceError.captureFailed(
                L10n.localize("screenshot.capture.error.start_failure", comment: "")
            )
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    process.waitUntilExit()
                    if process.terminationStatus == 0 {
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: ScreenshotOCRServiceError.captureCancelled)
                    }
                }
            }
        } onCancel: {
            process.terminate()
        }

        guard process.terminationStatus == 0 else {
            throw ScreenshotOCRServiceError.captureCancelled
        }
    }
}

@MainActor
final class SystemScreenshotSpeechService: NSObject, ScreenshotSpeechSpeaking {
    private let localSynthesizer: (any ScreenshotLocalTTSSynthesizing)?
    private let audioPlayer: any ScreenshotAudioPlaying
    private let systemSpeaker: any ScreenshotSystemSpeechSpeaking
    private let setSystemOutputMuted: @MainActor (Bool) -> Void
    private var speechTask: Task<Void, Never>?
    private var speechGeneration = 0

    init(
        localSynthesizer: (any ScreenshotLocalTTSSynthesizing)? = SoniqoScreenshotLocalTTSSynthesizer(),
        audioPlayer: any ScreenshotAudioPlaying = AVAudioScreenshotPlayer(),
        systemSpeaker: any ScreenshotSystemSpeechSpeaking = AVSpeechScreenshotSystemSpeaker(),
        setSystemOutputMuted: @escaping @MainActor (Bool) -> Void = { _ in }
    ) {
        self.localSynthesizer = localSynthesizer
        self.audioPlayer = audioPlayer
        self.systemSpeaker = systemSpeaker
        self.setSystemOutputMuted = setSystemOutputMuted
    }

    func speak(_ text: String, completion: ScreenshotSpeechCompletion? = nil) {
        stop()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        speechGeneration += 1
        let generation = speechGeneration
        speechTask = Task { @MainActor in
            guard !Task.isCancelled else { return }
            let synthesizedAudio: ScreenshotTTSAudio? = if let localSynthesizer {
                try? await localSynthesizer.synthesizeIfAvailable(text: trimmed)
            } else {
                nil
            }
            guard !Task.isCancelled else { return }
            if let audio = synthesizedAudio,
               !audio.samples.isEmpty {
                do {
                    try audioPlayer.play(audio) { [weak self] in
                        self?.finishSpeech(generation: generation)
                        completion?()
                    }
                    return
                } catch {
                    AppLogger.general.warning("Screenshot local TTS playback failed, falling back to system speech: \(error.localizedDescription)")
                }
            }
            guard !Task.isCancelled else { return }
            systemSpeaker.speak(trimmed) { [weak self] in
                self?.finishSpeech(generation: generation)
                completion?()
            }
        }
    }

    func stop() {
        speechGeneration += 1
        speechTask?.cancel()
        speechTask = nil
        audioPlayer.stop()
        systemSpeaker.stop()
    }

    private func finishSpeech(generation: Int) {
        guard generation == speechGeneration else { return }
        speechTask = nil
    }
}

actor SoniqoScreenshotLocalTTSSynthesizer: ScreenshotLocalTTSSynthesizing {
    private let defaults: UserDefaults
    private let downloader: any CapabilityModelDownloading
    private var kokoro: KokoroTTSModel?
    private var qwen3: Qwen3TTSModel?
    private var cosyVoice: CosyVoiceTTSModel?

    init(
        defaults: UserDefaults = .standard,
        downloader: any CapabilityModelDownloading = SoniqoCapabilityModelDownloader()
    ) {
        self.defaults = defaults
        self.downloader = downloader
    }

    func synthesizeIfAvailable(text: String) async throws -> ScreenshotTTSAudio? {
        let modelID = CapabilityModelViewModel.selectedModelID(kind: .tts, defaults: defaults)
        guard downloader.isInstalled(modelID: modelID) else { return nil }

        switch modelID {
        case CapabilityModelID.kokoroTTS:
            let model = try await loadKokoro()
            return ScreenshotTTSAudio(
                samples: try model.synthesize(text: text, language: Self.shortLanguage(for: text)),
                sampleRate: Double(KokoroTTSModel.outputSampleRate)
            )
        case CapabilityModelID.qwen3TTS06B4Bit:
            let model = try await loadQwen3()
            return ScreenshotTTSAudio(
                samples: model.synthesize(text: text, language: Self.longLanguage(for: text), languageExplicit: true),
                sampleRate: 24_000
            )
        case CapabilityModelID.cosyVoice3:
            let model = try await loadCosyVoice()
            return ScreenshotTTSAudio(
                samples: model.synthesize(text: text, language: Self.longLanguage(for: text)),
                sampleRate: 24_000
            )
        default:
            return nil
        }
    }

    private func loadKokoro() async throws -> KokoroTTSModel {
        if let kokoro { return kokoro }
        let loaded = try await KokoroTTSModel.fromPretrained(offlineMode: true)
        kokoro = loaded
        return loaded
    }

    private func loadQwen3() async throws -> Qwen3TTSModel {
        if let qwen3 { return qwen3 }
        let loaded = try await Qwen3TTSModel.fromPretrained(offlineMode: true)
        qwen3 = loaded
        return loaded
    }

    private func loadCosyVoice() async throws -> CosyVoiceTTSModel {
        if let cosyVoice { return cosyVoice }
        let loaded = try await CosyVoiceTTSModel.fromPretrained(offlineMode: true)
        cosyVoice = loaded
        return loaded
    }

    private static func shortLanguage(for text: String) -> String {
        containsChinese(text) ? "zh" : "en"
    }

    private static func longLanguage(for text: String) -> String {
        containsChinese(text) ? "chinese" : "english"
    }

    private static func containsChinese(_ text: String) -> Bool {
        text.range(of: #"\p{Han}"#, options: .regularExpression) != nil
    }
}

@MainActor
final class AVAudioScreenshotPlayer: ScreenshotAudioPlaying {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private(set) var connectedSampleRate: Double?

    init() {
        engine.attach(player)
        reconnectForPlayback(sampleRate: 24_000)
    }

    func play(_ audio: ScreenshotTTSAudio, completion: @escaping ScreenshotSpeechCompletion) throws {
        stop()
        reconnectForPlayback(sampleRate: audio.sampleRate)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: audio.sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(audio.samples.count)
              ) else {
            throw ScreenshotAudioPlaybackError.invalidBuffer
        }
        buffer.frameLength = AVAudioFrameCount(audio.samples.count)
        if let channel = buffer.floatChannelData?[0] {
            audio.samples.withUnsafeBufferPointer { pointer in
                channel.update(from: pointer.baseAddress!, count: audio.samples.count)
            }
        }
        if !engine.isRunning {
            try engine.start()
        }
        player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { _ in
            Task { @MainActor in
                completion()
            }
        }
        player.play()
    }

    func stop() {
        if player.isPlaying {
            player.stop()
        }
    }

    func reconnectForPlayback(sampleRate: Double) {
        guard connectedSampleRate != sampleRate,
              let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)
        else {
            return
        }
        engine.disconnectNodeOutput(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        connectedSampleRate = sampleRate
    }
}

@MainActor
final class AVSpeechScreenshotSystemSpeaker: NSObject, ScreenshotSystemSpeechSpeaking {
    private let synthesizer = AVSpeechSynthesizer()
    private var completion: ScreenshotSpeechCompletion?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String, completion: @escaping ScreenshotSpeechCompletion) {
        stop()
        self.completion = completion
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.voice = AVSpeechSynthesisVoice(language: Self.preferredLanguage(for: text))
        synthesizer.speak(utterance)
    }

    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        } else {
            completion = nil
        }
    }

    private func finishCurrentUtterance() {
        let completion = completion
        self.completion = nil
        completion?()
    }

    private static func preferredLanguage(for text: String) -> String {
        if text.range(of: #"\p{Han}"#, options: .regularExpression) != nil {
            return "zh-CN"
        }
        return "en-US"
    }
}

extension AVSpeechScreenshotSystemSpeaker: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            self?.finishCurrentUtterance()
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            self?.finishCurrentUtterance()
        }
    }
}
