import Foundation
import VoxFlowASRCore

public struct R2T2ASRProvider: VoxFlowASRCore.ASRProvider {
    public let descriptor: VoxFlowASRCore.ASRProviderDescriptor

    private let modelURL: URL?
    private let streamFactory: any R2T2StreamMaking

    public init(
        descriptor: VoxFlowASRCore.ASRProviderDescriptor,
        modelURL: URL?,
        streamFactory: any R2T2StreamMaking = VendoredR2T2StreamFactory()
    ) {
        self.descriptor = descriptor
        self.modelURL = modelURL
        self.streamFactory = streamFactory
    }

    public func install() async throws {
        throw R2T2ProviderError.preparationFailed(
            "Confucius4-R2T2 model installation is managed by ModelStore."
        )
    }

    public func delete() async throws {
        throw R2T2ProviderError.preparationFailed(
            "Confucius4-R2T2 model deletion is managed by ModelStore."
        )
    }

    public func prepare() async throws {
        try Self.throwIfUnavailable(descriptor.modelInstallationState)
        guard modelURL != nil else {
            throw R2T2ProviderError.modelNotInstalled
        }
    }

    public func healthCheck() async -> VoxFlowASRCore.ASRProviderHealth {
        do {
            try await prepare()
            return .healthy
        } catch let error as R2T2ProviderError {
            return .unhealthy(error.asrError)
        } catch {
            return .unhealthy(
                VoxFlowASRCore.ASRError(
                    category: .preparationFailed,
                    message: error.localizedDescription
                )
            )
        }
    }

    public func makeSession(
        language: VoxFlowASRCore.ASRLanguageCapability
    ) async throws -> any VoxFlowASRCore.ASRSession {
        try await prepare()
        guard let modelURL else {
            throw R2T2ProviderError.modelNotInstalled
        }
        return R2T2ASRSession(
            sessionID: VoxFlowASRCore.ASRSessionID(rawValue: "confucius4-r2t2-\(UUID().uuidString)"),
            modelURL: modelURL,
            languageHint: R2T2LanguageMapper.languageHint(for: language),
            streamFactory: streamFactory
        )
    }

    private static func throwIfUnavailable(
        _ state: VoxFlowASRCore.ASRModelInstallationState
    ) throws {
        switch state {
        case .ready:
            return
        case .notInstalled, .downloading, .verifying, .compiling, .prewarming:
            throw R2T2ProviderError.modelNotInstalled
        case .corrupt:
            throw R2T2ProviderError.modelCorrupt
        case .runtimeUnsupported(let reason):
            throw R2T2ProviderError.unsupportedInstallationState(
                category: .runtimeUnsupported,
                reason: reason
            )
        case .hardwareUnsupported(let reason):
            throw R2T2ProviderError.unsupportedInstallationState(
                category: .hardwareUnsupported,
                reason: reason
            )
        case .failed(let message):
            throw R2T2ProviderError.preparationFailed(message)
        }
    }
}
