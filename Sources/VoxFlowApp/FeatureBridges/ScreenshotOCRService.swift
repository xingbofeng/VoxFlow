import AppKit
import AVFoundation
import CoreGraphics
@preconcurrency import CosyVoiceTTS
import Foundation
@preconcurrency import KokoroTTS
@preconcurrency import Qwen3TTS

struct ScreenshotOCRResult: Equatable {
    let originalText: String
    let originalImage: CGImage?
    let ocrStatusMessage: String?
    var translatedText: String?
    var summaryText: String?

    init(
        originalText: String,
        originalImage: CGImage? = nil,
        ocrStatusMessage: String? = nil,
        translatedText: String? = nil,
        summaryText: String? = nil
    ) {
        self.originalText = originalText
        self.originalImage = originalImage
        self.ocrStatusMessage = ocrStatusMessage
        self.translatedText = translatedText
        self.summaryText = summaryText
    }

    static func == (lhs: ScreenshotOCRResult, rhs: ScreenshotOCRResult) -> Bool {
        lhs.originalText == rhs.originalText &&
            lhs.ocrStatusMessage == rhs.ocrStatusMessage &&
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
}

enum ScreenshotOCRServiceError: LocalizedError, Equatable {
    case captureCancelled
    case captureFailed(String)

    var errorDescription: String? {
        switch self {
        case .captureCancelled:
            return "已取消截图"
        case .captureFailed(let reason):
            return reason
        }
    }
}

enum ScreenshotAudioPlaybackError: LocalizedError, Equatable {
    case invalidBuffer

    var errorDescription: String? {
        switch self {
        case .invalidBuffer:
            return "无法创建截图朗读音频缓冲区"
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
    private let isCancelled: @MainActor () -> Bool

    init(
        imageProvider: any ScreenshotImageProviding,
        ocrRecognizer: any TextOCRRecognizing,
        translator: (any PromptAwareTextRefining)?,
        speechService: any ScreenshotSpeechSpeaking,
        clipboard: any ScreenshotImageClipboardWriting,
        lastResultStore: any LastResultStoring,
        isCancelled: @escaping @MainActor () -> Bool = { Task.isCancelled }
    ) {
        self.imageProvider = imageProvider
        self.ocrRecognizer = ocrRecognizer
        self.translator = translator
        self.speechService = speechService
        self.clipboard = clipboard
        self.lastResultStore = lastResultStore
        self.isCancelled = isCancelled
    }

    func captureAndRecognize() async -> ScreenshotOCRServiceOutcome {
        guard !isCancelled() else { return .captureCancelled }
        let image: CGImage
        do {
            image = try await imageProvider.captureImage()
        } catch ScreenshotOCRServiceError.captureCancelled {
            return .captureCancelled
        } catch ScreenshotOCRServiceError.captureFailed(let reason) {
            return .captureFailed(reason)
        } catch {
            return .captureFailed(error.localizedDescription)
        }

        guard !isCancelled() else { return .captureCancelled }
        clipboard.setImage(image)

        do {
            let text = try await ocrRecognizer
                .recognizeText(in: image)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !isCancelled() else { return .captureCancelled }
            guard !text.isEmpty else {
                return .recognized(
                    ScreenshotOCRResult(
                        originalText: "",
                        originalImage: image,
                        ocrStatusMessage: "未识别到截图文字"
                    )
                )
            }
            lastResultStore.setLastResultText(text)
            return .recognized(ScreenshotOCRResult(originalText: text, originalImage: image))
        } catch {
            return .ocrFailed(error.localizedDescription)
        }
    }

    func translate(_ result: ScreenshotOCRResult) async -> ScreenshotOCRServiceOutcome {
        guard let translator,
              translator.isEnabled,
              translationIsConfigured(translator) else {
            return .translationUnavailable(result)
        }

        do {
            let translated = try await translator.refine(
                TextRefinementRequest(
                    text: result.originalText,
                    systemPrompt: Self.translationSystemPrompt,
                    model: nil,
                    temperature: 0.2
                )
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !translated.isEmpty else {
                return .translationUnavailable(result)
            }

            var updated = result
            updated.translatedText = translated
            lastResultStore.setLastResultText(translated)
            return .translated(updated)
        } catch {
            return .translationFailed(result, error.localizedDescription)
        }
    }

    func summarize(_ result: ScreenshotOCRResult) async -> ScreenshotOCRServiceOutcome {
        guard let translator,
              summaryIsConfigured(translator) else {
            return .summaryUnavailable(result)
        }

        do {
            let summary = try await translator.refine(
                TextRefinementRequest(
                    text: result.originalText,
                    systemPrompt: Self.summarySystemPrompt,
                    model: nil,
                    temperature: 0.2
                )
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !summary.isEmpty else {
                return .summaryUnavailable(result)
            }

            var updated = result
            updated.summaryText = summary
            lastResultStore.setLastResultText(summary)
            return .summarized(updated)
        } catch {
            return .summaryFailed(result, error.localizedDescription)
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

    private func translationIsConfigured(_ refiner: any PromptAwareTextRefining) -> Bool {
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

    nonisolated static let translationSystemPrompt = """
        你是截图文字翻译助手。把用户框选截图中 OCR 得到的文字翻译成自然准确的对照文本。
        无论原文是什么语言，都翻译成简体中文；原文已经是中文时，保持中文并只做必要的自然化整理。
        中英混合时保留专名、代码、URL、命令和数字。尽量保留原文段落和换行结构。只输出译文，不要解释、标题、引号或额外说明。
        """

    nonisolated static let summarySystemPrompt = """
        你是截图文字总结助手。请根据截图 OCR 原文提炼关键信息。
        输出 3 条以内的简短要点；保留重要名称、数字、URL、错误码和操作建议。
        只输出总结内容，不要添加标题、引号或额外说明。
        """
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
            throw ScreenshotOCRServiceError.captureFailed("无法读取系统截图")
        }

        var proposedRect = CGRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) else {
            throw ScreenshotOCRServiceError.captureFailed("无法解码系统截图")
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
            throw ScreenshotOCRServiceError.captureFailed("无法启动系统截图")
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

    init() {
        engine.attach(player)
        if let format = AVAudioFormat(standardFormatWithSampleRate: 24_000, channels: 1) {
            engine.connect(player, to: engine.mainMixerNode, format: format)
        }
    }

    func play(_ audio: ScreenshotTTSAudio, completion: @escaping ScreenshotSpeechCompletion) throws {
        stop()
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
