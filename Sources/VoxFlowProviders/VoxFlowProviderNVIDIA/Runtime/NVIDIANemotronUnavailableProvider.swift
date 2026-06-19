import Foundation
import VoxFlowASRCore

public enum NVIDIANemotronProviderError: Error, Equatable, LocalizedError, Sendable {
    case modelNotInstalled
    case runtimeUnsupported(reason: String)
    case unsupportedLanguage(String)
    case preparationFailed(String)
    case emptyTranscript

    public var errorDescription: String? {
        switch self {
        case .modelNotInstalled:
            return "NVIDIA Nemotron 模型尚未安装或不可用。"
        case .runtimeUnsupported(let reason):
            return reason
        case .unsupportedLanguage(let language):
            return "NVIDIA Nemotron 暂不支持 \(language) 识别。"
        case .preparationFailed(let message):
            return message
        case .emptyTranscript:
            return "NVIDIA Nemotron 没有识别到可用文本。"
        }
    }
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
