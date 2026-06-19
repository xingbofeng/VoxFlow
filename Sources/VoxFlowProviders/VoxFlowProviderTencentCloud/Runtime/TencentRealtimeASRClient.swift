import CryptoKit
import Foundation
import VoxFlowProviderCloudCore

public enum TencentRealtimeASRError: Error, LocalizedError, Equatable {
    case missingCredential
    case invalidSignedURL
    case invalidMessage
    case providerError(code: Int, message: String)
    case unsupportedSampleRate(Int)
    case inconsistentSampleRate

    public var errorDescription: String? {
        switch self {
        case .missingCredential:
            return "未配置腾讯云 AppID、SecretId 或 SecretKey。"
        case .invalidSignedURL:
            return "腾讯云实时语音识别签名地址无效。"
        case .invalidMessage:
            return "腾讯云实时语音识别返回了无效消息。"
        case let .providerError(code, message):
            return "腾讯云实时语音识别失败（\(code)）：\(message)"
        case let .unsupportedSampleRate(sampleRate):
            return "腾讯云实时语音识别当前仅支持 16k PCM，收到 \(sampleRate)Hz 音频。"
        case .inconsistentSampleRate:
            return "录音采样率发生变化，无法提交腾讯云实时识别。"
        }
    }
}

public struct TencentRealtimeASRConfiguration: Equatable, Sendable {
    public static let defaultEngineModelType = "16k_zh"

    public let appID: String
    public let secretID: String
    public let secretKey: String
    public let engineModelType: String
    public let voiceFormat: Int
    public let needVAD: Int
    public let timeoutSeconds: Double

    public init(
        appID: String,
        secretID: String,
        secretKey: String,
        engineModelType: String = Self.defaultEngineModelType,
        voiceFormat: Int = 1,
        needVAD: Int = 1,
        timeoutSeconds: Double = 30
    ) {
        self.appID = appID
        self.secretID = secretID
        self.secretKey = secretKey
        self.engineModelType = engineModelType
        self.voiceFormat = voiceFormat
        self.needVAD = needVAD
        self.timeoutSeconds = timeoutSeconds
    }

    public var isComplete: Bool {
        !appID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !secretID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !secretKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

public struct TencentRealtimeASRURLSigner: Sendable {
    public let appID: String
    public let secretID: String
    public let secretKey: String
    public let timestamp: Int
    public let expired: Int
    public let nonce: Int
    public let voiceID: String
    public let engineModelType: String
    public let voiceFormat: Int
    public let needVAD: Int

    public init(
        appID: String,
        secretID: String,
        secretKey: String,
        timestamp: Int,
        expired: Int,
        nonce: Int,
        voiceID: String,
        engineModelType: String,
        voiceFormat: Int,
        needVAD: Int
    ) {
        self.appID = appID
        self.secretID = secretID
        self.secretKey = secretKey
        self.timestamp = timestamp
        self.expired = expired
        self.nonce = nonce
        self.voiceID = voiceID
        self.engineModelType = engineModelType
        self.voiceFormat = voiceFormat
        self.needVAD = needVAD
    }

    public var redactedDescription: String {
        "TencentRealtimeASR appID=\(appID) secretID=\(secretID) secretKey=<redacted> engine=\(engineModelType)"
    }

    public func signedURL() throws -> URL {
        let query = sortedQueryItems()
            .map { "\($0.name)=\($0.value ?? "")" }
            .joined(separator: "&")
        let signSource = "asr.cloud.tencent.com/asr/v2/\(appID)?\(query)"
        let key = SymmetricKey(data: Data(secretKey.utf8))
        let signature = HMAC<Insecure.SHA1>.authenticationCode(
            for: Data(signSource.utf8),
            using: key
        )
        let signatureText = Data(signature).base64EncodedString()

        var components = URLComponents()
        components.scheme = "wss"
        components.host = "asr.cloud.tencent.com"
        components.path = "/asr/v2/\(appID)"
        components.percentEncodedQuery = Self.percentEncodedQuery(for: sortedQueryItems() + [
            URLQueryItem(name: "signature", value: signatureText),
        ])
        guard let url = components.url else {
            throw TencentRealtimeASRError.invalidSignedURL
        }
        return url
    }

    private static func percentEncodedQuery(for items: [URLQueryItem]) -> String {
        items
            .map { "\(percentEncodeQueryComponent($0.name))=\(percentEncodeQueryComponent($0.value ?? ""))" }
            .joined(separator: "&")
    }

    private static func percentEncodeQueryComponent(_ value: String) -> String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private func sortedQueryItems() -> [URLQueryItem] {
        [
            URLQueryItem(name: "engine_model_type", value: engineModelType),
            URLQueryItem(name: "expired", value: String(expired)),
            URLQueryItem(name: "needvad", value: String(needVAD)),
            URLQueryItem(name: "nonce", value: String(nonce)),
            URLQueryItem(name: "secretid", value: secretID),
            URLQueryItem(name: "timestamp", value: String(timestamp)),
            URLQueryItem(name: "voice_format", value: String(voiceFormat)),
            URLQueryItem(name: "voice_id", value: voiceID),
        ].sorted { $0.name < $1.name }
    }
}

public struct TencentRealtimeASRMessage: Equatable, Sendable {
    public let code: Int
    public let message: String
    public let voiceID: String?
    public let index: Int?
    public let sliceType: Int?
    public let transcript: String
    public let isFinal: Bool

    public var isStable: Bool {
        sliceType == 2
    }

    public static func decode(_ data: Data) throws -> TencentRealtimeASRMessage {
        guard let payload = try? JSONDecoder().decode(Response.self, from: data) else {
            throw TencentRealtimeASRError.invalidMessage
        }
        return TencentRealtimeASRMessage(
            code: payload.code,
            message: payload.message,
            voiceID: payload.voiceID,
            index: payload.result?.index,
            sliceType: payload.result?.sliceType,
            transcript: payload.result?.voiceText ?? "",
            isFinal: payload.final == 1
        )
    }

    public static func decode(_ text: String) throws -> TencentRealtimeASRMessage {
        try decode(Data(text.utf8))
    }

    private struct Response: Decodable {
        struct Result: Decodable {
            let sliceType: Int?
            let index: Int?
            let voiceText: String?

            enum CodingKeys: String, CodingKey {
                case sliceType = "slice_type"
                case index
                case voiceText = "voice_text_str"
            }
        }

        let code: Int
        let message: String
        let voiceID: String?
        let result: Result?
        let final: Int?

        enum CodingKeys: String, CodingKey {
            case code
            case message
            case voiceID = "voice_id"
            case result
            case final
        }
    }
}

public enum TencentRealtimeWebSocketMessage: Equatable, Sendable {
    case text(String)
    case data(Data)
}

public protocol TencentRealtimeWebSocketConnection: Sendable {
    func sendData(_ data: Data) async throws
    func sendText(_ text: String) async throws
    func receive() async throws -> TencentRealtimeWebSocketMessage
    func close()
}

public protocol TencentRealtimeWebSocketTransport: Sendable {
    func connect(url: URL) async throws -> any TencentRealtimeWebSocketConnection
}

public struct URLSessionTencentRealtimeWebSocketTransport: TencentRealtimeWebSocketTransport {
    public init() {}

    public func connect(url: URL) async throws -> any TencentRealtimeWebSocketConnection {
        let task = URLSession.shared.webSocketTask(with: url)
        task.resume()
        return URLSessionTencentRealtimeWebSocketConnection(task: task)
    }
}

private final class URLSessionTencentRealtimeWebSocketConnection: TencentRealtimeWebSocketConnection, @unchecked Sendable {
    private let task: URLSessionWebSocketTask

    init(task: URLSessionWebSocketTask) {
        self.task = task
    }

    func sendData(_ data: Data) async throws {
        try await task.send(.data(data))
    }

    func sendText(_ text: String) async throws {
        try await task.send(.string(text))
    }

    func receive() async throws -> TencentRealtimeWebSocketMessage {
        switch try await task.receive() {
        case .string(let text):
            return .text(text)
        case .data(let data):
            return .data(data)
        @unknown default:
            throw TencentRealtimeASRError.invalidMessage
        }
    }

    func close() {
        task.cancel(with: .normalClosure, reason: nil)
    }
}

public protocol TencentRealtimeASRStreamingClient: Sendable {
    func testConnection(configuration: TencentRealtimeASRConfiguration) async throws -> ASRProviderHealthResult
    func transcribe(
        configuration: TencentRealtimeASRConfiguration,
        audioChunks: AsyncStream<Data>,
        onMessage: @escaping @Sendable (TencentRealtimeASRMessage) -> Void
    ) async throws
}

public final class TencentRealtimeASRClient: TencentRealtimeASRStreamingClient, @unchecked Sendable {
    private let transport: any TencentRealtimeWebSocketTransport
    private let clock: @Sendable () -> Date
    private let nonce: @Sendable () -> Int
    private let voiceID: @Sendable () -> String

    public init(
        transport: any TencentRealtimeWebSocketTransport = URLSessionTencentRealtimeWebSocketTransport(),
        clock: @escaping @Sendable () -> Date = Date.init,
        nonce: @escaping @Sendable () -> Int = { Int.random(in: 100_000...999_999_999) },
        voiceID: @escaping @Sendable () -> String = { UUID().uuidString }
    ) {
        self.transport = transport
        self.clock = clock
        self.nonce = nonce
        self.voiceID = voiceID
    }

    public func testConnection(configuration: TencentRealtimeASRConfiguration) async throws -> ASRProviderHealthResult {
        let startedAt = Date()
        let connection = try await transport.connect(url: signedURL(configuration: configuration))
        defer { connection.close() }
        let handshake = try await receiveDecodedMessage(from: connection)
        try validate(handshake)
        return ASRProviderHealthResult(
            status: .ok,
            message: "腾讯云实时语音识别连接正常",
            latencyMS: max(0, Int(Date().timeIntervalSince(startedAt) * 1_000))
        )
    }

    public func transcribe(
        configuration: TencentRealtimeASRConfiguration,
        audioChunks: AsyncStream<Data>,
        onMessage: @escaping @Sendable (TencentRealtimeASRMessage) -> Void
    ) async throws {
        let connection = try await transport.connect(url: signedURL(configuration: configuration))
        defer { connection.close() }
        let handshake = try await receiveDecodedMessage(from: connection)
        try validate(handshake)

        async let sender: Void = send(audioChunks: audioChunks, to: connection)
        async let receiver: Void = receiveMessages(from: connection, onMessage: onMessage)
        _ = try await (sender, receiver)
    }

    private func signedURL(configuration: TencentRealtimeASRConfiguration) throws -> URL {
        guard configuration.isComplete else {
            throw TencentRealtimeASRError.missingCredential
        }
        let timestamp = Int(clock().timeIntervalSince1970)
        return try TencentRealtimeASRURLSigner(
            appID: configuration.appID,
            secretID: configuration.secretID,
            secretKey: configuration.secretKey,
            timestamp: timestamp,
            expired: timestamp + 24 * 60 * 60,
            nonce: nonce(),
            voiceID: voiceID(),
            engineModelType: configuration.engineModelType,
            voiceFormat: configuration.voiceFormat,
            needVAD: configuration.needVAD
        ).signedURL()
    }

    private func send(
        audioChunks: AsyncStream<Data>,
        to connection: any TencentRealtimeWebSocketConnection
    ) async throws {
        for await chunk in audioChunks where !chunk.isEmpty {
            try await connection.sendData(chunk)
        }
        try await connection.sendText(#"{"type":"end"}"#)
    }

    private func receiveMessages(
        from connection: any TencentRealtimeWebSocketConnection,
        onMessage: @escaping @Sendable (TencentRealtimeASRMessage) -> Void
    ) async throws {
        while true {
            let message = try await receiveDecodedMessage(from: connection)
            try validate(message)
            onMessage(message)
            if message.isFinal {
                return
            }
        }
    }

    private func receiveDecodedMessage(
        from connection: any TencentRealtimeWebSocketConnection
    ) async throws -> TencentRealtimeASRMessage {
        switch try await connection.receive() {
        case .text(let text):
            return try TencentRealtimeASRMessage.decode(text)
        case .data(let data):
            return try TencentRealtimeASRMessage.decode(data)
        }
    }

    private func validate(_ message: TencentRealtimeASRMessage) throws {
        guard message.code == 0 else {
            throw TencentRealtimeASRError.providerError(
                code: message.code,
                message: message.message
            )
        }
    }
}
