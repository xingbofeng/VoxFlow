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
        XCTAssertEqual(finishTask.header.action, "finish-task")
        XCTAssertEqual(finishTask.header.taskID, taskID.uuidString)
        XCTAssertNil(finishTask.payload.parameters)
    }

    func testParsesDashScopeServerEvents() throws {
        let started = try AliyunDashScopeRealtimeASRMessage.decode(
            #"{"header":{"task_id":"task","event":"task-started","attributes":{}},"payload":{}}"#
        )
        let partial = try AliyunDashScopeRealtimeASRMessage.decode(
            #"{"header":{"task_id":"task","event":"result-generated","attributes":{}},"payload":{"output":{"sentence":{"begin_time":0,"end_time":null,"text":"你好","heartbeat":false,"sentence_end":false}},"usage":null}}"#
        )
        let final = try AliyunDashScopeRealtimeASRMessage.decode(
            #"{"header":{"task_id":"task","event":"result-generated","attributes":{}},"payload":{"output":{"sentence":{"begin_time":0,"end_time":1200,"text":"你好，随声写。","heartbeat":false,"sentence_end":true}},"usage":{"duration":2}}}"#
        )
        let finished = try AliyunDashScopeRealtimeASRMessage.decode(
            #"{"header":{"task_id":"task","event":"task-finished","attributes":{}},"payload":{"output":{},"usage":null}}"#
        )

        XCTAssertEqual(started.event, .taskStarted)
        XCTAssertEqual(partial.event, .resultGenerated)
        XCTAssertEqual(partial.transcript, "你好")
        XCTAssertFalse(partial.isFinalResult)
        XCTAssertEqual(final.transcript, "你好，随声写。")
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
            #"{"header":{"task_id":"task","event":"result-generated","attributes":{}},"payload":{"output":{"sentence":{"begin_time":0,"end_time":800,"text":"你好，随声写。","heartbeat":false,"sentence_end":true}},"usage":{"duration":1}}}"#,
            #"{"header":{"task_id":"task","event":"task-finished","attributes":{}},"payload":{"output":{},"usage":null}}"#,
        ]
        let message = messages[min(receiveIndex, messages.count - 1)]
        receiveIndex += 1
        return .text(message)
    }

    func close() {}
}
