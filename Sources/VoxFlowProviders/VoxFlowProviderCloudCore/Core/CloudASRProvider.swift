import Foundation

public enum ASRProviderHealthStatus: String, Equatable, Sendable {
    case ok
    case warning
    case error
}

public struct ASRProviderHealthResult: Equatable, Sendable {
    public let status: ASRProviderHealthStatus
    public let message: String
    public let latencyMS: Int?

    public init(status: ASRProviderHealthStatus, message: String, latencyMS: Int?) {
        self.status = status
        self.message = message
        self.latencyMS = latencyMS
    }
}

public struct CloudASRProviderConfiguration: Equatable, Sendable {
    public let providerID: String
    public let displayName: String
    public let baseURL: String
    public let model: String
    public let apiKeyRef: String
    public let timeoutSeconds: Double

    public init(
        providerID: String,
        displayName: String,
        baseURL: String,
        model: String,
        apiKeyRef: String,
        timeoutSeconds: Double
    ) {
        self.providerID = providerID
        self.displayName = displayName
        self.baseURL = baseURL
        self.model = model
        self.apiKeyRef = apiKeyRef
        self.timeoutSeconds = timeoutSeconds
    }

    public var redactedDescription: String {
        "\(displayName) \(baseURL) \(model) apiKey=<redacted> timeout=\(Int(timeoutSeconds))s"
    }
}

public struct CloudASRFileRequest: Equatable, Sendable {
    public let fileURL: URL
    public let locale: Locale
    public let configuration: CloudASRProviderConfiguration
    public let prompt: String?

    public init(
        fileURL: URL,
        locale: Locale,
        configuration: CloudASRProviderConfiguration,
        prompt: String? = nil
    ) {
        self.fileURL = fileURL
        self.locale = locale
        self.configuration = configuration
        self.prompt = prompt
    }
}

public struct CloudASRTranscriptionResult: Equatable, Sendable {
    public let text: String
    public let durationSeconds: Double?
    public let providerID: String
    public let warnings: [String]

    public init(text: String, durationSeconds: Double?, providerID: String, warnings: [String]) {
        self.text = text
        self.durationSeconds = durationSeconds
        self.providerID = providerID
        self.warnings = warnings
    }
}

public protocol CloudASRCredentialReading: AnyObject {
    func readCredential(account: String) throws -> String?
}

public protocol CloudASRProviderClient: Sendable {
    var providerID: String { get }
    var displayName: String { get }

    func testConnection(
        configuration: CloudASRProviderConfiguration
    ) async throws -> ASRProviderHealthResult

    func transcribeFile(
        _ request: CloudASRFileRequest,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> CloudASRTranscriptionResult
}

public protocol CloudASRStreamingClient: Sendable {
    associatedtype Configuration: Sendable
    associatedtype Message: Sendable

    func testConnection(
        configuration: Configuration
    ) async throws -> ASRProviderHealthResult

    func transcribe(
        configuration: Configuration,
        audioChunks: AsyncStream<Data>,
        onMessage: @escaping @Sendable (Message) -> Void
    ) async throws
}
