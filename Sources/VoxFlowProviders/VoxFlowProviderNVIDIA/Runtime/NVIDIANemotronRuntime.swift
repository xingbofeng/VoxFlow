import Foundation
import NemotronStreamingASR

public protocol NVIDIANemotronTranscribing: Sendable {
    func setPartialHandler(_ handler: @escaping @Sendable (String) -> Void) async
    func setWordBoostingPhrases(_ phrases: [String]) async
    func setLanguage(_ languageCode: String?) async
    func accept(audio: [Float]) async throws -> String
    func finish() async throws -> String
    func cancel() async
}

public protocol NVIDIANemotronTranscriberMaking: Sendable {
    func makeTranscriber(directoryURL: URL) async throws -> any NVIDIANemotronTranscribing
}

private actor NVIDIANemotronSpeechSwiftTranscriber: NVIDIANemotronTranscribing {
    private let model: NemotronStreamingASRModel
    private var session: StreamingSession?
    private var languageCode: String?
    private var wordBoostingPhrases: [String] = []
    private var partialHandler: (@Sendable (String) -> Void)?

    init(model: NemotronStreamingASRModel) {
        self.model = model
    }

    func setPartialHandler(_ handler: @escaping @Sendable (String) -> Void) async {
        partialHandler = handler
    }

    func setWordBoostingPhrases(_ phrases: [String]) async {
        wordBoostingPhrases = phrases
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        session = nil
    }

    func setLanguage(_ languageCode: String?) async {
        self.languageCode = languageCode
        session = try? model.createSession(
            language: languageCode,
            wordBoosting: wordBoostingConfig()
        )
    }

    func accept(audio: [Float]) async throws -> String {
        let activeSession = try ensureSession()
        let partials = try activeSession.pushAudio(audio)
        guard let latest = partials.last else { return "" }
        if !latest.text.isEmpty {
            partialHandler?(latest.text)
        }
        return latest.text
    }

    func finish() async throws -> String {
        let finals = try ensureSession().finalize()
        let finalText = finals.last(where: \.isFinal)?.text ?? finals.last?.text ?? ""
        if !finalText.isEmpty {
            partialHandler?(finalText)
        }
        return finalText
    }

    func cancel() async {
        session = nil
    }

    private func ensureSession() throws -> StreamingSession {
        if let session {
            return session
        }
        let created = try model.createSession(
            language: languageCode,
            wordBoosting: wordBoostingConfig()
        )
        session = created
        return created
    }

    private func wordBoostingConfig() -> WordBoostingConfig? {
        wordBoostingPhrases.isEmpty ? nil : WordBoostingConfig(phrases: wordBoostingPhrases)
    }
}

public struct NVIDIANemotronTranscriberFactory: NVIDIANemotronTranscriberMaking {
    public init() {}

    public func makeTranscriber(directoryURL: URL) async throws -> any NVIDIANemotronTranscribing {
        guard NVIDIANemotronModel.modelsExist(at: directoryURL) else {
            throw NVIDIANemotronProviderError.modelNotInstalled
        }
        let model = try await NemotronStreamingASRModel.fromLocal(bundleDir: directoryURL)
        return NVIDIANemotronSpeechSwiftTranscriber(model: model)
    }
}
