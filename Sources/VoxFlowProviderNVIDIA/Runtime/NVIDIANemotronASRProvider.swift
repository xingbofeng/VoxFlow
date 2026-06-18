import Foundation
import VoxFlowASRCore

public enum NVIDIANemotronASRProvider: VoxFlowASRCore.ASRProvider {
    case live(
        descriptor: VoxFlowASRCore.ASRProviderDescriptor,
        modelURL: URL?,
        transcriberFactory: any NVIDIANemotronTranscriberMaking = NVIDIANemotronTranscriberFactory()
    )

    public var descriptor: VoxFlowASRCore.ASRProviderDescriptor {
        switch self {
        case .live(let descriptor, _, _):
            return descriptor
        }
    }

    public func install() async throws {
        throw NVIDIANemotronProviderError.preparationFailed("NVIDIA Nemotron model installation is managed by ModelStore.")
    }

    public func delete() async throws {
        throw NVIDIANemotronProviderError.preparationFailed("NVIDIA Nemotron model deletion is managed by ModelStore.")
    }

    public func prepare() async throws {
        try Self.throwIfUnavailable(descriptor.modelInstallationState)
        switch self {
        case .live(_, let modelURL, _):
            guard modelURL != nil else {
                throw NVIDIANemotronProviderError.modelNotInstalled
            }
        }
    }

    public func healthCheck() async -> VoxFlowASRCore.ASRProviderHealth {
        do {
            try await prepare()
            return .healthy
        } catch {
            return .unhealthy(Self.asrError(for: error))
        }
    }

    public func makeSession(
        language: VoxFlowASRCore.ASRLanguageCapability
    ) async throws -> any VoxFlowASRCore.ASRSession {
        try await prepare()
        guard let languageCode = NVIDIANemotronLanguageMapper.languageCode(for: language) else {
            throw NVIDIANemotronProviderError.unsupportedLanguage(language.bcp47Tag)
        }
        switch self {
        case .live(_, let modelURL, let transcriberFactory):
            guard let modelURL else {
                throw NVIDIANemotronProviderError.modelNotInstalled
            }
            return NVIDIANemotronASRSession(
                sessionID: VoxFlowASRCore.ASRSessionID(rawValue: "nvidia-nemotron-\(UUID().uuidString)"),
                modelURL: modelURL,
                languageCode: languageCode,
                transcriberFactory: transcriberFactory
            )
        }
    }

    private static func throwIfUnavailable(_ state: VoxFlowASRCore.ASRModelInstallationState) throws {
        switch state {
        case .ready:
            return
        case .runtimeUnsupported(let reason),
             .hardwareUnsupported(let reason):
            throw NVIDIANemotronProviderError.runtimeUnsupported(reason: reason)
        case .failed(let message):
            throw NVIDIANemotronProviderError.preparationFailed(message)
        case .notInstalled, .downloading, .verifying, .compiling, .prewarming, .corrupt:
            throw NVIDIANemotronProviderError.modelNotInstalled
        }
    }

    static func asrError(for error: Error) -> VoxFlowASRCore.ASRError {
        if let providerError = error as? NVIDIANemotronProviderError {
            switch providerError {
            case .modelNotInstalled:
                return VoxFlowASRCore.ASRError(category: .modelNotInstalled, message: providerError.localizedDescription)
            case .runtimeUnsupported:
                return VoxFlowASRCore.ASRError(category: .runtimeUnsupported, message: providerError.localizedDescription)
            case .unsupportedLanguage:
                return VoxFlowASRCore.ASRError(category: .unsupportedLanguage, message: providerError.localizedDescription)
            case .preparationFailed:
                return VoxFlowASRCore.ASRError(category: .preparationFailed, message: providerError.localizedDescription)
            case .emptyTranscript:
                return VoxFlowASRCore.ASRError(category: .emptyTranscript, message: providerError.localizedDescription)
            }
        }
        return VoxFlowASRCore.ASRError(category: .preparationFailed, message: error.localizedDescription)
    }
}

public enum NVIDIANemotronLanguageMapper {
    public static func languageCode(for language: VoxFlowASRCore.ASRLanguageCapability) -> String? {
        let tag = language.bcp47Tag.lowercased()
        if tag.hasPrefix("zh") {
            return "zh-CN"
        }
        if tag.hasPrefix("en") {
            return "en-US"
        }
        if tag.hasPrefix("ja") {
            return "ja-JP"
        }
        if tag.hasPrefix("ko") {
            return "ko-KR"
        }
        return nil
    }
}
