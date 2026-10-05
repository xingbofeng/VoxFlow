import Foundation
import VoxFlowASRCore

public enum FireRedASRProviderError: Error, Equatable, Sendable, LocalizedError {
    case modelNotInstalled
    case unsupportedLanguage(String)
    case preparationFailed(String)
    case emptyTranscript

    public var errorDescription: String? {
        switch self {
        case .modelNotInstalled:
            return "FireRedASR2-AED model is not installed."
        case .unsupportedLanguage(let languageTag):
            return "FireRedASR2-AED does not support language \(languageTag)."
        case .preparationFailed(let reason):
            return reason
        case .emptyTranscript:
            return "FireRedASR2-AED final result was empty."
        }
    }
}

public struct FireRedASRASRProvider: VoxFlowASRCore.ASRProvider {
    public let descriptor: VoxFlowASRCore.ASRProviderDescriptor

    private let modelURL: URL?
    private let transcriberFactory: any FireRedASRTranscriberMaking
    private let segmentationObserver: (@Sendable (FireRedASRSegmentationReport) -> Void)?

    public init(
        descriptor: VoxFlowASRCore.ASRProviderDescriptor,
        modelURL: URL?,
        transcriberFactory: any FireRedASRTranscriberMaking = FireRedASRTranscriberFactory(),
        segmentationObserver: (@Sendable (FireRedASRSegmentationReport) -> Void)? = nil
    ) {
        self.descriptor = descriptor
        self.modelURL = modelURL
        self.transcriberFactory = transcriberFactory
        self.segmentationObserver = segmentationObserver
    }

    public func install() async throws {
        throw FireRedASRProviderError.preparationFailed(
            "FireRedASR2-AED model installation is managed by ModelStore."
        )
    }

    public func delete() async throws {
        throw FireRedASRProviderError.preparationFailed(
            "FireRedASR2-AED model deletion is managed by ModelStore."
        )
    }

    public func prepare() async throws {
        try Self.throwIfUnavailable(descriptor.modelInstallationState)
        guard modelURL != nil else {
            throw FireRedASRProviderError.modelNotInstalled
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
            throw FireRedASRProviderError.modelNotInstalled
        }
        guard FireRedASRLanguageMapper.supports(language: language) else {
            throw FireRedASRProviderError.unsupportedLanguage(language.bcp47Tag)
        }
        return FireRedASRASRSession(
            sessionID: VoxFlowASRCore.ASRSessionID(rawValue: "fireredasr-\(UUID().uuidString)"),
            modelURL: modelURL,
            transcriberFactory: transcriberFactory,
            segmentationObserver: segmentationObserver
        )
    }

    private static func throwIfUnavailable(_ state: VoxFlowASRCore.ASRModelInstallationState) throws {
        switch state {
        case .ready:
            return
        case .failed(let message),
             .runtimeUnsupported(let message),
             .hardwareUnsupported(let message):
            throw FireRedASRProviderError.preparationFailed(message)
        case .notInstalled, .downloading, .verifying, .compiling, .prewarming, .corrupt:
            throw FireRedASRProviderError.modelNotInstalled
        }
    }

    static func asrError(for error: Error) -> VoxFlowASRCore.ASRError {
        if let providerError = error as? FireRedASRProviderError {
            switch providerError {
            case .modelNotInstalled:
                return VoxFlowASRCore.ASRError(
                    category: .modelNotInstalled,
                    message: providerError.localizedDescription
                )
            case .unsupportedLanguage:
                return VoxFlowASRCore.ASRError(
                    category: .unsupportedLanguage,
                    message: providerError.localizedDescription
                )
            case .preparationFailed:
                return VoxFlowASRCore.ASRError(
                    category: .preparationFailed,
                    message: providerError.localizedDescription
                )
            case .emptyTranscript:
                return VoxFlowASRCore.ASRError(
                    category: .emptyTranscript,
                    message: providerError.localizedDescription
                )
            }
        }
        return VoxFlowASRCore.ASRError(
            category: .preparationFailed,
            message: error.localizedDescription
        )
    }
}

public enum FireRedASRLanguageMapper {
    /// FireRedASR2-AED 是中文优先模型；官方评测与文档聚焦中文与中文方言，英文是次要能力。
    /// `en` 保留是因为中英混说能出结果，但产品文案不得承诺英文质量。
    public static func supports(language: VoxFlowASRCore.ASRLanguageCapability) -> Bool {
        let tag = language.bcp47Tag.lowercased()
        return tag.hasPrefix("zh") || tag.hasPrefix("en")
    }
}
