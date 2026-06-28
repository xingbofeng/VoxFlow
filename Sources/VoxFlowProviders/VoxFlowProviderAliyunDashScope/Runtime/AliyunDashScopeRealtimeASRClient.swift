import Foundation
import VoxFlowProviderCloudCore

public enum AliyunDashScopeRealtimeASRError: Error, LocalizedError, Equatable {
    case missingCredential
    case invalidEndpoint
    case invalidMessage
    case providerError(code: String, message: String)
    case taskDidNotStart
    case unsupportedSampleRate(Int)
    case inconsistentSampleRate
    case connectionTimedOut

    public var errorDescription: String? {
        switch self {
        case .missingCredential:
            return "未配置阿里云百炼 API Key。"
        case .invalidEndpoint:
            return "阿里云 DashScope 实时语音识别地址无效。"
        case .invalidMessage:
            return "阿里云 DashScope 实时语音识别返回了无效消息。"
        case let .providerError(code, message):
            return "阿里云 DashScope 实时语音识别失败（\(code)）：\(message)"
        case .taskDidNotStart:
            return "阿里云 DashScope 实时语音识别任务未成功启动。"
        case let .unsupportedSampleRate(sampleRate):
            return "阿里云 DashScope 实时语音识别当前仅提交 16k PCM，收到 \(sampleRate)Hz 音频。"
        case .inconsistentSampleRate:
            return "录音采样率发生变化，无法提交阿里云 DashScope 实时识别。"
        case .connectionTimedOut:
            return "阿里云 DashScope 实时语音识别连接超时。"
        }
    }
}

public struct AliyunDashScopeRealtimeASRConfiguration: Equatable, Sendable {
    public static let defaultEndpoint = "wss://dashscope.aliyuncs.com/api-ws/v1/inference"
    public static let defaultModel = "fun-asr-realtime"

    public let apiKey: String
    public let model: String
    public let endpoint: String
    public let timeoutSeconds: Double
    public let vocabularyID: String?

    public init(
        apiKey: String,
        model: String = Self.defaultModel,
        endpoint: String = Self.defaultEndpoint,
        timeoutSeconds: Double = 30,
        vocabularyID: String? = nil
    ) {
        self.apiKey = apiKey
        self.model = model
        self.endpoint = endpoint
        self.timeoutSeconds = timeoutSeconds
        self.vocabularyID = Self.normalizedVocabularyID(vocabularyID)
    }

    public var isComplete: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public func endpointURL() throws -> URL {
        guard let url = URL(string: endpoint),
              url.scheme == "wss",
              url.host != nil else {
            throw AliyunDashScopeRealtimeASRError.invalidEndpoint
        }
        return url
    }

    private static func normalizedVocabularyID(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}

public struct AliyunDashScopeRealtimeASRRequest: Codable, Equatable, Sendable {
    public struct Header: Codable, Equatable, Sendable {
        public let action: String
        public let taskID: String
        public let streaming: String

        enum CodingKeys: String, CodingKey {
            case action
            case taskID = "task_id"
            case streaming
        }
    }

    public struct Payload: Codable, Equatable, Sendable {
        public let taskGroup: String?
        public let task: String?
        public let function: String?
        public let model: String?
        public let parameters: Parameters?
        public let input: EmptyObject

        enum CodingKeys: String, CodingKey {
            case taskGroup = "task_group"
            case task
            case function
            case model
            case parameters
            case input
        }
    }

    public struct Parameters: Codable, Equatable, Sendable {
        public let format: String
        public let sampleRate: Int
        public let punctuationPredictionEnabled: Bool
        public let vocabularyID: String?

        enum CodingKeys: String, CodingKey {
            case format
            case sampleRate = "sample_rate"
            case punctuationPredictionEnabled = "punctuation_prediction_enabled"
            case vocabularyID = "vocabulary_id"
        }
    }

    public struct EmptyObject: Codable, Equatable, Sendable {
        public init() {}
    }

    public let header: Header
    public let payload: Payload

    public static func runTask(
        configuration: AliyunDashScopeRealtimeASRConfiguration,
        taskID: UUID,
        sampleRate: Int
    ) throws -> AliyunDashScopeRealtimeASRRequest {
        let model = configuration.model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else {
            throw AliyunDashScopeRealtimeASRError.missingCredential
        }
        return AliyunDashScopeRealtimeASRRequest(
            header: Header(
                action: "run-task",
                taskID: taskID.uuidString,
                streaming: "duplex"
            ),
            payload: Payload(
                taskGroup: "audio",
                task: "asr",
                function: "recognition",
                model: model,
                parameters: Parameters(
                    format: "pcm",
                    sampleRate: sampleRate,
                    punctuationPredictionEnabled: true,
                    vocabularyID: configuration.vocabularyID
                ),
                input: EmptyObject()
            )
        )
    }

    public static func finishTask(taskID: UUID) throws -> AliyunDashScopeRealtimeASRRequest {
        AliyunDashScopeRealtimeASRRequest(
            header: Header(
                action: "finish-task",
                taskID: taskID.uuidString,
                streaming: "duplex"
            ),
            payload: Payload(
                taskGroup: nil,
                task: nil,
                function: nil,
                model: nil,
                parameters: nil,
                input: EmptyObject()
            )
        )
    }

    public func encodedText() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(self), as: UTF8.self)
    }
}

public enum AliyunDashScopeRealtimeASREvent: String, Equatable, Sendable {
    case taskStarted = "task-started"
    case resultGenerated = "result-generated"
    case taskFinished = "task-finished"
    case taskFailed = "task-failed"
    case unknown
}

public struct AliyunDashScopeRealtimeASRMessage: Equatable, Sendable {
    public let taskID: String?
    public let event: AliyunDashScopeRealtimeASREvent
    public let transcript: String
    public let isFinalResult: Bool
    public let isHeartbeat: Bool
    public let errorCode: String?
    public let errorMessage: String?

    public static func decode(_ text: String) throws -> AliyunDashScopeRealtimeASRMessage {
        try decode(Data(text.utf8))
    }

    public static func decode(_ data: Data) throws -> AliyunDashScopeRealtimeASRMessage {
        guard let payload = try? JSONDecoder().decode(Response.self, from: data) else {
            throw AliyunDashScopeRealtimeASRError.invalidMessage
        }
        let event = AliyunDashScopeRealtimeASREvent(rawValue: payload.header.event ?? "") ?? .unknown
        let sentence = payload.payload?.output?.sentence
        return AliyunDashScopeRealtimeASRMessage(
            taskID: payload.header.taskID,
            event: event,
            transcript: sentence?.text ?? "",
            isFinalResult: sentence?.sentenceEnd ?? false,
            isHeartbeat: sentence?.heartbeat ?? false,
            errorCode: payload.header.errorCode,
            errorMessage: payload.header.errorMessage
        )
    }

    private struct Response: Decodable {
        struct Header: Decodable {
            let taskID: String?
            let event: String?
            let errorCode: String?
            let errorMessage: String?

            enum CodingKeys: String, CodingKey {
                case taskID = "task_id"
                case event
                case errorCode = "error_code"
                case errorMessage = "error_message"
            }
        }

        struct Payload: Decodable {
            struct Output: Decodable {
                struct Sentence: Decodable {
                    let text: String?
                    let heartbeat: Bool?
                    let sentenceEnd: Bool?

                    enum CodingKeys: String, CodingKey {
                        case text
                        case heartbeat
                        case sentenceEnd = "sentence_end"
                    }
                }

                let sentence: Sentence?
            }

            let output: Output?
        }

        let header: Header
        let payload: Payload?
    }
}

public enum AliyunDashScopeWebSocketMessage: Equatable, Sendable {
    case text(String)
    case data(Data)
}

public protocol AliyunDashScopeWebSocketConnection: Sendable {
    func sendData(_ data: Data) async throws
    func sendText(_ text: String) async throws
    func receive() async throws -> AliyunDashScopeWebSocketMessage
    func close()
}

public protocol AliyunDashScopeWebSocketTransport: Sendable {
    func connect(request: URLRequest) async throws -> any AliyunDashScopeWebSocketConnection
}

public struct URLSessionAliyunDashScopeWebSocketTransport: AliyunDashScopeWebSocketTransport {
    public init() {}

    public func connect(request: URLRequest) async throws -> any AliyunDashScopeWebSocketConnection {
        let task = URLSession.shared.webSocketTask(with: request)
        task.resume()
        return URLSessionAliyunDashScopeWebSocketConnection(task: task)
    }
}

private final class URLSessionAliyunDashScopeWebSocketConnection: AliyunDashScopeWebSocketConnection, @unchecked Sendable {
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

    func receive() async throws -> AliyunDashScopeWebSocketMessage {
        switch try await task.receive() {
        case .string(let text):
            return .text(text)
        case .data(let data):
            return .data(data)
        @unknown default:
            throw AliyunDashScopeRealtimeASRError.invalidMessage
        }
    }

    func close() {
        task.cancel(with: .normalClosure, reason: nil)
    }
}

public protocol AliyunDashScopeRealtimeASRStreamingClient: CloudASRStreamingClient
where Configuration == AliyunDashScopeRealtimeASRConfiguration, Message == AliyunDashScopeRealtimeASRMessage {}

public final class AliyunDashScopeRealtimeASRClient: AliyunDashScopeRealtimeASRStreamingClient, @unchecked Sendable {
    private let transport: any AliyunDashScopeWebSocketTransport
    private let taskIDGenerator: @Sendable () -> UUID

    public init(
        transport: any AliyunDashScopeWebSocketTransport = URLSessionAliyunDashScopeWebSocketTransport(),
        taskIDGenerator: @escaping @Sendable () -> UUID = UUID.init
    ) {
        self.transport = transport
        self.taskIDGenerator = taskIDGenerator
    }

    public func transcribe(
        configuration: AliyunDashScopeRealtimeASRConfiguration,
        audioChunks: AsyncStream<Data>,
        onMessage: @escaping @Sendable (AliyunDashScopeRealtimeASRMessage) -> Void
    ) async throws {
        guard configuration.isComplete else {
            throw AliyunDashScopeRealtimeASRError.missingCredential
        }
        let taskID = taskIDGenerator()
        let connection = try await transport.connect(request: request(for: configuration))
        defer { connection.close() }

        let runTask = try AliyunDashScopeRealtimeASRRequest.runTask(
            configuration: configuration,
            taskID: taskID,
            sampleRate: 16_000
        )
        try await connection.sendText(runTask.encodedText())
        let started = try await receiveDecodedMessage(
            from: connection,
            timeoutSeconds: configuration.timeoutSeconds
        )
        onMessage(started)
        guard started.event == .taskStarted else {
            try validate(started)
            throw AliyunDashScopeRealtimeASRError.taskDidNotStart
        }

        try await runStreamingTasks(
            audioChunks: audioChunks,
            connection: connection,
            taskID: taskID,
            timeoutSeconds: configuration.timeoutSeconds,
            onMessage: onMessage
        )
    }

    public func testConnection(
        configuration: AliyunDashScopeRealtimeASRConfiguration
    ) async throws -> ASRProviderHealthResult {
        guard configuration.isComplete else {
            throw AliyunDashScopeRealtimeASRError.missingCredential
        }
        let startedAt = Date()
        let connection = try await transport.connect(request: request(for: configuration))
        defer { connection.close() }
        let taskID = taskIDGenerator()
        let runTask = try AliyunDashScopeRealtimeASRRequest.runTask(
            configuration: configuration,
            taskID: taskID,
            sampleRate: 16_000
        )
        try await connection.sendText(runTask.encodedText())
        let started = try await receiveDecodedMessage(
            from: connection,
            timeoutSeconds: configuration.timeoutSeconds
        )
        try validate(started)
        guard started.event == .taskStarted else {
            throw AliyunDashScopeRealtimeASRError.taskDidNotStart
        }
        let finishTask = try AliyunDashScopeRealtimeASRRequest.finishTask(taskID: taskID)
        try await connection.sendText(finishTask.encodedText())
        return ASRProviderHealthResult(
            status: .ok,
            message: "阿里云百炼连接正常",
            latencyMS: max(0, Int(Date().timeIntervalSince(startedAt) * 1_000))
        )
    }

    private func request(for configuration: AliyunDashScopeRealtimeASRConfiguration) throws -> URLRequest {
        var request = URLRequest(url: try configuration.endpointURL())
        request.timeoutInterval = configuration.timeoutSeconds
        request.setValue(
            "Bearer \(configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines))",
            forHTTPHeaderField: "Authorization"
        )
        request.setValue("VoxFlow", forHTTPHeaderField: "User-Agent")
        return request
    }

    private func receiveDecodedMessage(
        from connection: any AliyunDashScopeWebSocketConnection,
        timeoutSeconds: Double
    ) async throws -> AliyunDashScopeRealtimeASRMessage {
        try await Self.withTimeout(
            seconds: timeoutSeconds,
            timeoutError: AliyunDashScopeRealtimeASRError.connectionTimedOut,
            onTimeout: {
                connection.close()
            }
        ) {
            switch try await connection.receive() {
            case .text(let text):
                return try AliyunDashScopeRealtimeASRMessage.decode(text)
            case .data(let data):
                return try AliyunDashScopeRealtimeASRMessage.decode(data)
            }
        }
    }

    private func runStreamingTasks(
        audioChunks: AsyncStream<Data>,
        connection: any AliyunDashScopeWebSocketConnection,
        taskID: UUID,
        timeoutSeconds: Double,
        onMessage: @escaping @Sendable (AliyunDashScopeRealtimeASRMessage) -> Void
    ) async throws {
        try await withThrowingTaskGroup(of: StreamingTaskResult.self) { group in
            group.addTask {
                try await self.sendAudioAndFinishTask(
                    audioChunks: audioChunks,
                    connection: connection,
                    taskID: taskID
                )
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

    private func sendAudioAndFinishTask(
        audioChunks: AsyncStream<Data>,
        connection: any AliyunDashScopeWebSocketConnection,
        taskID: UUID
    ) async throws {
        for await chunk in audioChunks {
            try Task.checkCancellation()
            if !chunk.isEmpty {
                try await connection.sendData(chunk)
            }
        }
        try Task.checkCancellation()
        let finishTask = try AliyunDashScopeRealtimeASRRequest.finishTask(taskID: taskID)
        try await connection.sendText(finishTask.encodedText())
    }

    private func receiveMessages(
        from connection: any AliyunDashScopeWebSocketConnection,
        timeoutSeconds: Double,
        onMessage: @escaping @Sendable (AliyunDashScopeRealtimeASRMessage) -> Void
    ) async throws {
        while true {
            try Task.checkCancellation()
            let message = try await receiveDecodedMessage(
                from: connection,
                timeoutSeconds: timeoutSeconds
            )
            onMessage(message)
            try validate(message)
            if message.event == .taskFinished {
                return
            }
        }
    }

    private func validate(_ message: AliyunDashScopeRealtimeASRMessage) throws {
        guard message.event == .taskFailed else { return }
        throw AliyunDashScopeRealtimeASRError.providerError(
            code: message.errorCode ?? "UNKNOWN",
            message: message.errorMessage ?? "Unknown error"
        )
    }

    private enum StreamingTaskResult: Sendable {
        case senderFinished
        case receiverFinished
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
}
