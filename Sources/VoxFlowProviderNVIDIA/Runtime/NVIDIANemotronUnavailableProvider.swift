import VoxFlowASRCore

public enum NVIDIANemotronProviderError: Error, Equatable, Sendable {
    case modelNotInstalled
    case runtimeUnsupported(reason: String)
    case unsupportedLanguage(String)
    case preparationFailed(String)
    case emptyTranscript
}

public struct NVIDIANemotronUnavailableProvider: ASRProvider {
    public let descriptor: ASRProviderDescriptor

    public init(descriptor: ASRProviderDescriptor = NVIDIANemotronProviderDescriptor.current) {
        self.descriptor = descriptor
    }

    public func install() async throws {
        throw runtimeUnsupportedError()
    }

    public func delete() async throws {}

    public func prepare() async throws {
        throw runtimeUnsupportedError()
    }

    public func healthCheck() async -> ASRProviderHealth {
        .unhealthy(runtimeUnsupportedASRError())
    }

    public func makeSession(language: ASRLanguageCapability) async throws -> any ASRSession {
        throw runtimeUnsupportedError()
    }

    private func runtimeUnsupportedError() -> NVIDIANemotronProviderError {
        .runtimeUnsupported(reason: NVIDIANemotronProviderDescriptor.runtimeUnsupportedReason)
    }

    private func runtimeUnsupportedASRError() -> ASRError {
        ASRError(
            category: .runtimeUnsupported,
            message: NVIDIANemotronProviderDescriptor.runtimeUnsupportedReason
        )
    }
}
