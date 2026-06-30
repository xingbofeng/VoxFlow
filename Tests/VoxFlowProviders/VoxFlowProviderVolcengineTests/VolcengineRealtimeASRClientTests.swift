import Foundation
import XCTest
import VoxFlowProviderCloudCore
@testable import VoxFlowProviderVolcengine

final class VolcengineRealtimeASRClientTests: XCTestCase {
    func testConnectionUsesOfficialBigModelHeaders() async throws {
        let connection = CapturingVolcengineConnection(messages: [
            .data(VolcengineRealtimeASRFrame.fullServerResponse(payload: #"{"result":{"text":"ok"},"is_final":true}"#.data(using: .utf8)!)),
        ])
        let transport = CapturingVolcengineTransport(connection: connection)
        let client = VolcengineRealtimeASRClient(
            transport: transport,
            connectID: { "connect-id" }
        )
        let configuration = VolcengineRealtimeASRConfiguration(
            appID: "app-id",
            accessToken: "access-token",
            secretKey: "secret-key"
        )

        let result = try await client.testConnection(configuration: configuration)

        XCTAssertEqual(result.status, .ok)
        XCTAssertEqual(transport.request?.value(forHTTPHeaderField: "X-Api-App-Key"), "app-id")
        XCTAssertEqual(transport.request?.value(forHTTPHeaderField: "X-Api-Access-Key"), "access-token")
        XCTAssertEqual(transport.request?.value(forHTTPHeaderField: "X-Api-Resource-Id"), "volc.bigasr.sauc.duration")
        XCTAssertEqual(transport.request?.value(forHTTPHeaderField: "X-Api-Connect-Id"), "connect-id")
        let startData = try XCTUnwrap(connection.sentData.first)
        XCTAssertEqual([UInt8](startData)[2], 0x11)
        let startFrame = try VolcengineRealtimeASRFrame.decode(startData)
        XCTAssertEqual(startFrame.messageType, .fullClientRequest)
        XCTAssertTrue(String(data: startFrame.payload, encoding: .utf8)?.contains(#""model_name":"bigmodel""#) == true)
        XCTAssertTrue(connection.sentData.count >= 3)
        XCTAssertEqual(try VolcengineRealtimeASRFrame.decode(connection.sentData[1]).messageType, .audioOnlyRequest)
        XCTAssertEqual([UInt8](connection.sentData.last!), [0x11, 0x22, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
    }

    func testAudioFrameUsesGzipWithoutJSONSerialization() throws {
        let audio = Data([0x01, 0x02, 0x03, 0x04])

        let frameData = VolcengineRealtimeASRFrame.audioOnlyRequest(payload: audio, sequence: 2)

        XCTAssertEqual([UInt8](frameData)[2], 0x01)
        let frame = try VolcengineRealtimeASRFrame.decode(frameData)
        XCTAssertEqual(frame.messageType, .audioOnlyRequest)
        XCTAssertEqual(frame.payload, audio)
    }

    func testFinalAudioFrameUsesNegativeFlagWithoutSequenceOrCompression() throws {
        let frameData = VolcengineRealtimeASRFrame.finalAudioOnlyRequest(sequence: 21)

        XCTAssertEqual([UInt8](frameData), [0x11, 0x22, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
        let frame = try VolcengineRealtimeASRFrame.decode(frameData)
        XCTAssertEqual(frame.messageType, .audioOnlyRequest)
        XCTAssertTrue(frame.isFinalResponse)
        XCTAssertNil(frame.sequence)
        XCTAssertTrue(frame.payload.isEmpty)
    }
}

private final class CapturingVolcengineTransport: VolcengineRealtimeWebSocketTransport, @unchecked Sendable {
    private let lock = NSLock()
    private let connection: CapturingVolcengineConnection
    private var capturedRequest: URLRequest?

    init(connection: CapturingVolcengineConnection) {
        self.connection = connection
    }

    var request: URLRequest? {
        lock.withLock { capturedRequest }
    }

    func connect(request: URLRequest) async throws -> any VolcengineRealtimeWebSocketConnection {
        lock.withLock {
            capturedRequest = request
        }
        return connection
    }
}

private final class CapturingVolcengineConnection: VolcengineRealtimeWebSocketConnection, @unchecked Sendable {
    private let lock = NSLock()
    private var messages: [VolcengineRealtimeWebSocketMessage]
    private(set) var sentData: [Data] = []
    private(set) var isClosed = false

    init(messages: [VolcengineRealtimeWebSocketMessage]) {
        self.messages = messages
    }

    func sendData(_ data: Data) async throws {
        lock.withLock {
            sentData.append(data)
        }
    }

    func receive() async throws -> VolcengineRealtimeWebSocketMessage {
        try lock.withLock {
            guard !messages.isEmpty else {
                throw VolcengineRealtimeASRError.invalidMessage
            }
            return messages.removeFirst()
        }
    }

    func close() {
        lock.withLock {
            isClosed = true
        }
    }
}
