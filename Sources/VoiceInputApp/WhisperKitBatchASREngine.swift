import AVFoundation
import Foundation
import WhisperKit

enum WhisperKitModelVariant: String, CaseIterable, Sendable {
    case turbo
    case largeV3

    var remoteName: String {
        switch self {
        case .turbo:
            return "openai_whisper-large-v3-v20240930_turbo_632MB"
        case .largeV3:
            return "openai_whisper-large-v3_947MB"
        }
    }

    var requiredPaths: [String] {
        [
            "MelSpectrogram.mlmodelc",
            "AudioEncoder.mlmodelc",
            "TextDecoder.mlmodelc",
        ]
    }

    var defaultDirectoryURL: URL {
        let base = (try? ApplicationSupportPaths.live().modelsDirectory)
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("VoiceInputModels")
        return base
            .appendingPathComponent("WhisperKit", isDirectory: true)
            .appendingPathComponent(remoteName, isDirectory: true)
    }

    func modelsExist(
        at directory: URL? = nil,
        fileManager: FileManager = .default
    ) -> Bool {
        let root = directory ?? defaultDirectoryURL
        return requiredPaths.allSatisfy { relativePath in
            let url = root.appendingPathComponent(relativePath, isDirectory: true)
            guard let enumerator = fileManager.enumerator(
                at: url,
                includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]
            ) else {
                return false
            }
            for case let fileURL as URL in enumerator {
                guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                      values.isRegularFile == true,
                      (values.fileSize ?? 0) > 0 else {
                    continue
                }
                return true
            }
            return false
        }
    }
}

struct WhisperKitModelDownloadProgress: Sendable, Equatable {
    let fractionCompleted: Double
    let status: String
}

protocol WhisperKitModelDownloading: Sendable {
    func download(
        variant: WhisperKitModelVariant,
        progress: @escaping @MainActor @Sendable (WhisperKitModelDownloadProgress) -> Void
    ) async throws -> URL
}

struct WhisperKitModelDownloader: WhisperKitModelDownloading, @unchecked Sendable {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func download(
        variant: WhisperKitModelVariant,
        progress: @escaping @MainActor @Sendable (WhisperKitModelDownloadProgress) -> Void
    ) async throws -> URL {
        let destination = variant.defaultDirectoryURL
        let modelsRoot = destination.deletingLastPathComponent()
        try fileManager.createDirectory(at: modelsRoot, withIntermediateDirectories: true)
        await progress(.init(fractionCompleted: 0, status: "下载 \(variant.remoteName)"))

        let downloaded = try await WhisperKit.download(
            variant: variant.remoteName,
            downloadBase: modelsRoot.appendingPathComponent(".downloads", isDirectory: true)
        ) { update in
            Task { @MainActor in
                progress(.init(
                    fractionCompleted: update.fractionCompleted,
                    status: "下载 Whisper 模型"
                ))
            }
        }
        guard variant.modelsExist(at: downloaded, fileManager: fileManager) else {
            throw ASREngineError.modelNotLoaded
        }

        let staging = modelsRoot.appendingPathComponent(
            ".\(variant.remoteName)-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? fileManager.removeItem(at: staging) }
        try fileManager.copyItem(at: downloaded, to: staging)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: staging, to: destination)
        await progress(.init(fractionCompleted: 1, status: "模型已就绪"))
        return destination
    }
}

protocol WhisperKitTranscribing: Sendable {
    func transcribe(audio: [Float]) async throws -> String
}

protocol WhisperKitTranscriberMaking: Sendable {
    func makeTranscriber(
        for variant: WhisperKitModelVariant,
        directoryURL: URL
    ) async throws -> any WhisperKitTranscribing
}

private enum WhisperKitTranscriberError: LocalizedError {
    case transcriptionFailed

    var errorDescription: String? {
        "Whisper 转写失败。"
    }
}

private actor LocalWhisperKitTranscriber: WhisperKitTranscribing {
    private let whisperKit: WhisperKit

    init(directoryURL: URL) async throws {
        whisperKit = try await WhisperKit(
            WhisperKitConfig(
                modelFolder: directoryURL.path,
                verbose: false,
                load: true,
                download: false
            )
        )
    }

    func transcribe(audio: [Float]) async throws -> String {
        let results = await whisperKit.transcribe(audioArrays: [audio])
        guard let first = results.first,
              let segments = first else {
            throw WhisperKitTranscriberError.transcriptionFailed
        }
        return segments.map(\.text).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct LocalWhisperKitTranscriberFactory: WhisperKitTranscriberMaking {
    func makeTranscriber(
        for variant: WhisperKitModelVariant,
        directoryURL: URL
    ) async throws -> any WhisperKitTranscribing {
        try await LocalWhisperKitTranscriber(directoryURL: directoryURL)
    }
}

private final class WhisperKitASRCallbackBox: @unchecked Sendable {
    var onTranscription: ((String, Bool) -> Void)?
    var onError: ((Error) -> Void)?
}

final class WhisperKitBatchASREngine: ASREngine, @unchecked Sendable {
    var onTranscription: ((String, Bool) -> Void)? {
        get { callbacks.onTranscription }
        set { callbacks.onTranscription = newValue }
    }
    var onError: ((Error) -> Void)? {
        get { callbacks.onError }
        set { callbacks.onError = newValue }
    }
    var isAvailable: Bool { isModelAvailable() }

    private let callbacks = WhisperKitASRCallbackBox()
    private let variant: WhisperKitModelVariant
    private let directoryURL: URL
    private let isModelAvailable: @Sendable () -> Bool
    private let transcriberFactory: any WhisperKitTranscriberMaking
    private var transcriberTask: Task<any WhisperKitTranscribing, Error>?
    private var audioSamples: [Float] = []
    private var isAcceptingAudio = false

    init(
        variant: WhisperKitModelVariant,
        directoryURL: URL? = nil,
        isModelAvailable: (@Sendable () -> Bool)? = nil,
        transcriberFactory: any WhisperKitTranscriberMaking = LocalWhisperKitTranscriberFactory()
    ) {
        let directory = directoryURL ?? variant.defaultDirectoryURL
        self.variant = variant
        self.directoryURL = directory
        self.transcriberFactory = transcriberFactory
        self.isModelAvailable = isModelAvailable ?? {
            variant.modelsExist(at: directory)
        }
    }

    func configure(locale: Locale) {}

    func start() throws {
        guard isAvailable else {
            throw ASREngineError.modelNotLoaded
        }
        audioSamples = []
        isAcceptingAudio = true
        let variant = variant
        let directoryURL = directoryURL
        let factory = transcriberFactory
        transcriberTask = Task {
            try await factory.makeTranscriber(for: variant, directoryURL: directoryURL)
        }
    }

    func appendAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard isAcceptingAudio,
              let samples = AudioPreprocessor.resampleTo16kHz(buffer) else {
            return
        }
        audioSamples.append(contentsOf: samples)
    }

    func endAudio() {
        isAcceptingAudio = false
        let samples = audioSamples
        let task = transcriberTask
        let callbacks = callbacks

        guard !samples.isEmpty else {
            callbacks.onTranscription?("", true)
            return
        }

        Task {
            do {
                guard let task else {
                    throw ASREngineError.modelNotLoaded
                }
                let transcriber = try await task.value
                let text = try await transcriber.transcribe(audio: samples)
                await MainActor.run {
                    callbacks.onTranscription?(text, true)
                }
            } catch {
                await MainActor.run {
                    callbacks.onError?(error)
                }
            }
        }
    }

    func stop() {
        isAcceptingAudio = false
        audioSamples = []
    }

    func cancel() {
        isAcceptingAudio = false
        audioSamples = []
        transcriberTask?.cancel()
        transcriberTask = nil
    }
}
