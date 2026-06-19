import Foundation
import VoxFlowProviderAliyunDashScope
import VoxFlowProviderCloudCore
import VoxFlowProviderTencentCloud
import XCTest
@testable import VoxFlowApp

final class CloudStreamingEngineTranscriptTests: XCTestCase {
    func testTencentUnstablePartialKeepsStablePrefixFromEarlierSegments() throws {
        let client = CapturingTencentStreamingClient()
        let engine = TencentRealtimeASREngine(
            client: client,
            configurationProvider: {
                TencentRealtimeASRConfiguration(
                    appID: "1259220000",
                    secretID: "AKID",
                    secretKey: "SECRET"
                )
            }
        )
        let emissions = LockedCloudStreamingEmissions()
        engine.onTranscription = { text, isFinal in
            emissions.append(text: text, isFinal: isFinal)
        }

        try engine.start()
        client.waitUntilReady()
        client.emit(try TencentRealtimeASRMessage.decode(
            #"{"code":0,"message":"success","result":{"slice_type":2,"index":0,"voice_text_str":"第一句。"}}"#
        ))
        client.emit(try TencentRealtimeASRMessage.decode(
            #"{"code":0,"message":"success","result":{"slice_type":1,"index":1,"voice_text_str":"第二句正在说"}}"#
        ))
        drainMainQueue()

        XCTAssertEqual(emissions.values.map(\.text), ["第一句。", "第一句。第二句正在说"])
        XCTAssertEqual(emissions.values.map(\.isFinal), [false, false])
        engine.cancel()
    }

    func testAliyunFinalSentencesAccumulateInsteadOfReplacingEarlierSentence() throws {
        let client = CapturingAliyunStreamingClient()
        let engine = AliyunDashScopeRealtimeASREngine(
            client: client,
            configurationProvider: {
                AliyunDashScopeRealtimeASRConfiguration(apiKey: "sk-test")
            }
        )
        let emissions = LockedCloudStreamingEmissions()
        engine.onTranscription = { text, isFinal in
            emissions.append(text: text, isFinal: isFinal)
        }

        try engine.start()
        client.waitUntilReady()
        client.emit(try AliyunDashScopeRealtimeASRMessage.decode(
            #"{"header":{"task_id":"task","event":"result-generated"},"payload":{"output":{"sentence":{"text":"第一句。","heartbeat":false,"sentence_end":true}}}}"#
        ))
        client.emit(try AliyunDashScopeRealtimeASRMessage.decode(
            #"{"header":{"task_id":"task","event":"result-generated"},"payload":{"output":{"sentence":{"text":"第二句","heartbeat":false,"sentence_end":false}}}}"#
        ))
        drainMainQueue()

        XCTAssertEqual(emissions.values.map(\.text), ["第一句。", "第一句。第二句"])
        XCTAssertEqual(emissions.values.map(\.isFinal), [false, false])
        engine.cancel()
    }
}

private final class CapturingTencentStreamingClient: TencentRealtimeASRStreamingClient, @unchecked Sendable {
    private let lock = NSLock()
    private var callback: (@Sendable (TencentRealtimeASRMessage) -> Void)?

    func testConnection(configuration: TencentRealtimeASRConfiguration) async throws -> ASRProviderHealthResult {
        ASRProviderHealthResult(status: .ok, message: "OK", latencyMS: 1)
    }

    func transcribe(
        configuration: TencentRealtimeASRConfiguration,
        audioChunks: AsyncStream<Data>,
        onMessage: @escaping @Sendable (TencentRealtimeASRMessage) -> Void
    ) async throws {
        lock.withLock {
            callback = onMessage
        }
        for await _ in audioChunks {}
    }

    func emit(_ message: TencentRealtimeASRMessage) {
        lock.withLock { callback }?(message)
    }

    func waitUntilReady() {
        while lock.withLock({ callback == nil }) {
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.001))
        }
    }
}

private final class CapturingAliyunStreamingClient: AliyunDashScopeRealtimeASRStreamingClient, @unchecked Sendable {
    private let lock = NSLock()
    private var callback: (@Sendable (AliyunDashScopeRealtimeASRMessage) -> Void)?

    func transcribe(
        configuration: AliyunDashScopeRealtimeASRConfiguration,
        audioChunks: AsyncStream<Data>,
        onMessage: @escaping @Sendable (AliyunDashScopeRealtimeASRMessage) -> Void
    ) async throws {
        lock.withLock {
            callback = onMessage
        }
        for await _ in audioChunks {}
    }

    func testConnection(
        configuration: AliyunDashScopeRealtimeASRConfiguration
    ) async throws -> ASRProviderHealthResult {
        ASRProviderHealthResult(status: .ok, message: "OK", latencyMS: 1)
    }

    func emit(_ message: AliyunDashScopeRealtimeASRMessage) {
        lock.withLock { callback }?(message)
    }

    func waitUntilReady() {
        while lock.withLock({ callback == nil }) {
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.001))
        }
    }
}

private final class LockedCloudStreamingEmissions: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [(text: String, isFinal: Bool)] = []

    var values: [(text: String, isFinal: Bool)] {
        lock.withLock { storage }
    }

    func append(text: String, isFinal: Bool) {
        lock.withLock {
            storage.append((text, isFinal))
        }
    }
}

private func drainMainQueue() {
    RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
}
