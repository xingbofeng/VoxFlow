public struct ASRProviderID: RawRepresentable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public struct ASRLanguageCapability: Equatable, Sendable {
    public let bcp47Tag: String

    public init(bcp47Tag: String) {
        self.bcp47Tag = bcp47Tag
    }
}

public enum ASRStreamingSemantics: Equatable, Sendable {
    case systemStreaming
    case nativeStreaming
    case chunkedStablePrefix
    case rollingWindowConfirmedSegments
    case companionPartialFinal
    case offlineFinalOnly
}

public enum ASRModelInstallationState: Equatable, Sendable {
    case notInstalled
    case downloading(progress: Double)
    case verifying
    case compiling
    case prewarming
    case ready
    case corrupt
    case runtimeUnsupported(reason: String)
    case hardwareUnsupported(reason: String)
    case failed(message: String)

    public var isReady: Bool {
        self == .ready
    }

    public var isUnsupported: Bool {
        switch self {
        case .runtimeUnsupported, .hardwareUnsupported:
            return true
        case .notInstalled,
             .downloading,
             .verifying,
             .compiling,
             .prewarming,
             .ready,
             .corrupt,
             .failed:
            return false
        }
    }
}

public struct ASRProviderDescriptor: Equatable, Sendable {
    public let id: ASRProviderID
    public let displayName: String
    public let modelInstallationState: ASRModelInstallationState
    public let supportedLanguages: [ASRLanguageCapability]
    public let streamingSemantics: ASRStreamingSemantics
    public let timeoutPolicy: ASRTimeoutPolicy

    public init(
        id: ASRProviderID,
        displayName: String,
        modelInstallationState: ASRModelInstallationState,
        supportedLanguages: [ASRLanguageCapability],
        streamingSemantics: ASRStreamingSemantics,
        timeoutPolicy: ASRTimeoutPolicy = .standard
    ) {
        self.id = id
        self.displayName = displayName
        self.modelInstallationState = modelInstallationState
        self.supportedLanguages = supportedLanguages
        self.streamingSemantics = streamingSemantics
        self.timeoutPolicy = timeoutPolicy
    }
}

public enum ASRProviderHealth: Equatable, Sendable {
    case healthy
    case unhealthy(ASRError)
}

public protocol ASRProvider: Sendable {
    var descriptor: ASRProviderDescriptor { get }

    func install() async throws
    func delete() async throws
    func prepare() async throws
    func healthCheck() async -> ASRProviderHealth
    func makeSession(language: ASRLanguageCapability) async throws -> any ASRSession
}
