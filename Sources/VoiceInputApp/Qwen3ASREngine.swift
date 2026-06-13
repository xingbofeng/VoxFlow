import AVFoundation
import FluidAudio
import Foundation

private final class ManagerBox: @unchecked Sendable {
    let value: Any
    init(_ value: Any) { self.value = value }
}

private final class Qwen3CallbackBox: @unchecked Sendable {
    var onTranscription: ((String, Bool) -> Void)?
    var onError: ((Error) -> Void)?
}

struct Qwen3StreamingUpdate: Sendable, Equatable {
    let transcript: String
    let isFinal: Bool
}

protocol Qwen3StreamingSession: Sendable {
    func addAudio(_ samples: [Float]) async throws -> Qwen3StreamingUpdate?
    func finish() async throws -> Qwen3StreamingUpdate
    func cancel() async
}

protocol Qwen3StreamingSessionMaking: Sendable {
    func makeSession(modelURL: URL, languageHint: String?) async throws -> any Qwen3StreamingSession
}

struct FluidAudioQwen3StreamingSessionFactory: Qwen3StreamingSessionMaking {
    func makeSession(modelURL: URL, languageHint: String?) async throws -> any Qwen3StreamingSession {
        guard #available(macOS 15, *) else {
            throw Qwen3ASREngineError.unsupportedOS
        }
        let manager = Qwen3AsrManager()
        try await manager.loadModels(from: modelURL)
        let language = languageHint.flatMap(Qwen3AsrConfig.Language.init(rawValue:))
        let config = Qwen3StreamingConfig(
            minAudioSeconds: 1.0,
            chunkSeconds: 1.0,
            maxAudioSeconds: 30.0,
            language: language
        )
        return FluidAudioQwen3StreamingSession(
            manager: Qwen3StreamingManager(asrManager: manager, config: config)
        )
    }
}

@available(macOS 15, *)
private struct FluidAudioQwen3StreamingSession: Qwen3StreamingSession {
    let manager: Qwen3StreamingManager

    func addAudio(_ samples: [Float]) async throws -> Qwen3StreamingUpdate? {
        guard let result = try await manager.addAudio(samples) else { return nil }
        return Qwen3StreamingUpdate(transcript: result.transcript, isFinal: result.isFinal)
    }

    func finish() async throws -> Qwen3StreamingUpdate {
        let result = try await manager.finish()
        return Qwen3StreamingUpdate(transcript: result.transcript, isFinal: result.isFinal)
    }

    func cancel() async {
        await manager.reset()
    }
}

/// Qwen3-ASR CoreML-based speech recognition engine.
final class Qwen3ASREngine: NSObject, @unchecked Sendable, ASREngine {
    // MARK: - ASREngine

    var onTranscription: ((String, Bool) -> Void)? {
        get { callbacks.onTranscription }
        set { callbacks.onTranscription = newValue }
    }
    var onError: ((Error) -> Void)? {
        get { callbacks.onError }
        set { callbacks.onError = newValue }
    }
    private(set) var isAvailable: Bool

    // MARK: - Properties

    private let callbacks = Qwen3CallbackBox()
    /// Path to the FluidAudio-compatible Qwen3-ASR model directory.
    private let modelPath: String?
    private let sessionFactory: any Qwen3StreamingSessionMaking
    private var languageHint: String?

    /// Accumulated 16kHz mono audio samples during recording.
    private var audioBuffer: [Float] = []

    /// Pre-loaded Qwen3 streaming session task — created in `start()` so model loading
    /// happens during recording, not during `endAudio()`.
    /// Stored as `Any` to avoid `@available(macOS 15, *)` on the stored property.
    private var sessionTask: Task<ManagerBox, Error>?
    private var streamingTasks: [Task<Void, Never>] = []

    // MARK: - Initialization

    /// Creates a Qwen3-ASR engine.
    /// - Parameter modelPath: Path to the compiled .mlmodelc directory,
    ///   or nil if no model is available.
    init(
        modelPath: String?,
        sessionFactory: any Qwen3StreamingSessionMaking = FluidAudioQwen3StreamingSessionFactory()
    ) {
        self.modelPath = modelPath
        self.sessionFactory = sessionFactory
        if let modelPath {
            self.isAvailable = Qwen3ModelManifest.supportedModelExists(
                at: URL(fileURLWithPath: modelPath, isDirectory: true)
            )
        } else {
            self.isAvailable = false
        }
        super.init()
    }

    // MARK: - ASREngine Methods

    func configure(locale: Locale) {
        let nextLanguageHint = Self.qwen3LanguageHint(for: locale)
        if nextLanguageHint != languageHint {
            sessionTask?.cancel()
            sessionTask = nil
        }
        languageHint = nextLanguageHint
    }

    func start() throws {
        audioBuffer = []
        streamingTasks.forEach { $0.cancel() }
        streamingTasks = []

        guard isAvailable else {
            throw Qwen3ASREngineError.modelNotAvailable
        }
        guard #available(macOS 15, *) else {
            throw Qwen3ASREngineError.unsupportedOS
        }

        // Pre-load CoreML models and streaming session in background during recording.
        // This avoids the 2-5s model-load penalty in endAudio().
        if sessionTask == nil, let path = modelPath {
            let url = URL(fileURLWithPath: path, isDirectory: true)
            let languageHint = languageHint
            let sessionFactory = sessionFactory
            sessionTask = Task<ManagerBox, Error> {
                let session = try await sessionFactory.makeSession(
                    modelURL: url,
                    languageHint: languageHint
                )
                return ManagerBox(session)
            }
        }
    }

    func appendAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard isAvailable else { return }

        if let resampled = AudioPreprocessor.resampleTo16kHz(buffer) {
            audioBuffer.append(contentsOf: resampled)
            let sessionTask = sessionTask
            let callbacks = callbacks
            let task = Task { [resampled] in
                do {
                    guard let sessionTask else { return }
                    let session = try await sessionTask.value.value as! any Qwen3StreamingSession
                    if let update = try await session.addAudio(resampled),
                       !update.transcript.isEmpty {
                        await MainActor.run {
                            callbacks.onTranscription?(update.transcript, update.isFinal)
                        }
                    }
                } catch is CancellationError {
                } catch {
                    await MainActor.run {
                        callbacks.onError?(error)
                    }
                }
            }
            streamingTasks.append(task)
        }
    }

    func endAudio() {
        guard let modelPath else {
            onError?(Qwen3ASREngineError.modelNotAvailable)
            return
        }

        let samples = audioBuffer
        let languageHint = languageHint
        let sessionFactory = sessionFactory
        let callbacks = callbacks

        guard !samples.isEmpty else {
            callbacks.onTranscription?("", true)
            return
        }

        // Capture the pre-load task (start() already kicked it off).
        let task = sessionTask
        let pendingStreamingTasks = streamingTasks

        Task {
            do {
                guard #available(macOS 15, *) else {
                    throw Qwen3ASREngineError.unsupportedOS
                }

                for task in pendingStreamingTasks {
                    await task.value
                }

                let session: any Qwen3StreamingSession
                if let task {
                    session = try await task.value.value as! any Qwen3StreamingSession
                } else {
                    // Fallback: load now (shouldn't normally happen).
                    let url = URL(fileURLWithPath: modelPath, isDirectory: true)
                    session = try await sessionFactory.makeSession(
                        modelURL: url,
                        languageHint: languageHint
                    )
                    _ = try await session.addAudio(samples)
                }

                let update = try await session.finish()
                await MainActor.run {
                    callbacks.onTranscription?(update.transcript, true)
                }
            } catch {
                await MainActor.run {
                    callbacks.onError?(error)
                }
            }
        }
    }

    func stop() {
        audioBuffer = []
        streamingTasks.forEach { $0.cancel() }
        streamingTasks = []
        // Keep sessionTask alive — model stays loaded for next recording.
    }

    func cancel() {
        audioBuffer = []
        streamingTasks.forEach { $0.cancel() }
        streamingTasks = []
        sessionTask?.cancel()
        sessionTask = nil
    }

    private static func qwen3LanguageHint(for locale: Locale) -> String? {
        let identifier = locale.identifier.lowercased()
        if identifier.hasPrefix("zh") { return "zh" }
        if identifier.hasPrefix("en") { return "en" }
        if identifier.hasPrefix("ja") { return "ja" }
        if identifier.hasPrefix("ko") { return "ko" }
        return nil
    }
}

// MARK: - Errors

enum Qwen3ASREngineError: Error, LocalizedError {
    case modelNotAvailable
    case modelLoadFailed(String)
    case unsupportedOS

    var errorDescription: String? {
        switch self {
        case .modelNotAvailable:
            return "Qwen3-ASR 模型未配置。请在设置中指定模型路径。"
        case .modelLoadFailed(let reason):
            return "Qwen3-ASR 模型加载失败：\(reason)"
        case .unsupportedOS:
            return "Qwen3-ASR 需要 macOS 15 或更新版本。"
        }
    }
}
