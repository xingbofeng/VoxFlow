import Foundation
import VoxFlowASRCore

public enum Qwen3ProviderError: Error, Equatable, Sendable, LocalizedError {
    case modelNotInstalled
    case modelCorrupt
    case runtimeUnsupported(String)
    case hardwareUnsupported(String)
    case unsupportedLanguage(String)
    case preparationFailed(String)
    case unsupportedOS

    public var errorDescription: String? {
        switch self {
        case .modelNotInstalled:
            return "Qwen3-ASR model is not installed."
        case .modelCorrupt:
            return "Qwen3-ASR model is corrupt."
        case .runtimeUnsupported(let reason),
             .hardwareUnsupported(let reason),
             .preparationFailed(let reason):
            return reason
        case .unsupportedLanguage(let languageTag):
            return "Qwen3-ASR does not support language \(languageTag)."
        case .unsupportedOS:
            return "Qwen3-ASR requires macOS 15 or later."
        }
    }
}

public struct Qwen3ASRProvider: VoxFlowASRCore.ASRProvider {
    public let descriptor: VoxFlowASRCore.ASRProviderDescriptor

    private let modelURL: URL?
    private let sessionFactory: any Qwen3StreamingSessionMaking

    public init(
        descriptor: VoxFlowASRCore.ASRProviderDescriptor,
        modelURL: URL?,
        sessionFactory: any Qwen3StreamingSessionMaking = FluidAudioQwen3StreamingSessionFactory()
    ) {
        self.descriptor = descriptor
        self.modelURL = modelURL
        self.sessionFactory = sessionFactory
    }

    public func install() async throws {
        throw Qwen3ProviderError.preparationFailed("Qwen3 model installation is managed by ModelStore.")
    }

    public func delete() async throws {
        throw Qwen3ProviderError.preparationFailed("Qwen3 model deletion is managed by ModelStore.")
    }

    public func prepare() async throws {
        try Self.throwIfUnavailable(descriptor.modelInstallationState)
        guard modelURL != nil else {
            throw Qwen3ProviderError.modelNotInstalled
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
            throw Qwen3ProviderError.modelNotInstalled
        }
        return Qwen3ASRSession(
            sessionID: VoxFlowASRCore.ASRSessionID(rawValue: "qwen3-asr-\(UUID().uuidString)"),
            modelURL: modelURL,
            languageHint: Qwen3LanguageMapper.languageHint(for: language),
            sessionFactory: sessionFactory,
            timeoutPolicy: descriptor.timeoutPolicy
        )
    }

    private static func throwIfUnavailable(_ state: VoxFlowASRCore.ASRModelInstallationState) throws {
        switch state {
        case .ready:
            return
        case .notInstalled, .downloading, .verifying, .compiling, .prewarming:
            throw Qwen3ProviderError.modelNotInstalled
        case .corrupt:
            throw Qwen3ProviderError.modelCorrupt
        case .runtimeUnsupported(let reason):
            throw Qwen3ProviderError.runtimeUnsupported(reason)
        case .hardwareUnsupported(let reason):
            throw Qwen3ProviderError.hardwareUnsupported(reason)
        case .failed(let message):
            throw Qwen3ProviderError.preparationFailed(message)
        }
    }

    private static func asrError(for error: Error) -> VoxFlowASRCore.ASRError {
        if let providerError = error as? Qwen3ProviderError {
            switch providerError {
            case .modelNotInstalled:
                return VoxFlowASRCore.ASRError(category: .modelNotInstalled, message: providerError.localizedDescription)
            case .modelCorrupt:
                return VoxFlowASRCore.ASRError(category: .modelCorrupt, message: providerError.localizedDescription)
            case .runtimeUnsupported, .unsupportedOS:
                return VoxFlowASRCore.ASRError(category: .runtimeUnsupported, message: providerError.localizedDescription)
            case .hardwareUnsupported:
                return VoxFlowASRCore.ASRError(category: .hardwareUnsupported, message: providerError.localizedDescription)
            case .unsupportedLanguage:
                return VoxFlowASRCore.ASRError(category: .unsupportedLanguage, message: providerError.localizedDescription)
            case .preparationFailed:
                return VoxFlowASRCore.ASRError(category: .preparationFailed, message: providerError.localizedDescription)
            }
        }
        return VoxFlowASRCore.ASRError(category: .preparationFailed, message: error.localizedDescription)
    }
}
