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
    case connectionTimedOut

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
        case .connectionTimedOut:
            return "腾讯云实时语音识别连接超时。"
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
    func connect(request: URLRequest) async throws -> any TencentRealtimeWebSocketConnection
}

public struct URLSessionTencentRealtimeWebSocketTransport: TencentRealtimeWebSocketTransport {
    public init() {}

    public func connect(request: URLRequest) async throws -> any TencentRealtimeWebSocketConnection {
        let task = URLSession.shared.webSocketTask(with: request)
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

public protocol TencentRealtimeASRStreamingClient: CloudASRStreamingClient
where Configuration == TencentRealtimeASRConfiguration, Message == TencentRealtimeASRMessage {}

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
        let connection = try await transport.connect(request: signedRequest(configuration: configuration))
        defer { connection.close() }
        let handshake = try await receiveDecodedMessage(
            from: connection,
            timeoutSeconds: configuration.timeoutSeconds
        )
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
        let connection = try await transport.connect(request: signedRequest(configuration: configuration))
        defer { connection.close() }
        let handshake = try await receiveDecodedMessage(
            from: connection,
            timeoutSeconds: configuration.timeoutSeconds
        )
        try validate(handshake)

        try await runStreamingTasks(
            audioChunks: audioChunks,
            connection: connection,
            timeoutSeconds: configuration.timeoutSeconds,
            onMessage: onMessage
        )
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

    private func signedRequest(configuration: TencentRealtimeASRConfiguration) throws -> URLRequest {
        var request = URLRequest(url: try signedURL(configuration: configuration))
        request.timeoutInterval = configuration.timeoutSeconds
        return request
    }

    private func send(
        audioChunks: AsyncStream<Data>,
        to connection: any TencentRealtimeWebSocketConnection
    ) async throws {
        for await chunk in audioChunks where !chunk.isEmpty {
            try Task.checkCancellation()
            try await connection.sendData(chunk)
        }
        try Task.checkCancellation()
        try await connection.sendText(#"{"type":"end"}"#)
    }

    private func runStreamingTasks(
        audioChunks: AsyncStream<Data>,
        connection: any TencentRealtimeWebSocketConnection,
        timeoutSeconds: Double,
        onMessage: @escaping @Sendable (TencentRealtimeASRMessage) -> Void
    ) async throws {
        try await withThrowingTaskGroup(of: StreamingTaskResult.self) { group in
            group.addTask {
                try await self.send(audioChunks: audioChunks, to: connection)
                return .senderFinished
            }
            group.addTask {
                try await self.receiveMessages(
                    from: connection,
                    timeoutSeconds: timeoutSeconds,
                    onMessage: onMessage
                )
                return .receiverFinished
            }
            defer { group.cancelAll() }

            while let result = try await group.next() {
                switch result {
                case .senderFinished:
                    continue
                case .receiverFinished:
                    return
                }
            }
        }
    }

    private func receiveMessages(
        from connection: any TencentRealtimeWebSocketConnection,
        timeoutSeconds: Double,
        onMessage: @escaping @Sendable (TencentRealtimeASRMessage) -> Void
    ) async throws {
        while true {
            try Task.checkCancellation()
            let message = try await receiveDecodedMessage(
                from: connection,
                timeoutSeconds: timeoutSeconds
            )
            try validate(message)
            onMessage(message)
            if message.isFinal {
                return
            }
        }
    }

    private func receiveDecodedMessage(
        from connection: any TencentRealtimeWebSocketConnection,
        timeoutSeconds: Double
    ) async throws -> TencentRealtimeASRMessage {
        try await Self.withTimeout(
            seconds: timeoutSeconds,
            timeoutError: TencentRealtimeASRError.connectionTimedOut,
            onTimeout: {
                connection.close()
            }
        ) {
            switch try await connection.receive() {
            case .text(let text):
                return try TencentRealtimeASRMessage.decode(text)
            case .data(let data):
                return try TencentRealtimeASRMessage.decode(data)
            }
        }
    }

    private static func withTimeout<T: Sendable>(
        seconds: Double,
        timeoutError: Error,
        onTimeout: @escaping @Sendable () -> Void,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        let nanoseconds = UInt64(max(seconds, 0.001) * 1_000_000_000)
        let race = TimeoutRace<T>()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let operationTask = Task {
                    do {
                        let value = try await operation()
                        await race.resume(.success(value), continuation: continuation)
                    } catch {
                        await race.resume(.failure(error), continuation: continuation)
                    }
                }
                let timeoutTask = Task {
                    do {
                        try await Task.sleep(nanoseconds: nanoseconds)
                    } catch {
                        return
                    }
                    onTimeout()
                    await race.resume(.failure(timeoutError), continuation: continuation)
                }
                Task {
                    await race.register(
                        continuation: continuation,
                        operationTask: operationTask,
                        timeoutTask: timeoutTask
                    )
                }
            }
        } onCancel: {
            onTimeout()
            Task {
                await race.cancel()
            }
        }
    }

    private actor TimeoutRace<T: Sendable> {
        private var didResume = false
        private var continuation: CheckedContinuation<T, Error>?
        private var operationTask: Task<Void, Never>?
        private var timeoutTask: Task<Void, Never>?

        func register(
            continuation: CheckedContinuation<T, Error>,
            operationTask: Task<Void, Never>,
            timeoutTask: Task<Void, Never>
        ) {
            guard !didResume else {
                operationTask.cancel()
                timeoutTask.cancel()
                return
            }
            self.continuation = continuation
            self.operationTask = operationTask
            self.timeoutTask = timeoutTask
        }

        func resume(
            _ result: Result<T, Error>,
            continuation fallbackContinuation: CheckedContinuation<T, Error>
        ) {
            guard !didResume else { return }
            didResume = true
            let continuation = continuation ?? fallbackContinuation
            operationTask?.cancel()
            timeoutTask?.cancel()
            self.continuation = nil
            operationTask = nil
            timeoutTask = nil
            continuation.resume(with: result)
        }

        func cancel() {
            guard !didResume else { return }
            didResume = true
            operationTask?.cancel()
            timeoutTask?.cancel()
            continuation?.resume(throwing: CancellationError())
            continuation = nil
            operationTask = nil
            timeoutTask = nil
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

    private enum StreamingTaskResult: Sendable {
        case senderFinished
        case receiverFinished
    }
}
