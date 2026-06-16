import AVFoundation
@preconcurrency import CoreML
import FluidAudio
import Foundation

enum FluidAudioLocalASRModel: Sendable {
    case paraformer
    case senseVoice

    var precision: SenseVoiceEncoderPrecision? {
        switch self {
        case .paraformer:
            nil
        case .senseVoice:
            .fp16
        }
    }

    var directoryURL: URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        let folderName = switch self {
        case .paraformer: Repo.paraformerLargeZh.folderName
        case .senseVoice: Repo.senseVoiceSmall.folderName
        }
        return base
            .appendingPathComponent("FluidAudio", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent(folderName, isDirectory: true)
    }
}

protocol LocalASRTranscribing: Sendable {
    func transcribe(audio: [Float]) async throws -> String
}

protocol LocalASRTranscriberMaking: Sendable {
    func makeTranscriber(for model: FluidAudioLocalASRModel) async throws -> any LocalASRTranscribing
}

struct FluidAudioLocalASRTranscriberFactory: LocalASRTranscriberMaking {
    func makeTranscriber(for model: FluidAudioLocalASRModel) async throws -> any LocalASRTranscribing {
        switch model {
        case .paraformer:
            let models = try ParaformerModels.load(from: model.directoryURL, precision: .int8)
            return ParaformerTranscriber(manager: ParaformerManager(models: models))
        case .senseVoice:
            let models = try SenseVoiceModels.load(from: model.directoryURL, precision: model.precision ?? .fp32)
            return SenseVoiceManagerTranscriber(manager: SenseVoiceManager(models: models))
        }
    }
}

private struct ParaformerTranscriber: LocalASRTranscribing {
    let manager: ParaformerManager

    func transcribe(audio: [Float]) async throws -> String {
        try await manager.transcribe(audio: audio)
    }
}

private struct SenseVoiceManagerTranscriber: LocalASRTranscribing {
    let manager: SenseVoiceManager

    func transcribe(audio: [Float]) async throws -> String {
        try await manager.transcribe(audio: audio)
    }
}

private final class LocalASRCallbackBox: @unchecked Sendable {
    var onTranscription: ((String, Bool) -> Void)?
    var onError: ((Error) -> Void)?
}

final class FluidAudioBatchASREngine: ASREngine, @unchecked Sendable {
    var onTranscription: ((String, Bool) -> Void)? {
        get { callbacks.onTranscription }
        set { callbacks.onTranscription = newValue }
    }
    var onError: ((Error) -> Void)? {
        get { callbacks.onError }
        set { callbacks.onError = newValue }
    }
    var isAvailable: Bool { isModelAvailable() }

    private let callbacks = LocalASRCallbackBox()
    private let model: FluidAudioLocalASRModel
    private let isModelAvailable: @Sendable () -> Bool
    private let transcriberFactory: any LocalASRTranscriberMaking
    private var transcriberTask: Task<any LocalASRTranscribing, Error>?
    private var audioSamples: [Float] = []
    private var isAcceptingAudio = false

    init(
        model: FluidAudioLocalASRModel,
        isModelAvailable: (@Sendable () -> Bool)? = nil,
        transcriberFactory: any LocalASRTranscriberMaking = FluidAudioLocalASRTranscriberFactory()
    ) {
        self.model = model
        self.transcriberFactory = transcriberFactory
        self.isModelAvailable = isModelAvailable ?? {
            switch model {
            case .paraformer:
                ParaformerModels.modelsExist(at: model.directoryURL, precision: .int8)
            case .senseVoice:
                SenseVoiceModels.modelsExist(at: model.directoryURL, precision: model.precision ?? .fp32)
            }
        }
    }

    func configure(locale: Locale) {}

    func start() throws {
        guard isAvailable else {
            throw ASREngineError.modelNotLoaded
        }
        audioSamples = []
        isAcceptingAudio = true
        let model = model
        let factory = transcriberFactory
        transcriberTask = Task {
            try await factory.makeTranscriber(for: model)
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
