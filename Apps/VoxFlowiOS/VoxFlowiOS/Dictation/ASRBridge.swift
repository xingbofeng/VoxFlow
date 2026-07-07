import Foundation
import VoxFlowASRRuntime
import VoxFlowAudio

protocol ProviderEngineBuilding {
    func makeEngine(for provider: SelectedProvider, language: SelectedLanguage) throws -> ASREngine
}

struct DefaultProviderEngineBuilder: ProviderEngineBuilding {
    let credentialStore: LocalCredentialStore

    func makeEngine(for provider: SelectedProvider, language: SelectedLanguage) throws -> ASREngine {
        switch provider {
        case .appleSpeech:
            let adapter = AppleSpeechASREngineAdapter()
            adapter.configure(locale: language.locale)
            return adapter
        case .tencent:
            return try iOSASREngineFactory.makeTencentEngine(store: credentialStore)
        case .aliyun:
            return try iOSASREngineFactory.makeAliyunEngine(store: credentialStore)
        case .volcengine:
            return try iOSASREngineFactory.makeVolcengineEngine(store: credentialStore)
        }
    }
}

enum ASRBridgeError: LocalizedError, Equatable {
    case providerUnavailable

    var errorDescription: String? {
        switch self {
        case .providerUnavailable:
            return "Selected ASR provider is not available."
        }
    }
}

final class DictationASRBridge: @unchecked Sendable {
    private let engineBuilder: ProviderEngineBuilding
    private let lock = NSLock()
    private let audioQueue = DispatchQueue(label: "com.mashangxie.ios.dictation-asr-bridge")
    private var engine: ASREngine?

    init(engineBuilder: ProviderEngineBuilding) {
        self.engineBuilder = engineBuilder
    }

    var isRunning: Bool {
        lock.withLock { engine != nil }
    }

    func start(
        provider: SelectedProvider,
        language: SelectedLanguage,
        onTranscription: @escaping (String, Bool) -> Void,
        onError: @escaping (Error) -> Void
    ) throws {
        try prepare(
            provider: provider,
            language: language,
            onTranscription: onTranscription,
            onError: onError
        )
        try startPrepared()
    }

    func prepare(
        provider: SelectedProvider,
        language: SelectedLanguage,
        onTranscription: @escaping (String, Bool) -> Void,
        onError: @escaping (Error) -> Void
    ) throws {
        let engine = try engineBuilder.makeEngine(for: provider, language: language)
        guard engine.isAvailable else {
            throw ASRBridgeError.providerUnavailable
        }
        engine.onTranscription = onTranscription
        engine.onError = onError
        lock.withLock { self.engine = engine }
    }

    func startPrepared() throws {
        let currentEngine = lock.withLock { engine }
        try currentEngine?.start()
    }

    func appendAudioFrame(_ frame: AudioFrame) {
        audioQueue.async { [weak self] in
            guard let self else { return }
            let currentEngine = self.lock.withLock { self.engine }
            currentEngine?.appendAudioFrame(frame)
        }
    }

    func endAudio() {
        audioQueue.async { [weak self] in
            guard let self else { return }
            let currentEngine = self.lock.withLock { self.engine }
            currentEngine?.endAudio()
        }
    }

    func stop() {
        audioQueue.async { [weak self] in
            guard let self else { return }
            let currentEngine = self.lock.withLock { () -> ASREngine? in
                let current = self.engine
                self.engine = nil
                return current
            }
            currentEngine?.stop()
        }
    }

    func cancel() {
        audioQueue.async { [weak self] in
            guard let self else { return }
            let currentEngine = self.lock.withLock { () -> ASREngine? in
                let current = self.engine
                self.engine = nil
                return current
            }
            currentEngine?.cancel()
        }
    }
}
