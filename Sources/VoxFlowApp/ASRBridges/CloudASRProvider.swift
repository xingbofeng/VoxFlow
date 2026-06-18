import Foundation

enum ASRProviderHealthStatus: String, Equatable {
    case ok
    case warning
    case error
}

struct ASRProviderHealthResult: Equatable {
    let status: ASRProviderHealthStatus
    let message: String
    let latencyMS: Int?
}

struct CloudASRProviderConfiguration: Equatable, Sendable {
    let providerID: String
    let displayName: String
    let baseURL: String
    let model: String
    let apiKeyRef: String
    let timeoutSeconds: Double

    var redactedDescription: String {
        "\(displayName) \(baseURL) \(model) apiKey=<redacted> timeout=\(Int(timeoutSeconds))s"
    }
}

struct CloudASRFileRequest: Equatable, Sendable {
    let fileURL: URL
    let locale: Locale
    let configuration: CloudASRProviderConfiguration
}

struct CloudASRTranscriptionResult: Equatable, Sendable {
    let text: String
    let durationSeconds: Double?
    let providerID: String
    let warnings: [String]
}

protocol CloudASRProviderClient: Sendable {
    var providerID: String { get }
    var displayName: String { get }
    var capabilities: ASRProviderCapabilities { get }

    func testConnection(
        configuration: CloudASRProviderConfiguration
    ) async throws -> ASRProviderHealthResult

    func transcribeFile(
        _ request: CloudASRFileRequest,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> CloudASRTranscriptionResult
}
