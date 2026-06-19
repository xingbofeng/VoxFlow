import Foundation
import VoxFlowASRCore

public enum ParakeetProviderError: Error, Equatable, Sendable, LocalizedError {
    case modelNotInstalled
    case unsupportedLanguage(String)
    case preparationFailed(String)
    case emptyTranscript

    public var errorDescription: String? {
        switch self {
        case .modelNotInstalled:
            return "Parakeet model is not installed."
        case .unsupportedLanguage(let languageTag):
            return "Parakeet does not support language \(languageTag)."
        case .preparationFailed(let reason):
            return reason
        case .emptyTranscript:
            return "Parakeet final result was empty."
        }
    }
}

public struct ParakeetASRProvider: VoxFlowASRCore.ASRProvider {
    public let descriptor: VoxFlowASRCore.ASRProviderDescriptor

    private let modelURL: URL?
    private let transcriberFactory: any ParakeetTranscriberMaking

    public init(
        descriptor: VoxFlowASRCore.ASRProviderDescriptor,
        modelURL: URL?,
        transcriberFactory: any ParakeetTranscriberMaking = ParakeetTranscriberFactory()
    ) {
        self.descriptor = descriptor
        self.modelURL = modelURL
        self.transcriberFactory = transcriberFactory
    }

    public func install() async throws {
        throw ParakeetProviderError.preparationFailed("Parakeet model installation is managed by ModelStore.")
    }

    public func delete() async throws {
        throw ParakeetProviderError.preparationFailed("Parakeet model deletion is managed by ModelStore.")
    }

    public func prepare() async throws {
        try Self.throwIfUnavailable(descriptor.modelInstallationState)
        guard modelURL != nil else {
            throw ParakeetProviderError.modelNotInstalled
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
            throw ParakeetProviderError.modelNotInstalled
        }
        guard ParakeetLanguageMapper.supports(language: language) else {
            throw ParakeetProviderError.unsupportedLanguage(language.bcp47Tag)
        }
        return ParakeetASRSession(
            sessionID: VoxFlowASRCore.ASRSessionID(rawValue: "parakeet-\(UUID().uuidString)"),
            modelURL: modelURL,
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
            throw ParakeetProviderError.preparationFailed(message)
        case .notInstalled, .downloading, .verifying, .compiling, .prewarming, .corrupt:
            throw ParakeetProviderError.modelNotInstalled
        }
    }

    static func asrError(for error: Error) -> VoxFlowASRCore.ASRError {
        if let providerError = error as? ParakeetProviderError {
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

public enum ParakeetLanguageMapper {
    public static func supports(language: VoxFlowASRCore.ASRLanguageCapability) -> Bool {
        let tag = language.bcp47Tag.lowercased()
        return ["en", "de", "fr", "es", "it", "pt", "nl", "pl"].contains {
            tag.hasPrefix($0)
        }
    }
}
