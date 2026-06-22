import AVFoundation
import Foundation
import VoxFlowAudio

protocol SherpaASRTranscribing: Sendable {
    func transcribe(audio: [Float]) async throws -> String
}

protocol SherpaASRTranscriberMaking: Sendable {
    func makeTranscriber(
        for variant: SherpaASRModelVariant,
        directoryURL: URL
    ) async throws -> any SherpaASRTranscribing
}

private struct SherpaOnnxTranscriber: SherpaASRTranscribing {
    let recognizer: SherpaOnnxRecognizer

    func transcribe(audio: [Float]) async throws -> String {
        try recognizer.transcribe(samples: audio)
    }
}

struct SherpaASRTranscriberFactory: SherpaASRTranscriberMaking {
    func makeTranscriber(
        for variant: SherpaASRModelVariant,
        directoryURL: URL
    ) async throws -> any SherpaASRTranscribing {
        try SherpaOnnxTranscriber(
            recognizer: SherpaOnnxRecognizer(variant: variant, directoryURL: directoryURL)
        )
    }
}

private final class SherpaASRCallbackBox: @unchecked Sendable {
    var onTranscription: ((String, Bool) -> Void)?
    var onError: ((Error) -> Void)?
}

final class SherpaBatchASREngine: ASREngine, @unchecked Sendable {
    var onTranscription: ((String, Bool) -> Void)? {
        get { callbacks.onTranscription }
        set { callbacks.onTranscription = newValue }
    }
    var onError: ((Error) -> Void)? {
        get { callbacks.onError }
        set { callbacks.onError = newValue }
    }
    var isAvailable: Bool { isModelAvailable() }

    private let callbacks = SherpaASRCallbackBox()
    private let variant: SherpaASRModelVariant
    private let directoryURL: URL
    private let isModelAvailable: @Sendable () -> Bool
    private let transcriberFactory: any SherpaASRTranscriberMaking
    private var transcriberTask: Task<any SherpaASRTranscribing, Error>?
    private var audioSamples: [Float] = []
    private var isAcceptingAudio = false

    init(
        variant: SherpaASRModelVariant,
        directoryURL: URL? = nil,
        isModelAvailable: (@Sendable () -> Bool)? = nil,
        transcriberFactory: any SherpaASRTranscriberMaking = SherpaASRTranscriberFactory()
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
        AppLogger.audio.debug("SherpaBatchASREngine start variant=\(variant.rawValue)")
        guard isAvailable else {
            AppLogger.audio.warning("SherpaBatchASREngine start blocked: model not loaded variant=\(variant.rawValue)")
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

    func appendAudioFrame(_ frame: AudioFrame) {
        guard isAcceptingAudio else {
            AppLogger.audio.debug("SherpaBatchASREngine append dropped: not accepting audio")
            return
        }
        AppLogger.audio.debug("SherpaBatchASREngine append frameCount=\(frame.samples.count)")
        audioSamples.append(contentsOf: frame.samples)
    }

    func endAudio() {
        AppLogger.audio.debug("SherpaBatchASREngine endAudio sampleCount=\(audioSamples.count)")
        isAcceptingAudio = false
        let samples = audioSamples
        let task = transcriberTask
        let callbacks = callbacks

        guard !samples.isEmpty else {
            AppLogger.audio.info("SherpaBatchASREngine empty input, emit empty transcript")
            callbacks.onTranscription?("", true)
            return
        }

        Task {
            do {
                guard let task else {
                    AppLogger.audio.error("SherpaBatchASREngine endAudio missing transcriber task")
                    throw ASREngineError.modelNotLoaded
                }
                let transcriber = try await task.value
                AppLogger.audio.debug("SherpaBatchASREngine transcriber ready variant=\(variant.rawValue)")
                let text = try await transcriber.transcribe(audio: samples)
                AppLogger.audio.info("SherpaBatchASREngine transcribed variant=\(variant.rawValue) len=\(text.count)")
                await MainActor.run {
                    callbacks.onTranscription?(text, true)
                }
            } catch {
                AppLogger.audio.warning(
                    "SherpaBatchASREngine transcribe failed variant=\(variant.rawValue), reason=\(error.localizedDescription)"
                )
                await MainActor.run {
                    callbacks.onError?(error)
                }
            }
        }
    }

    func stop() {
        AppLogger.audio.debug("SherpaBatchASREngine stop")
        isAcceptingAudio = false
        audioSamples = []
    }

    func cancel() {
        AppLogger.audio.debug("SherpaBatchASREngine cancel")
        isAcceptingAudio = false
        audioSamples = []
        transcriberTask?.cancel()
        transcriberTask = nil
    }
}
