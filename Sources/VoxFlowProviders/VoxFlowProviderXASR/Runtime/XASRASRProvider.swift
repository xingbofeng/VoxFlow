import Foundation
import VoxFlowASRCore

public enum XASRProviderError: Error, Sendable {
    case modelNotInstalled
    case preflightBlocked(XASRPreflightBlocker)
    case unsupportedLanguage(String)
    case emptyTranscript
    case audioDropped
    case invalidSessionState
    case preparationFailed(String)
}

public struct XASRASRProvider: ASRProvider {
    public let descriptor: ASRProviderDescriptor
    private let modelURL: URL?
    private let streamFactory: any XASRStreamMaking
    private let environment: XASRRuntimePreflight.Environment
    public init(descriptor: ASRProviderDescriptor, modelURL: URL?, streamFactory: any XASRStreamMaking = XASRRuntime(), environment: XASRRuntimePreflight.Environment = .current()) {
        self.descriptor = descriptor; self.modelURL = modelURL; self.streamFactory = streamFactory; self.environment = environment
    }
    public func install() async throws { throw XASRProviderError.preparationFailed("X-ASR installation is managed by ModelStore.") }
    public func delete() async throws { throw XASRProviderError.preparationFailed("X-ASR deletion is managed by ModelStore.") }
    public func prepare() async throws {
        if case .blocked(let blocker) = XASRRuntimePreflight.evaluate(environment: environment) {
            throw XASRProviderError.preflightBlocked(blocker)
        }
        guard descriptor.modelInstallationState.isReady,
              let modelURL, XASRModel.modelsExist(at: modelURL) else {
            throw XASRProviderError.modelNotInstalled
        }
    }
    public func healthCheck() async -> ASRProviderHealth {
        do { try await prepare(); return .healthy } catch { return .unhealthy(Self.asrError(for: error)) }
    }
    public func makeSession(language: ASRLanguageCapability) async throws -> any ASRSession {
        try await prepare()
        let tag = language.bcp47Tag.lowercased()
        guard tag == "zh" || tag.hasPrefix("zh-") || tag == "en" || tag.hasPrefix("en-") else {
            throw XASRProviderError.unsupportedLanguage(language.bcp47Tag)
        }
        guard let modelURL else { throw XASRProviderError.modelNotInstalled }
        return XASRASRSession(sessionID: .init(rawValue: "xasr-\(UUID().uuidString)"), modelURL: modelURL, streamFactory: streamFactory)
    }

    static func asrError(for error: Error) -> ASRError {
        let category: ASRErrorCategory
        if let error = error as? XASRProviderError {
            switch error {
            case .modelNotInstalled: category = .modelNotInstalled
            case .preflightBlocked(let blocker): category = blocker.asrErrorCategory
            case .unsupportedLanguage: category = .unsupportedLanguage
            case .emptyTranscript: category = .emptyTranscript
            case .audioDropped: category = .audioDropped
            case .invalidSessionState, .preparationFailed: category = .preparationFailed
            }
        } else if error is CancellationError {
            category = .cancelled
        } else if let error = error as? XASRRuntimeError {
            switch error {
            case .modelFilesMissing: category = .modelNotInstalled
            case .modelCorrupt: category = .modelCorrupt
            case .invalidated, .streamClosed: category = .cancelled
            case .recognizerCreationFailed, .streamCreationFailed, .busy, .invalidAudio: category = .preparationFailed
            }
        } else {
            category = .preparationFailed
        }
        return ASRError(category: category, message: String(describing: error))
    }
}
