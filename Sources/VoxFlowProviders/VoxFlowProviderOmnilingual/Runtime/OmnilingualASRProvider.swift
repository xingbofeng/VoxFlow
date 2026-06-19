import Foundation
import VoxFlowASRCore

public enum OmnilingualProviderError: Error, Equatable, Sendable, LocalizedError {
    case modelNotInstalled
    case unsupportedLanguage(String)
    case preparationFailed(String)
    case emptyTranscript

    public var errorDescription: String? {
        switch self {
        case .modelNotInstalled:
            return "Omnilingual ASR model is not installed."
        case .unsupportedLanguage(let languageTag):
            return "Omnilingual ASR does not support language \(languageTag)."
        case .preparationFailed(let reason):
            return reason
        case .emptyTranscript:
            return "Omnilingual ASR final result was empty."
        }
    }
}

public struct OmnilingualASRProvider: VoxFlowASRCore.ASRProvider {
    public let descriptor: VoxFlowASRCore.ASRProviderDescriptor

    private let modelURL: URL?
    private let transcriberFactory: any OmnilingualTranscriberMaking

    public init(
        descriptor: VoxFlowASRCore.ASRProviderDescriptor,
        modelURL: URL?,
        transcriberFactory: any OmnilingualTranscriberMaking = OmnilingualTranscriberFactory()
    ) {
        self.descriptor = descriptor
        self.modelURL = modelURL
        self.transcriberFactory = transcriberFactory
    }

    public func install() async throws {
        throw OmnilingualProviderError.preparationFailed("Omnilingual model installation is managed by ModelStore.")
    }

    public func delete() async throws {
        throw OmnilingualProviderError.preparationFailed("Omnilingual model deletion is managed by ModelStore.")
    }

    public func prepare() async throws {
        try Self.throwIfUnavailable(descriptor.modelInstallationState)
        guard modelURL != nil else {
            throw OmnilingualProviderError.modelNotInstalled
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
        guard let modelURL else {
            throw OmnilingualProviderError.modelNotInstalled
        }
        guard OmnilingualLanguageMapper.supports(language: language) else {
            throw OmnilingualProviderError.unsupportedLanguage(language.bcp47Tag)
        }
        return OmnilingualASRSession(
            sessionID: VoxFlowASRCore.ASRSessionID(rawValue: "omnilingual-\(UUID().uuidString)"),
            modelURL: modelURL,
            languageCode: language.bcp47Tag,
            transcriberFactory: transcriberFactory
        )
    }

    private static func throwIfUnavailable(_ state: VoxFlowASRCore.ASRModelInstallationState) throws {
        switch state {
        case .ready:
            return
        case .failed(let message),
             .runtimeUnsupported(let message),
             .hardwareUnsupported(let message):
            throw OmnilingualProviderError.preparationFailed(message)
        case .notInstalled, .downloading, .verifying, .compiling, .prewarming, .corrupt:
            throw OmnilingualProviderError.modelNotInstalled
        }
    }

    static func asrError(for error: Error) -> VoxFlowASRCore.ASRError {
        if let providerError = error as? OmnilingualProviderError {
            switch providerError {
            case .modelNotInstalled:
                return VoxFlowASRCore.ASRError(category: .modelNotInstalled, message: providerError.localizedDescription)
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

public enum OmnilingualLanguageMapper {
    public static func supports(language: VoxFlowASRCore.ASRLanguageCapability) -> Bool {
        !language.bcp47Tag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
