import Foundation
import VoxFlowProviderCloudCore
import zlib

public enum VolcengineRealtimeASRError: Error, LocalizedError, Equatable {
    case missingCredential
    case invalidEndpoint
    case invalidMessage
    case providerError(code: Int, message: String)
    case unsupportedSampleRate(Int)
    case inconsistentSampleRate
    case connectionTimedOut

    public var errorDescription: String? {
        switch self {
        case .missingCredential:
            return "未配置火山云 App ID、Access Token 或 Secret Key。"
        case .invalidEndpoint:
            return "火山云豆包流式语音识别地址无效。"
        case .invalidMessage:
            return "火山云豆包流式语音识别返回了无效消息。"
        case let .providerError(code, message):
            return "火山云豆包流式语音识别失败（\(code)）：\(message)"
        case let .unsupportedSampleRate(sampleRate):
            return "火山云豆包流式语音识别当前仅提交 16k PCM，收到 \(sampleRate)Hz 音频。"
        case .inconsistentSampleRate:
            return "录音采样率发生变化，无法提交火山云豆包流式识别。"
        case .connectionTimedOut:
            return "火山云豆包流式语音识别连接超时。"
        }
    }
}

public struct VolcengineRealtimeASRConfiguration: Equatable, Sendable {
    public static let defaultEndpoint = "wss://openspeech.bytedance.com/api/v3/sauc/bigmodel"
    public static let defaultResourceID = "volc.bigasr.sauc.duration"
    public static let defaultModelName = "bigmodel"

    public let appID: String
    public let accessToken: String
    public let secretKey: String
    public let resourceID: String
    public let endpoint: String
    public let modelName: String
    public let timeoutSeconds: Double

    public init(
        appID: String,
        accessToken: String,
        secretKey: String,
        resourceID: String = Self.defaultResourceID,
        endpoint: String = Self.defaultEndpoint,
        modelName: String = Self.defaultModelName,
        timeoutSeconds: Double = 30
    ) {
        self.appID = appID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.accessToken = accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        self.secretKey = secretKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.resourceID = resourceID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.endpoint = endpoint
        self.modelName = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.timeoutSeconds = timeoutSeconds
    }

    public var isComplete: Bool {
        !appID.isEmpty && !accessToken.isEmpty && !secretKey.isEmpty && !resourceID.isEmpty && !modelName.isEmpty
    }

    public func endpointURL() throws -> URL {
        guard let url = URL(string: endpoint),
              url.scheme == "wss",
              url.host != nil else {
            throw VolcengineRealtimeASRError.invalidEndpoint
        }
        return url
    }
}

public struct VolcengineRealtimeASRRequest: Codable, Equatable, Sendable {
    public struct User: Codable, Equatable, Sendable {
        public let uid: String
    }

    public struct Audio: Codable, Equatable, Sendable {
        public let format: String
        public let codec: String
        public let rate: Int
        public let bits: Int
        public let channel: Int
    }

    public struct Request: Codable, Equatable, Sendable {
        public let modelName: String
        public let enablePunc: Bool
        public let resultType: String

        enum CodingKeys: String, CodingKey {
            case modelName = "model_name"
            case enablePunc = "enable_punc"
            case resultType = "result_type"
        }
    }

    public let user: User
    public let audio: Audio
    public let request: Request

    public static func start(
        configuration: VolcengineRealtimeASRConfiguration,
        sampleRate: Int = 16_000
    ) -> VolcengineRealtimeASRRequest {
        VolcengineRealtimeASRRequest(
            user: User(uid: "VoxFlow"),
            audio: Audio(
                format: "pcm",
                codec: "raw",
                rate: sampleRate,
                bits: 16,
                channel: 1
            ),
            request: Request(
                modelName: configuration.modelName,
                enablePunc: true,
                resultType: "full"
            )
        )
    }

    public func encodedData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }
}

public struct VolcengineRealtimeASRFrame: Equatable, Sendable {
    public enum MessageType: UInt8, Sendable {
        case fullClientRequest = 0x1
        case audioOnlyRequest = 0x2
        case fullServerResponse = 0x9
        case serverAck = 0xB
        case serverErrorResponse = 0xF
    }

    public enum MessageFlags: UInt8, Sendable {
        case noSequence = 0x0
        case positiveSequence = 0x1
        case negativeSequence = 0x2
        case negativeSequenceOne = 0x3
    }

    private static let protocolVersion: UInt8 = 0x1
    private static let headerSizeWords: UInt8 = 0x1
    private static let serializationNone: UInt8 = 0x0
    private static let serializationJSON: UInt8 = 0x1
    private static let compressionNone: UInt8 = 0x0
    private static let compressionGzip: UInt8 = 0x1

    public let messageType: MessageType
    public let flags: MessageFlags
    public let sequence: Int32?
    public let payload: Data

    public var isFinalResponse: Bool {
        flags == .negativeSequence || flags == .negativeSequenceOne
    }

    public static func fullClientRequest(payload: Data, sequence: Int32 = 1) -> Data {
        encode(
            messageType: .fullClientRequest,
            flags: .positiveSequence,
            sequence: sequence,
            payload: payload,
            serialization: serializationJSON,
            compression: compressionGzip
        )
    }

    public static func audioOnlyRequest(payload: Data, sequence: Int32) -> Data {
        encode(
            messageType: .audioOnlyRequest,
            flags: .positiveSequence,
            sequence: sequence,
            payload: payload,
            serialization: serializationNone,
            compression: compressionGzip
        )
    }

    public static func finalAudioOnlyRequest(sequence: Int32) -> Data {
        encode(
            messageType: .audioOnlyRequest,
            flags: .negativeSequence,
            sequence: nil,
            payload: Data(),
            serialization: serializationNone,
            compression: compressionNone
        )
    }

    public static func fullServerResponse(payload: Data, sequence: Int32 = 1) -> Data {
        encode(
            messageType: .fullServerResponse,
            flags: .positiveSequence,
            sequence: sequence,
            payload: payload,
            serialization: serializationJSON,
            compression: compressionGzip
        )
    }

    public static func decode(_ data: Data) throws -> VolcengineRealtimeASRFrame {
        guard data.count >= 4 else {
            throw VolcengineRealtimeASRError.invalidMessage
        }
        let bytes = [UInt8](data)
        let headerSize = Int(bytes[0] & 0x0F) * 4
        guard headerSize >= 4, data.count >= headerSize else {
            throw VolcengineRealtimeASRError.invalidMessage
        }
        guard let messageType = MessageType(rawValue: bytes[1] >> 4),
              let flags = MessageFlags(rawValue: bytes[1] & 0x0F) else {
            throw VolcengineRealtimeASRError.invalidMessage
        }
        let compression = bytes[2] & 0x0F
        guard compression == compressionNone || compression == compressionGzip else {
            throw VolcengineRealtimeASRError.invalidMessage
        }

        var cursor = headerSize
        let sequence: Int32?
        if flags == .positiveSequence || flags == .negativeSequenceOne {
            guard data.count >= cursor + 4 else {
                throw VolcengineRealtimeASRError.invalidMessage
            }
            sequence = readInt32(from: bytes, at: cursor)
            cursor += 4
        } else {
            sequence = nil
        }

        guard data.count >= cursor + 4 else {
            return VolcengineRealtimeASRFrame(
                messageType: messageType,
                flags: flags,
                sequence: sequence,
                payload: Data()
            )
        }
        let payloadSize = Int(readUInt32(from: bytes, at: cursor))
        cursor += 4
        guard data.count >= cursor + payloadSize else {
            throw VolcengineRealtimeASRError.invalidMessage
        }
        let encodedPayload = payloadSize == 0 ? Data() : data[cursor..<(cursor + payloadSize)]
        let payload = compression == compressionGzip
            ? try GzipCoding.decompress(Data(encodedPayload))
            : Data(encodedPayload)
        return VolcengineRealtimeASRFrame(
            messageType: messageType,
            flags: flags,
            sequence: sequence,
            payload: Data(payload)
        )
    }

    private static func encode(
        messageType: MessageType,
        flags: MessageFlags,
        sequence: Int32?,
        payload: Data,
        serialization: UInt8,
        compression: UInt8
    ) -> Data {
        var actualCompression = compression
        let encodedPayload: Data
        if compression == compressionGzip {
            if let compressed = try? GzipCoding.compress(payload) {
                encodedPayload = compressed
            } else {
                actualCompression = compressionNone
                encodedPayload = payload
            }
        } else {
            encodedPayload = payload
        }
        var data = Data()
        data.append((protocolVersion << 4) | headerSizeWords)
        data.append((messageType.rawValue << 4) | flags.rawValue)
        data.append((serialization << 4) | actualCompression)
        data.append(0)
        if let sequence {
            data.appendInt32(sequence)
        }
        data.appendUInt32(UInt32(encodedPayload.count))
        data.append(encodedPayload)
        return data
    }

    private static func readUInt32(from bytes: [UInt8], at offset: Int) -> UInt32 {
        UInt32(bytes[offset]) << 24
            | UInt32(bytes[offset + 1]) << 16
            | UInt32(bytes[offset + 2]) << 8
            | UInt32(bytes[offset + 3])
    }

    private static func readInt32(from bytes: [UInt8], at offset: Int) -> Int32 {
        Int32(bitPattern: readUInt32(from: bytes, at: offset))
    }
}

public struct VolcengineRealtimeASRMessage: Equatable, Sendable {
    public let transcript: String
    public let isFinal: Bool
    public let errorCode: Int?
    public let errorMessage: String?

    public static func decode(_ frame: VolcengineRealtimeASRFrame) throws -> VolcengineRealtimeASRMessage {
        if frame.messageType == .serverAck {
            return VolcengineRealtimeASRMessage(transcript: "", isFinal: false, errorCode: nil, errorMessage: nil)
        }
        if frame.messageType == .serverErrorResponse {
            let payload = try? JSONDecoder().decode(ErrorPayload.self, from: frame.payload)
            return VolcengineRealtimeASRMessage(
                transcript: "",
                isFinal: true,
                errorCode: payload?.code ?? -1,
                errorMessage: payload?.message ?? "Unknown error"
            )
        }
        guard frame.messageType == .fullServerResponse else {
            throw VolcengineRealtimeASRError.invalidMessage
        }
        let payload = try JSONDecoder().decode(ResponsePayload.self, from: frame.payload)
        return VolcengineRealtimeASRMessage(
            transcript: payload.bestText,
            isFinal: frame.isFinalResponse || payload.isFinal,
            errorCode: payload.errorCode,
            errorMessage: payload.errorMessage
        )
    }

    private struct ErrorPayload: Decodable {
        let code: Int?
        let message: String?
    }

    private struct ResponsePayload: Decodable {
        struct Result: Decodable {
            let text: String?
        }

        struct Payload: Decodable {
            let result: Result?
            let text: String?
        }

        let result: Result?
        let payload: Payload?
        let text: String?
        let code: Int?
        let message: String?
        let isFinalValue: Bool?

        enum CodingKeys: String, CodingKey {
            case result
            case payload
            case text
            case code
            case message
            case isFinalValue = "is_final"
        }

        var bestText: String {
            result?.text ?? payload?.result?.text ?? payload?.text ?? text ?? ""
        }

        var isFinal: Bool {
            isFinalValue ?? false
        }

        var errorCode: Int? {
            guard let code, code != 0 else { return nil }
            return code
        }

        var errorMessage: String? {
            guard errorCode != nil else { return nil }
            return message
        }
    }
}

public enum VolcengineRealtimeWebSocketMessage: Equatable, Sendable {
    case data(Data)
}

public protocol VolcengineRealtimeWebSocketConnection: Sendable {
    func sendData(_ data: Data) async throws
    func receive() async throws -> VolcengineRealtimeWebSocketMessage
    func close()
}

public protocol VolcengineRealtimeWebSocketTransport: Sendable {
    func connect(request: URLRequest) async throws -> any VolcengineRealtimeWebSocketConnection
}

public struct URLSessionVolcengineRealtimeWebSocketTransport: VolcengineRealtimeWebSocketTransport {
    public init() {}

    public func connect(request: URLRequest) async throws -> any VolcengineRealtimeWebSocketConnection {
        let task = URLSession.shared.webSocketTask(with: request)
        task.resume()
        return URLSessionVolcengineRealtimeWebSocketConnection(task: task)
    }
}

private final class URLSessionVolcengineRealtimeWebSocketConnection: VolcengineRealtimeWebSocketConnection, @unchecked Sendable {
    private let task: URLSessionWebSocketTask

    init(task: URLSessionWebSocketTask) {
        self.task = task
    }

    func sendData(_ data: Data) async throws {
        try await task.send(.data(data))
    }

    func receive() async throws -> VolcengineRealtimeWebSocketMessage {
        switch try await task.receive() {
        case .data(let data):
            return .data(data)
        case .string(let text):
            return .data(Data(text.utf8))
        @unknown default:
            throw VolcengineRealtimeASRError.invalidMessage
        }
    }

    func close() {
        task.cancel(with: .normalClosure, reason: nil)
    }
}

public protocol VolcengineRealtimeASRStreamingClient: CloudASRStreamingClient
where Configuration == VolcengineRealtimeASRConfiguration, Message == VolcengineRealtimeASRMessage {}

public final class VolcengineRealtimeASRClient: VolcengineRealtimeASRStreamingClient, @unchecked Sendable {
    private let transport: any VolcengineRealtimeWebSocketTransport
    private let connectID: @Sendable () -> String

    public init(
        transport: any VolcengineRealtimeWebSocketTransport = URLSessionVolcengineRealtimeWebSocketTransport(),
        connectID: @escaping @Sendable () -> String = { UUID().uuidString }
    ) {
        self.transport = transport
        self.connectID = connectID
    }

    public func testConnection(
        configuration: VolcengineRealtimeASRConfiguration
    ) async throws -> ASRProviderHealthResult {
        guard configuration.isComplete else {
            throw VolcengineRealtimeASRError.missingCredential
        }
        let startedAt = Date()
        let connection = try await transport.connect(request: request(for: configuration))
        defer { connection.close() }
        try await connection.sendData(
            VolcengineRealtimeASRFrame.fullClientRequest(
                payload: try VolcengineRealtimeASRRequest.start(configuration: configuration).encodedData()
            )
        )
        try await Self.sendSilenceProbe(to: connection)
        try await receiveMessages(
            from: connection,
            timeoutSeconds: configuration.timeoutSeconds,
            onMessage: { _ in }
        )
        return ASRProviderHealthResult(
            status: .ok,
            message: "火山云豆包流式语音识别连接正常",
            latencyMS: max(0, Int(Date().timeIntervalSince(startedAt) * 1_000))
        )
    }

    private static func sendSilenceProbe(to connection: any VolcengineRealtimeWebSocketConnection) async throws {
        let chunk = Data(repeating: 0, count: 6_400)
        var sequence: Int32 = 2
        for _ in 0..<3 {
            try await connection.sendData(
                VolcengineRealtimeASRFrame.audioOnlyRequest(payload: chunk, sequence: sequence)
            )
            sequence += 1
            try? await Task.sleep(nanoseconds: 120_000_000)
        }
        try await connection.sendData(
            VolcengineRealtimeASRFrame.finalAudioOnlyRequest(sequence: sequence)
        )
    }

    public func transcribe(
        configuration: VolcengineRealtimeASRConfiguration,
        audioChunks: AsyncStream<Data>,
        onMessage: @escaping @Sendable (VolcengineRealtimeASRMessage) -> Void
    ) async throws {
        guard configuration.isComplete else {
            throw VolcengineRealtimeASRError.missingCredential
        }
        let connection = try await transport.connect(request: request(for: configuration))
        defer { connection.close() }
        try await connection.sendData(
            VolcengineRealtimeASRFrame.fullClientRequest(
                payload: try VolcengineRealtimeASRRequest.start(configuration: configuration).encodedData()
            )
        )

        try await runStreamingTasks(
            audioChunks: audioChunks,
            connection: connection,
            timeoutSeconds: configuration.timeoutSeconds,
            onMessage: onMessage
        )
    }

    private func request(for configuration: VolcengineRealtimeASRConfiguration) throws -> URLRequest {
        var request = URLRequest(url: try configuration.endpointURL())
        request.timeoutInterval = configuration.timeoutSeconds
        request.setValue(configuration.appID, forHTTPHeaderField: "X-Api-App-Key")
        request.setValue(configuration.accessToken, forHTTPHeaderField: "X-Api-Access-Key")
        request.setValue(configuration.resourceID, forHTTPHeaderField: "X-Api-Resource-Id")
        request.setValue(connectID(), forHTTPHeaderField: "X-Api-Connect-Id")
        request.setValue("VoxFlow", forHTTPHeaderField: "User-Agent")
        return request
    }

    private func runStreamingTasks(
        audioChunks: AsyncStream<Data>,
        connection: any VolcengineRealtimeWebSocketConnection,
        timeoutSeconds: Double,
        onMessage: @escaping @Sendable (VolcengineRealtimeASRMessage) -> Void
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

    private func send(
        audioChunks: AsyncStream<Data>,
        to connection: any VolcengineRealtimeWebSocketConnection
    ) async throws {
        var sequence: Int32 = 2
        for await chunk in audioChunks where !chunk.isEmpty {
            try Task.checkCancellation()
            try await connection.sendData(
                VolcengineRealtimeASRFrame.audioOnlyRequest(payload: chunk, sequence: sequence)
            )
            sequence += 1
        }
        try Task.checkCancellation()
        try await connection.sendData(
            VolcengineRealtimeASRFrame.finalAudioOnlyRequest(sequence: sequence)
        )
    }

    private func receiveMessages(
        from connection: any VolcengineRealtimeWebSocketConnection,
        timeoutSeconds: Double,
        onMessage: @escaping @Sendable (VolcengineRealtimeASRMessage) -> Void
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
        from connection: any VolcengineRealtimeWebSocketConnection,
        timeoutSeconds: Double
    ) async throws -> VolcengineRealtimeASRMessage {
        try await Self.withTimeout(
            seconds: timeoutSeconds,
            timeoutError: VolcengineRealtimeASRError.connectionTimedOut,
            onTimeout: {
                connection.close()
            }
        ) {
            switch try await connection.receive() {
            case .data(let data):
                return try VolcengineRealtimeASRMessage.decode(
                    VolcengineRealtimeASRFrame.decode(data)
                )
            }
        }
    }

    private func validate(_ message: VolcengineRealtimeASRMessage) throws {
        if let code = message.errorCode {
            throw VolcengineRealtimeASRError.providerError(
                code: code,
                message: message.errorMessage ?? "Unknown error"
            )
        }
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

private enum GzipCoding {
    private static let chunkSize = 16_384

    static func compress(_ data: Data) throws -> Data {
        guard !data.isEmpty else { return Data() }

        var stream = z_stream()
        guard deflateInit2_(
            &stream,
            Z_DEFAULT_COMPRESSION,
            Z_DEFLATED,
            MAX_WBITS + 16,
            8,
            Z_DEFAULT_STRATEGY,
            ZLIB_VERSION,
            Int32(MemoryLayout<z_stream>.size)
        ) == Z_OK else {
            throw VolcengineRealtimeASRError.invalidMessage
        }
        defer { deflateEnd(&stream) }

        return try data.withUnsafeBytes { inputBuffer in
            stream.next_in = UnsafeMutablePointer<Bytef>(
                mutating: inputBuffer.bindMemory(to: Bytef.self).baseAddress
            )
            stream.avail_in = uInt(data.count)

            var output = Data()
            var buffer = [UInt8](repeating: 0, count: chunkSize)
            let bufferCount = buffer.count
            while true {
                let status = buffer.withUnsafeMutableBytes { outputBuffer in
                    stream.next_out = outputBuffer.bindMemory(to: Bytef.self).baseAddress
                    stream.avail_out = uInt(bufferCount)
                    return deflate(&stream, Z_FINISH)
                }
                guard status == Z_OK || status == Z_STREAM_END else {
                    throw VolcengineRealtimeASRError.invalidMessage
                }
                let produced = bufferCount - Int(stream.avail_out)
                if produced > 0 {
                    output.append(buffer, count: produced)
                }
                if status == Z_STREAM_END {
                    return output
                }
            }
        }
    }

    static func decompress(_ data: Data) throws -> Data {
        guard !data.isEmpty else { return Data() }

        var stream = z_stream()
        guard inflateInit2_(
            &stream,
            MAX_WBITS + 16,
            ZLIB_VERSION,
            Int32(MemoryLayout<z_stream>.size)
        ) == Z_OK else {
            throw VolcengineRealtimeASRError.invalidMessage
        }
        defer { inflateEnd(&stream) }

        return try data.withUnsafeBytes { inputBuffer in
            stream.next_in = UnsafeMutablePointer<Bytef>(
                mutating: inputBuffer.bindMemory(to: Bytef.self).baseAddress
            )
            stream.avail_in = uInt(data.count)

            var output = Data()
            var buffer = [UInt8](repeating: 0, count: chunkSize)
            let bufferCount = buffer.count
            while true {
                let status = buffer.withUnsafeMutableBytes { outputBuffer in
                    stream.next_out = outputBuffer.bindMemory(to: Bytef.self).baseAddress
                    stream.avail_out = uInt(bufferCount)
                    return inflate(&stream, Z_NO_FLUSH)
                }
                guard status == Z_OK || status == Z_STREAM_END else {
                    throw VolcengineRealtimeASRError.invalidMessage
                }
                let produced = bufferCount - Int(stream.avail_out)
                if produced > 0 {
                    output.append(buffer, count: produced)
                }
                if status == Z_STREAM_END {
                    return output
                }
                if produced == 0, stream.avail_in == 0 {
                    throw VolcengineRealtimeASRError.invalidMessage
                }
            }
        }
    }
}

private extension Data {
    mutating func appendUInt32(_ value: UInt32) {
        append(UInt8((value >> 24) & 0xFF))
        append(UInt8((value >> 16) & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8(value & 0xFF))
    }

    mutating func appendInt32(_ value: Int32) {
        appendUInt32(UInt32(bitPattern: value))
    }
}
