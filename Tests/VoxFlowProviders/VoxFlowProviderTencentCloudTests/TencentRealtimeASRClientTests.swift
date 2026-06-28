import Foundation
import VoxFlowProviderTencentCloud
import XCTest

final class TencentRealtimeASRClientTests: XCTestCase {
    func testRealtimeURLContainsRequiredQueryAndRedactsSecretKey() throws {
        let signer = TencentRealtimeASRURLSigner(
            appID: "1259220000",
            secretID: "AKIDEXAMPLE",
            secretKey: "SECRETEXAMPLE",
            timestamp: 1_673_408_372,
            expired: 1_673_494_772,
            nonce: 1_673_408_372,
            voiceID: "c64385ee-3e5c-4fc5-bbfd-7c71addb35b0",
            engineModelType: "16k_zh",
            voiceFormat: 1,
            needVAD: 1
        )

        let signedURL = try signer.signedURL()
        let components = try XCTUnwrap(URLComponents(url: signedURL, resolvingAgainstBaseURL: false))
        let items: [URLQueryItem] = components.queryItems ?? []
        let queryItems = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })

        XCTAssertEqual(components.scheme, "wss")
        XCTAssertEqual(components.host, "asr.cloud.tencent.com")
        XCTAssertEqual(components.path, "/asr/v2/1259220000")
        XCTAssertEqual(queryItems["secretid"], "AKIDEXAMPLE")
        XCTAssertEqual(queryItems["engine_model_type"], "16k_zh")
        XCTAssertEqual(queryItems["voice_format"], "1")
        XCTAssertNotNil(queryItems["signature"])
        XCTAssertFalse(signer.redactedDescription.contains("SECRETEXAMPLE"))
        XCTAssertFalse(signedURL.absoluteString.contains("SECRETEXAMPLE"))
    }

    func testRealtimeURLPercentEncodesBase64SignatureReservedCharacters() throws {
        let signer = TencentRealtimeASRURLSigner(
            appID: "1259220000",
            secretID: "AKIDEXAMPLE",
            secretKey: "SECRETEXAMPLE4",
            timestamp: 1_673_408_372,
            expired: 1_673_494_772,
            nonce: 1_673_408_372,
            voiceID: "c64385ee-3e5c-4fc5-bbfd-7c71addb35b0",
            engineModelType: "16k_zh",
            voiceFormat: 1,
            needVAD: 1
        )

        let signedURL = try signer.signedURL()
        let query = try XCTUnwrap(URLComponents(url: signedURL, resolvingAgainstBaseURL: false)?.percentEncodedQuery)

        XCTAssertTrue(query.contains("signature=XK3pBX9JULp%2BNfBx2mHr94h1y%2Bw%3D"))
        XCTAssertFalse(query.contains("+"))
    }

    func testRealtimeURLIncludesHotwordListWhenConfigured() throws {
        let signer = TencentRealtimeASRURLSigner(
            appID: "1259220000",
            secretID: "AKIDEXAMPLE",
            secretKey: "SECRETEXAMPLE",
            timestamp: 1_673_408_372,
            expired: 1_673_494_772,
            nonce: 1_673_408_372,
            voiceID: "c64385ee-3e5c-4fc5-bbfd-7c71addb35b0",
            engineModelType: "16k_zh",
            voiceFormat: 1,
            needVAD: 1,
            hotwordList: "VoxFlow|11,ContextBoost|11"
        )

        let signedURL = try signer.signedURL()
        let components = try XCTUnwrap(URLComponents(url: signedURL, resolvingAgainstBaseURL: false))
        let items: [URLQueryItem] = components.queryItems ?? []
        let queryItems = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })

        XCTAssertEqual(queryItems["hotword_list"], "VoxFlow|11,ContextBoost|11")
    }

    func testParsesPartialStableAndFinalMessages() throws {
        let partial = try TencentRealtimeASRMessage.decode(
            Data(#"{"code":0,"message":"success","voice_id":"v","result":{"slice_type":1,"index":0,"voice_text_str":"实时"}}"#.utf8)
        )
        let stable = try TencentRealtimeASRMessage.decode(
            Data(#"{"code":0,"message":"success","voice_id":"v","result":{"slice_type":2,"index":0,"voice_text_str":"实时语音识别"}}"#.utf8)
        )
        let final = try TencentRealtimeASRMessage.decode(
            Data(#"{"code":0,"message":"success","voice_id":"v","final":1}"#.utf8)
        )

        XCTAssertEqual(partial.transcript, "实时")
        XCTAssertFalse(partial.isStable)
        XCTAssertFalse(partial.isFinal)
        XCTAssertEqual(stable.transcript, "实时语音识别")
        XCTAssertTrue(stable.isStable)
        XCTAssertFalse(stable.isFinal)
        XCTAssertTrue(final.isFinal)
    }

    func testTranscribeCancelsSenderWhenFinalMessageArrivesBeforeAudioStreamEnds() async throws {
        let transport = EarlyFinalTencentRealtimeWebSocketTransport()
        let client = TencentRealtimeASRClient(
            transport: transport,
            clock: { Date(timeIntervalSince1970: 1_673_408_372) },
            nonce: { 1_673_408_372 },
            voiceID: { "c64385ee-3e5c-4fc5-bbfd-7c71addb35b0" }
        )
        let chunks = Array(repeating: Data([0, 1, 2, 3]), count: 40)

        try await client.transcribe(
            configuration: TencentRealtimeASRConfiguration(
                appID: "1259220000",
                secretID: "AKIDEXAMPLE",
                secretKey: "SECRETEXAMPLE"
            ),
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

    func testConnectionUsesConfiguredTimeoutOnWebSocketRequest() async throws {
        let transport = CapturingRequestTencentRealtimeWebSocketTransport(
            connection: ScriptedTencentRealtimeWebSocketConnection(messages: [
                .text(#"{"code":0,"message":"success","voice_id":"v"}"#)
            ])
        )
        let client = TencentRealtimeASRClient(
            transport: transport,
            clock: { Date(timeIntervalSince1970: 1_673_408_372) },
            nonce: { 1_673_408_372 },
            voiceID: { "c64385ee-3e5c-4fc5-bbfd-7c71addb35b0" }
        )

        _ = try await client.testConnection(
            configuration: TencentRealtimeASRConfiguration(
                appID: "1259220000",
                secretID: "AKIDEXAMPLE",
                secretKey: "SECRETEXAMPLE",
                timeoutSeconds: 0.5
            )
        )

        XCTAssertEqual(transport.requests.first?.timeoutInterval, 0.5)
    }

    func testConnectionTimesOutWhenHandshakeNeverArrives() async throws {
        let connection = HangingTencentRealtimeWebSocketConnection()
        let transport = CapturingRequestTencentRealtimeWebSocketTransport(
            connection: connection
        )
        let client = TencentRealtimeASRClient(
            transport: transport,
            clock: { Date(timeIntervalSince1970: 1_673_408_372) },
            nonce: { 1_673_408_372 },
            voiceID: { "c64385ee-3e5c-4fc5-bbfd-7c71addb35b0" }
        )

        do {
            _ = try await client.testConnection(
                configuration: TencentRealtimeASRConfiguration(
                    appID: "1259220000",
                    secretID: "AKIDEXAMPLE",
                    secretKey: "SECRETEXAMPLE",
                    timeoutSeconds: 0.01
                )
            )
            XCTFail("Expected connection timeout")
        } catch let error as TencentRealtimeASRError {
            XCTAssertEqual(error, .connectionTimedOut)
            XCTAssertTrue(connection.isClosed)
        }
    }

    func testTranscribeTimesOutWhenHandshakeNeverArrives() async throws {
        let connection = HangingTencentRealtimeWebSocketConnection()
        let transport = CapturingRequestTencentRealtimeWebSocketTransport(
            connection: connection
        )
        let client = TencentRealtimeASRClient(
            transport: transport,
            clock: { Date(timeIntervalSince1970: 1_673_408_372) },
            nonce: { 1_673_408_372 },
            voiceID: { "c64385ee-3e5c-4fc5-bbfd-7c71addb35b0" }
        )

        do {
            try await client.transcribe(
                configuration: TencentRealtimeASRConfiguration(
                    appID: "1259220000",
                    secretID: "AKIDEXAMPLE",
                    secretKey: "SECRETEXAMPLE",
                    timeoutSeconds: 0.01
                ),
                audioChunks: AsyncStream { continuation in
                    continuation.finish()
                },
                onMessage: { _ in }
            )
            XCTFail("Expected connection timeout")
        } catch let error as TencentRealtimeASRError {
            XCTAssertEqual(error, .connectionTimedOut)
            XCTAssertTrue(connection.isClosed)
        }
    }

    func testHandshakeTimeoutReturnsEvenWhenReceiveIgnoresCancellation() async throws {
        let connection = CancellationIgnoringTencentRealtimeWebSocketConnection()
        let transport = CapturingRequestTencentRealtimeWebSocketTransport(
            connection: connection
        )
        let client = TencentRealtimeASRClient(
            transport: transport,
            clock: { Date(timeIntervalSince1970: 1_673_408_372) },
            nonce: { 1_673_408_372 },
            voiceID: { "c64385ee-3e5c-4fc5-bbfd-7c71addb35b0" }
        )

        do {
            _ = try await client.testConnection(
                configuration: TencentRealtimeASRConfiguration(
                    appID: "1259220000",
                    secretID: "AKIDEXAMPLE",
                    secretKey: "SECRETEXAMPLE",
                    timeoutSeconds: 0.01
                )
            )
            XCTFail("Expected connection timeout")
        } catch let error as TencentRealtimeASRError {
            XCTAssertEqual(error, .connectionTimedOut)
            XCTAssertTrue(connection.isClosed)
        }
    }
}

private final class EarlyFinalTencentRealtimeWebSocketTransport: TencentRealtimeWebSocketTransport, @unchecked Sendable {
    let connection = EarlyFinalTencentRealtimeWebSocketConnection()

    func connect(request: URLRequest) async throws -> any TencentRealtimeWebSocketConnection {
        connection
    }
}

private final class EarlyFinalTencentRealtimeWebSocketConnection: TencentRealtimeWebSocketConnection, @unchecked Sendable {
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

    func receive() async throws -> TencentRealtimeWebSocketMessage {
        let index = lock.withLock {
            defer { receiveIndex += 1 }
            return receiveIndex
        }
        if index == 0 {
            return .text(#"{"code":0,"message":"success","voice_id":"v"}"#)
        }
        return .text(#"{"code":0,"message":"success","voice_id":"v","final":1}"#)
    }

    func close() {}
}

private final class CapturingRequestTencentRealtimeWebSocketTransport: TencentRealtimeWebSocketTransport, @unchecked Sendable {
    let connection: any TencentRealtimeWebSocketConnection
    private let lock = NSLock()
    private var requestStorage: [URLRequest] = []

    init(connection: any TencentRealtimeWebSocketConnection) {
        self.connection = connection
    }

    var requests: [URLRequest] {
        lock.withLock { requestStorage }
    }

    func connect(request: URLRequest) async throws -> any TencentRealtimeWebSocketConnection {
        lock.withLock { requestStorage.append(request) }
        return connection
    }
}

private final class ScriptedTencentRealtimeWebSocketConnection: TencentRealtimeWebSocketConnection, @unchecked Sendable {
    private let lock = NSLock()
    private var messages: [TencentRealtimeWebSocketMessage]
    private(set) var isClosed = false

    init(messages: [TencentRealtimeWebSocketMessage]) {
        self.messages = messages
    }

    func sendData(_ data: Data) async throws {}

    func sendText(_ text: String) async throws {}

    func receive() async throws -> TencentRealtimeWebSocketMessage {
        try lock.withLock {
            guard !messages.isEmpty else {
                throw TencentRealtimeASRError.invalidMessage
            }
            return messages.removeFirst()
        }
    }

    func close() {
        lock.withLock { isClosed = true }
    }
}

private final class HangingTencentRealtimeWebSocketConnection: TencentRealtimeWebSocketConnection, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var isClosed = false

    func sendData(_ data: Data) async throws {}

    func sendText(_ text: String) async throws {}

    func receive() async throws -> TencentRealtimeWebSocketMessage {
        while !Task.isCancelled {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        throw CancellationError()
    }

    func close() {
        lock.withLock { isClosed = true }
    }
}

private final class CancellationIgnoringTencentRealtimeWebSocketConnection: TencentRealtimeWebSocketConnection, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var isClosed = false

    func sendData(_ data: Data) async throws {}

    func sendText(_ text: String) async throws {}

    func receive() async throws -> TencentRealtimeWebSocketMessage {
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
