import Foundation
import VoxFlowASRCore
import VoxFlowAudio

public enum WhisperProviderError: Error, Equatable, Sendable, LocalizedError {
    case modelNotInstalled
    case runtimeUnsupported(String)
    case unsupportedLanguage(String)
    case preparationFailed(String)
    case emptyTranscript

    public var errorDescription: String? {
        switch self {
        case .modelNotInstalled:
            return "Whisper model is not installed."
        case .runtimeUnsupported(let reason),
             .preparationFailed(let reason):
            return reason
        case .unsupportedLanguage(let languageTag):
            return "Whisper does not support language \(languageTag)."
        case .emptyTranscript:
            return "Whisper final result was empty."
        }
    }
}

public struct WhisperASRProvider: VoxFlowASRCore.ASRProvider {
    public let descriptor: VoxFlowASRCore.ASRProviderDescriptor

    private let variant: WhisperKitModelVariant
    private let modelURL: URL?
    private let transcriberFactory: any WhisperKitTranscriberMaking

    public init(
        descriptor: VoxFlowASRCore.ASRProviderDescriptor,
        variant: WhisperKitModelVariant,
        modelURL: URL?,
        transcriberFactory: any WhisperKitTranscriberMaking = LocalWhisperKitTranscriberFactory()
    ) {
        self.descriptor = descriptor
        self.variant = variant
        self.modelURL = modelURL
        self.transcriberFactory = transcriberFactory
    }

    public func install() async throws {
        throw WhisperProviderError.preparationFailed("Whisper model installation is managed by the app model downloader during migration.")
    }

    public func delete() async throws {
        throw WhisperProviderError.preparationFailed("Whisper model deletion is managed by the app model downloader during migration.")
    }

    public func prepare() async throws {
        try Self.throwIfUnavailable(descriptor.modelInstallationState)
        guard modelURL != nil else {
            throw WhisperProviderError.modelNotInstalled
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
            throw WhisperProviderError.modelNotInstalled
        }
        guard let languageCode = WhisperLanguageMapper.languageCode(for: language) else {
            throw WhisperProviderError.unsupportedLanguage(language.bcp47Tag)
        }
        return WhisperASRSession(
            sessionID: VoxFlowASRCore.ASRSessionID(rawValue: "whisper-\(UUID().uuidString)"),
            variant: variant,
            modelURL: modelURL,
            languageCode: languageCode,
            transcriberFactory: transcriberFactory
        )
    }

    private static func throwIfUnavailable(_ state: VoxFlowASRCore.ASRModelInstallationState) throws {
        switch state {
        case .ready:
            return
        case .runtimeUnsupported(let reason):
            throw WhisperProviderError.runtimeUnsupported(reason)
        case .hardwareUnsupported(let reason):
            throw WhisperProviderError.runtimeUnsupported(reason)
        case .failed(let message):
            throw WhisperProviderError.preparationFailed(message)
        case .notInstalled, .downloading, .verifying, .compiling, .prewarming, .corrupt:
            throw WhisperProviderError.modelNotInstalled
        }
    }

    private static func asrError(for error: Error) -> VoxFlowASRCore.ASRError {
        if let providerError = error as? WhisperProviderError {
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

public enum WhisperLanguageMapper {
    public static func supports(language: VoxFlowASRCore.ASRLanguageCapability) -> Bool {
        languageCode(for: language) != nil
    }

    public static func languageCode(for language: VoxFlowASRCore.ASRLanguageCapability) -> String? {
        let tag = language.bcp47Tag.lowercased()
        if tag.hasPrefix("zh") {
            return "zh"
        }
        if tag.hasPrefix("en") {
            return "en"
        }
        if tag.hasPrefix("ja") {
            return "ja"
        }
        if tag.hasPrefix("ko") {
            return "ko"
        }
        return nil
    }
}
