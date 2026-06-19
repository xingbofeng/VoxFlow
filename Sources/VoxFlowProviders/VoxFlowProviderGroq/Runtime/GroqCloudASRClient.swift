import Foundation
import VoxFlowProviderCloudCore

public protocol CloudASRHTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionCloudASRHTTPTransport: CloudASRHTTPTransport {
    public init() {}

    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw CloudASRClientError.invalidResponse
        }
        return (data, response)
    }
}

public enum CloudASRClientError: Error, LocalizedError, Equatable {
    case missingCredential
    case invalidBaseURL
    case unreadableAudioFile
    case invalidResponse
    case requestFailed(statusCode: Int, message: String)

    public var errorDescription: String? {
        switch self {
        case .missingCredential:
            return "未配置云端语音识别 API 密钥。"
        case .invalidBaseURL:
            return "云端语音识别地址无效。"
        case .unreadableAudioFile:
            return "无法读取待识别的音频文件。"
        case .invalidResponse:
            return "云端语音识别返回了无效响应。"
        case let .requestFailed(statusCode, message):
            return "云端语音识别请求失败（HTTP \(statusCode)）：\(message)"
        }
    }
}

public final class GroqCloudASRClient: CloudASRProviderClient, @unchecked Sendable {
    public static let defaultProviderID = "groq_whisper"
    public static let defaultBaseURL = "https://api.groq.com/openai/v1"
    public static let defaultModel = "whisper-large-v3-turbo"
    public static let supportedWhisperModels = [
        "whisper-large-v3-turbo",
        "whisper-large-v3",
    ]

    public let providerID = GroqCloudASRClient.defaultProviderID
    public let displayName = "Groq（免费）"

    private let credentialStore: any CloudASRCredentialReading
    private let transport: any CloudASRHTTPTransport

    public init(
        credentialStore: any CloudASRCredentialReading,
        transport: any CloudASRHTTPTransport = URLSessionCloudASRHTTPTransport()
    ) {
        self.credentialStore = credentialStore
        self.transport = transport
    }

    public func testConnection(
        configuration: CloudASRProviderConfiguration
    ) async throws -> ASRProviderHealthResult {
        let apiKey = try resolvedAPIKey(for: configuration)
        let url = try endpointURL(configuration: configuration, component: "models")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = configuration.timeoutSeconds
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let startedAt = Date()
        let (data, response) = try await transport.data(for: request)
        try validate(response: response, data: data, redacting: apiKey)
        return ASRProviderHealthResult(
            status: .ok,
            message: "Groq 连接正常",
            latencyMS: max(0, Int(Date().timeIntervalSince(startedAt) * 1_000))
        )
    }

    public func transcribeFile(
        _ request: CloudASRFileRequest,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> CloudASRTranscriptionResult {
        let apiKey = try resolvedAPIKey(for: request.configuration)
        let audioData: Data
        do {
            audioData = try Data(contentsOf: request.fileURL)
        } catch {
            throw CloudASRClientError.unreadableAudioFile
        }

        let url = try endpointURL(
            configuration: request.configuration,
            component: "audio/transcriptions"
        )
        let boundary = "VoxFlow-\(UUID().uuidString)"
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = request.configuration.timeoutSeconds
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue(
            "multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type"
        )
        urlRequest.httpBody = multipartBody(
            audioData: audioData,
            fileURL: request.fileURL,
            model: request.configuration.model.isEmpty
                ? Self.defaultModel
                : request.configuration.model,
            language: request.locale.language.languageCode?.identifier,
            boundary: boundary
        )

        progress(0)
        let (data, response) = try await transport.data(for: urlRequest)
        try validate(response: response, data: data, redacting: apiKey)
        guard
            let payload = try? JSONDecoder().decode(TranscriptionResponse.self, from: data),
            !payload.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw CloudASRClientError.invalidResponse
        }
        progress(1)
        return CloudASRTranscriptionResult(
            text: payload.text,
            durationSeconds: payload.duration,
            providerID: providerID,
            warnings: []
        )
    }

    private func resolvedAPIKey(
        for configuration: CloudASRProviderConfiguration
    ) throws -> String {
        let apiKey = try credentialStore.readCredential(account: configuration.apiKeyRef)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let apiKey, !apiKey.isEmpty else {
            throw CloudASRClientError.missingCredential
        }
        return apiKey
    }

    private func endpointURL(
        configuration: CloudASRProviderConfiguration,
        component: String
    ) throws -> URL {
        let rawBaseURL = configuration.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(
            string: rawBaseURL.isEmpty ? Self.defaultBaseURL : rawBaseURL
        ), components.scheme == "https", components.host != nil else {
            throw CloudASRClientError.invalidBaseURL
        }

        var path = components.path
        if path.hasSuffix("/audio/transcriptions") {
            path.removeLast("/audio/transcriptions".count)
        }
        path = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = "/" + [path, component]
            .filter { !$0.isEmpty }
            .joined(separator: "/")
        guard let url = components.url else {
            throw CloudASRClientError.invalidBaseURL
        }
        return url
    }

    private func multipartBody(
        audioData: Data,
        fileURL: URL,
        model: String,
        language: String?,
        boundary: String
    ) -> Data {
        var body = Data()
        body.appendMultipartField(name: "model", value: model, boundary: boundary)
        body.appendMultipartField(name: "response_format", value: "verbose_json", boundary: boundary)
        if let language, !language.isEmpty {
            body.appendMultipartField(name: "language", value: language, boundary: boundary)
        }
        body.append("--\(boundary)\r\n")
        body.append(
            "Content-Disposition: form-data; name=\"file\"; filename=\"\(safeFilename(fileURL.lastPathComponent))\"\r\n"
        )
        body.append("Content-Type: \(mimeType(for: fileURL))\r\n\r\n")
        body.append(audioData)
        body.append("\r\n--\(boundary)--\r\n")
        return body
    }

    private func safeFilename(_ filename: String) -> String {
        filename
            .replacingOccurrences(of: "\r", with: "-")
            .replacingOccurrences(of: "\n", with: "-")
            .replacingOccurrences(of: "\"", with: "-")
    }

    private func mimeType(for fileURL: URL) -> String {
        switch fileURL.pathExtension.lowercased() {
        case "m4a", "mp4": "audio/mp4"
        case "mp3": "audio/mpeg"
        case "ogg", "oga": "audio/ogg"
        case "webm": "audio/webm"
        case "wav", "wave": "audio/wav"
        default: "application/octet-stream"
        }
    }

    private func validate(response: HTTPURLResponse, data: Data, redacting apiKey: String) throws {
        guard (200..<300).contains(response.statusCode) else {
            let payload = try? JSONDecoder().decode(ErrorResponse.self, from: data)
            let rawMessage = payload?.error.message
                ?? HTTPURLResponse.localizedString(forStatusCode: response.statusCode)
            throw CloudASRClientError.requestFailed(
                statusCode: response.statusCode,
                message: redacted(rawMessage, apiKey: apiKey)
            )
        }
    }

    private func redacted(_ message: String, apiKey: String) -> String {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { return message }
        return message.replacingOccurrences(of: trimmedKey, with: "<redacted>")
    }

    private struct TranscriptionResponse: Decodable {
        let text: String
        let duration: Double?
    }

    private struct ErrorResponse: Decodable {
        struct Detail: Decodable {
            let message: String
        }

        let error: Detail
    }
}

private extension Data {
    mutating func append(_ string: String) {
        append(Data(string.utf8))
    }

    mutating func appendMultipartField(name: String, value: String, boundary: String) {
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        append(value)
        append("\r\n")
    }
}
