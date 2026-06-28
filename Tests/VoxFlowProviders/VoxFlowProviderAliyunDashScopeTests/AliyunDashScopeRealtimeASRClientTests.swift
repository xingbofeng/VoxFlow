import Foundation
import VoxFlowProviderAliyunDashScope
import XCTest

final class AliyunDashScopeRealtimeASRClientTests: XCTestCase {
    func testRunTaskAndFinishTaskPayloadsUseDashScopeRealtimeASRProtocol() throws {
        let configuration = AliyunDashScopeRealtimeASRConfiguration(
            apiKey: "sk-test",
            model: "fun-asr-realtime"
        )
        let taskID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!

        let runTask = try AliyunDashScopeRealtimeASRRequest.runTask(
            configuration: configuration,
            taskID: taskID,
            sampleRate: 16_000
        )
        let finishTask = try AliyunDashScopeRealtimeASRRequest.finishTask(taskID: taskID)

        XCTAssertEqual(runTask.header.action, "run-task")
        XCTAssertEqual(runTask.header.taskID, taskID.uuidString)
        XCTAssertEqual(runTask.header.streaming, "duplex")
        XCTAssertEqual(runTask.payload.taskGroup, "audio")
        XCTAssertEqual(runTask.payload.task, "asr")
        XCTAssertEqual(runTask.payload.function, "recognition")
        XCTAssertEqual(runTask.payload.model, "fun-asr-realtime")
        XCTAssertEqual(runTask.payload.parameters?.format, "pcm")
        XCTAssertEqual(runTask.payload.parameters?.sampleRate, 16_000)
        XCTAssertEqual(runTask.payload.parameters?.punctuationPredictionEnabled, true)
        XCTAssertNil(runTask.payload.parameters?.vocabularyID)
        XCTAssertEqual(finishTask.header.action, "finish-task")
        XCTAssertEqual(finishTask.header.taskID, taskID.uuidString)
        XCTAssertNil(finishTask.payload.parameters)
    }

    func testRunTaskPayloadIncludesConfiguredVocabularyID() throws {
        let configuration = AliyunDashScopeRealtimeASRConfiguration(
            apiKey: "sk-test",
            model: "fun-asr-realtime",
            vocabularyID: "vocab-123"
        )

        let runTask = try AliyunDashScopeRealtimeASRRequest.runTask(
            configuration: configuration,
            taskID: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            sampleRate: 16_000
        )

        XCTAssertEqual(runTask.payload.parameters?.vocabularyID, "vocab-123")
    }

    func testParsesDashScopeServerEvents() throws {
        let started = try AliyunDashScopeRealtimeASRMessage.decode(
            #"{"header":{"task_id":"task","event":"task-started","attributes":{}},"payload":{}}"#
        )
        let partial = try AliyunDashScopeRealtimeASRMessage.decode(
            #"{"header":{"task_id":"task","event":"result-generated","attributes":{}},"payload":{"output":{"sentence":{"begin_time":0,"end_time":null,"text":"你好","heartbeat":false,"sentence_end":false}},"usage":null}}"#
        )
        let final = try AliyunDashScopeRealtimeASRMessage.decode(
            #"{"header":{"task_id":"task","event":"result-generated","attributes":{}},"payload":{"output":{"sentence":{"begin_time":0,"end_time":1200,"text":"你好，码上写。","heartbeat":false,"sentence_end":true}},"usage":{"duration":2}}}"#
        )
        let finished = try AliyunDashScopeRealtimeASRMessage.decode(
            #"{"header":{"task_id":"task","event":"task-finished","attributes":{}},"payload":{"output":{},"usage":null}}"#
        )

        XCTAssertEqual(started.event, .taskStarted)
        XCTAssertEqual(partial.event, .resultGenerated)
        XCTAssertEqual(partial.transcript, "你好")
        XCTAssertFalse(partial.isFinalResult)
        XCTAssertEqual(final.transcript, "你好，码上写。")
        XCTAssertTrue(final.isFinalResult)
        XCTAssertEqual(finished.event, .taskFinished)
    }

    func testClientHandshakeUsesBearerAuthorizationWithoutLeakingAPIKeyIntoMessages() async throws {
        let transport = CapturingAliyunDashScopeWebSocketTransport()
        let client = AliyunDashScopeRealtimeASRClient(
            transport: transport,
            taskIDGenerator: { UUID(uuidString: "11111111-2222-3333-4444-555555555555")! }
        )
        let configuration = AliyunDashScopeRealtimeASRConfiguration(
            apiKey: "sk-secret",
            model: "fun-asr-realtime"
        )

        try await client.transcribe(
            configuration: configuration,
            audioChunks: AsyncStream { continuation in
                continuation.yield(Data([0, 1, 2, 3]))
                continuation.finish()
            },
            onMessage: { _ in }
        )

        let request = try XCTUnwrap(transport.request)
        XCTAssertEqual(request.url?.absoluteString, "wss://dashscope.aliyuncs.com/api-ws/v1/inference")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-secret")
        XCTAssertFalse(transport.connection.sentTexts.joined().contains("sk-secret"))
        XCTAssertTrue(transport.connection.sentData.contains(Data([0, 1, 2, 3])))
        XCTAssertTrue(transport.connection.sentTexts.contains { $0.contains("\"run-task\"") })
        XCTAssertTrue(transport.connection.sentTexts.contains { $0.contains("\"finish-task\"") })
    }

    func testConnectionSendsRunTaskAndFinishTaskBeforeReportingHealthy() async throws {
        let transport = CapturingAliyunDashScopeWebSocketTransport()
        let client = AliyunDashScopeRealtimeASRClient(
            transport: transport,
            taskIDGenerator: { UUID(uuidString: "11111111-2222-3333-4444-555555555555")! }
        )

        let result = try await client.testConnection(
            configuration: AliyunDashScopeRealtimeASRConfiguration(apiKey: "sk-test")
        )

        XCTAssertEqual(result.status, .ok)
        XCTAssertTrue(transport.connection.sentTexts.contains { $0.contains("\"run-task\"") })
        XCTAssertTrue(transport.connection.sentTexts.contains { $0.contains("\"finish-task\"") })
    }

    func testConnectionFailsWhenRunTaskIsRejectedByProvider() async throws {
        let connection = ScriptedAliyunDashScopeWebSocketConnection(messages: [
            #"{"header":{"task_id":"task","event":"task-failed","error_code":"InvalidApiKey","error_message":"bad key"},"payload":{}}"#
        ])
        let transport = ScriptedAliyunDashScopeWebSocketTransport(connection: connection)
        let client = AliyunDashScopeRealtimeASRClient(
            transport: transport,
            taskIDGenerator: { UUID(uuidString: "11111111-2222-3333-4444-555555555555")! }
        )

        do {
            _ = try await client.testConnection(
                configuration: AliyunDashScopeRealtimeASRConfiguration(apiKey: "bad-key")
            )
            XCTFail("Expected provider error")
        } catch let error as AliyunDashScopeRealtimeASRError {
            XCTAssertEqual(error, .providerError(code: "InvalidApiKey", message: "bad key"))
        }
    }

    func testTranscribeCancelsSenderWhenTaskFinishedArrivesBeforeAudioStreamEnds() async throws {
        let transport = EarlyFinishedAliyunDashScopeWebSocketTransport()
        let client = AliyunDashScopeRealtimeASRClient(
            transport: transport,
            taskIDGenerator: { UUID(uuidString: "11111111-2222-3333-4444-555555555555")! }
        )
        let chunks = Array(repeating: Data([0, 1, 2, 3]), count: 40)

        try await client.transcribe(
            configuration: AliyunDashScopeRealtimeASRConfiguration(apiKey: "sk-test"),
            audioChunks: AsyncStream { continuation in
                for chunk in chunks {
                    continuation.yield(chunk)
                }
                continuation.finish()
            },
            onMessage: { _ in }
        )

        XCTAssertLessThan(transport.connection.sentDataCount, chunks.count)
    }

    func testConnectionTimesOutAndClosesWhenHandshakeReceiveIgnoresCancellation() async throws {
        let connection = CancellationIgnoringAliyunDashScopeWebSocketConnection()
        let transport = HangingAliyunDashScopeWebSocketTransport(connection: connection)
        let client = AliyunDashScopeRealtimeASRClient(
            transport: transport,
            taskIDGenerator: { UUID(uuidString: "11111111-2222-3333-4444-555555555555")! }
        )

        do {
            _ = try await client.testConnection(
                configuration: AliyunDashScopeRealtimeASRConfiguration(
                    apiKey: "sk-test",
                    timeoutSeconds: 0.01
                )
            )
            XCTFail("Expected connection timeout")
        } catch let error as AliyunDashScopeRealtimeASRError {
            XCTAssertEqual(error, .connectionTimedOut)
            XCTAssertTrue(connection.isClosed)
        }
    }
}

private final class CapturingAliyunDashScopeWebSocketTransport: AliyunDashScopeWebSocketTransport, @unchecked Sendable {
    let connection = CapturingAliyunDashScopeWebSocketConnection()
    private(set) var request: URLRequest?

    func connect(request: URLRequest) async throws -> any AliyunDashScopeWebSocketConnection {
        self.request = request
        return connection
    }
}

private final class CapturingAliyunDashScopeWebSocketConnection: AliyunDashScopeWebSocketConnection, @unchecked Sendable {
    private var receiveIndex = 0
    var sentTexts: [String] = []
    var sentData: [Data] = []

    func sendData(_ data: Data) async throws {
        sentData.append(data)
    }

    func sendText(_ text: String) async throws {
        sentTexts.append(text)
    }

    func receive() async throws -> AliyunDashScopeWebSocketMessage {
        let messages = [
            #"{"header":{"task_id":"task","event":"task-started","attributes":{}},"payload":{}}"#,
            #"{"header":{"task_id":"task","event":"result-generated","attributes":{}},"payload":{"output":{"sentence":{"begin_time":0,"end_time":800,"text":"你好，码上写。","heartbeat":false,"sentence_end":true}},"usage":{"duration":1}}}"#,
            #"{"header":{"task_id":"task","event":"task-finished","attributes":{}},"payload":{"output":{},"usage":null}}"#,
        ]
        let message = messages[min(receiveIndex, messages.count - 1)]
        receiveIndex += 1
        return .text(message)
    }

    func close() {}
}

private final class ScriptedAliyunDashScopeWebSocketTransport: AliyunDashScopeWebSocketTransport, @unchecked Sendable {
    let connection: ScriptedAliyunDashScopeWebSocketConnection

    init(connection: ScriptedAliyunDashScopeWebSocketConnection) {
        self.connection = connection
    }

    func connect(request: URLRequest) async throws -> any AliyunDashScopeWebSocketConnection {
        connection
    }
}

private final class ScriptedAliyunDashScopeWebSocketConnection: AliyunDashScopeWebSocketConnection, @unchecked Sendable {
    private let lock = NSLock()
    private var messages: [String]
    private(set) var sentTexts: [String] = []

    init(messages: [String]) {
        self.messages = messages
    }

    func sendData(_ data: Data) async throws {}

    func sendText(_ text: String) async throws {
        lock.withLock { sentTexts.append(text) }
    }

    func receive() async throws -> AliyunDashScopeWebSocketMessage {
        try lock.withLock {
            guard !messages.isEmpty else {
                throw AliyunDashScopeRealtimeASRError.invalidMessage
            }
            return .text(messages.removeFirst())
        }
    }

    func close() {}
}

private final class EarlyFinishedAliyunDashScopeWebSocketTransport: AliyunDashScopeWebSocketTransport, @unchecked Sendable {
    let connection = EarlyFinishedAliyunDashScopeWebSocketConnection()

    func connect(request: URLRequest) async throws -> any AliyunDashScopeWebSocketConnection {
        connection
    }
}

private final class EarlyFinishedAliyunDashScopeWebSocketConnection: AliyunDashScopeWebSocketConnection, @unchecked Sendable {
    private let lock = NSLock()
    private var receiveIndex = 0
    private var sentDataStorage: [Data] = []

    var sentDataCount: Int {
        lock.withLock { sentDataStorage.count }
    }

    func sendData(_ data: Data) async throws {
        lock.withLock { sentDataStorage.append(data) }
        try await Task.sleep(nanoseconds: 10_000_000)
    }

    func sendText(_ text: String) async throws {}

    func receive() async throws -> AliyunDashScopeWebSocketMessage {
        let index = lock.withLock {
            defer { receiveIndex += 1 }
            return receiveIndex
        }
        if index == 0 {
            return .text(#"{"header":{"task_id":"task","event":"task-started","attributes":{}},"payload":{}}"#)
        }
        return .text(#"{"header":{"task_id":"task","event":"task-finished","attributes":{}},"payload":{"output":{},"usage":null}}"#)
    }

    func close() {}
}

private final class HangingAliyunDashScopeWebSocketTransport: AliyunDashScopeWebSocketTransport, @unchecked Sendable {
    let connection: CancellationIgnoringAliyunDashScopeWebSocketConnection

    init(connection: CancellationIgnoringAliyunDashScopeWebSocketConnection) {
        self.connection = connection
    }

    func connect(request: URLRequest) async throws -> any AliyunDashScopeWebSocketConnection {
        connection
    }
}

private final class CancellationIgnoringAliyunDashScopeWebSocketConnection: AliyunDashScopeWebSocketConnection, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var isClosed = false

    func sendData(_ data: Data) async throws {}

    func sendText(_ text: String) async throws {}

    func receive() async throws -> AliyunDashScopeWebSocketMessage {
        while true {
            do {
                try await Task.sleep(nanoseconds: 10_000_000)
            } catch {
                continue
            }
        }
    }

    func close() {
        lock.withLock { isClosed = true }
    }
}
