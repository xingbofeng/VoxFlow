import FluidAudio
import Foundation

public protocol NVIDIANemotronTranscribing: Sendable {
    func setPartialHandler(_ handler: @escaping @Sendable (String) -> Void) async
    func setLanguage(_ languageCode: String?) async
    func accept(audio: [Float]) async throws -> String
    func finish() async throws -> String
    func cancel() async
}

public protocol NVIDIANemotronTranscriberMaking: Sendable {
    func makeTranscriber(directoryURL: URL) async throws -> any NVIDIANemotronTranscribing
}

private actor NVIDIANemotronManagerTranscriber: NVIDIANemotronTranscribing {
    private let manager: StreamingNemotronMultilingualAsrManager

    init(manager: StreamingNemotronMultilingualAsrManager) {
        self.manager = manager
    }

    func setPartialHandler(_ handler: @escaping @Sendable (String) -> Void) async {
        await manager.setPartialCallback(handler)
    }

    func setLanguage(_ languageCode: String?) async {
        await manager.setLanguage(languageCode)
        await manager.setForcedPrefix(true)
    }

    func accept(audio: [Float]) async throws -> String {
        try await manager.process(samples: audio)
    }

    func finish() async throws -> String {
        try await manager.finish()
    }

    func cancel() async {
        await manager.reset()
    }
}

public struct NVIDIANemotronTranscriberFactory: NVIDIANemotronTranscriberMaking {
    public init() {}

    public func makeTranscriber(directoryURL: URL) async throws -> any NVIDIANemotronTranscribing {
        guard NVIDIANemotronModel.modelsExist(at: directoryURL) else {
            throw NVIDIANemotronProviderError.modelNotInstalled
        }
        let manager = StreamingNemotronMultilingualAsrManager()
        try await manager.loadModels(from: directoryURL)
        return NVIDIANemotronManagerTranscriber(manager: manager)
    }
}
