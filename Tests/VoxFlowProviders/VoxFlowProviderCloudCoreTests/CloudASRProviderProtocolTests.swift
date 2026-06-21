import Foundation
import VoxFlowProviderCloudCore
import XCTest
@testable import VoxFlowApp

final class CloudASRProviderProtocolTests: XCTestCase {
    func testCloudASRProtocolCarriesConfigurationAndResultShape() async throws {
        let client = StubCloudASRClient()
        let configuration = CloudASRProviderConfiguration(
            providerID: "cloud-asr",
            displayName: "Cloud ASR",
            baseURL: "https://asr.example.com/v1",
            model: "speech-model",
            apiKeyRef: "cloud-asr-key",
            timeoutSeconds: 30
        )

        let health = try await client.testConnection(configuration: configuration)
        let result = try await client.transcribeFile(
            CloudASRFileRequest(
                fileURL: URL(fileURLWithPath: "/tmp/audio.wav"),
                locale: Locale(identifier: "zh_CN"),
                configuration: configuration
            )
        ) { _ in }

        XCTAssertEqual(client.providerID, "cloud-asr")
        XCTAssertEqual(health.status, .ok)
        XCTAssertEqual(result.text, "云端转写结果")
        XCTAssertFalse(configuration.redactedDescription.contains(configuration.apiKeyRef))
    }

    func testRegistryCanRegisterCloudASRDescriptor() {
        let registry = ASRProviderRegistry()
        registry.register(
            ASRProviderDescriptor(
                id: "cloud-asr",
                displayName: "Cloud ASR",
                providerType: "cloud",
                capabilities: [.cloud, .fileTranscription, .multilingual],
                tags: ["cloud", "file", "multilingual"],
                isAvailable: true,
                isDefault: false,
                statusMessage: "可用",
                privacySummary: "音频会发送到用户配置的云端 ASR 服务。",
                modelSize: nil,
                engineType: nil
            )
        )

        let cloudProviders = registry.descriptors(
            matching: ASRProviderFilter(requiredCapabilities: [.cloud], tags: ["cloud"])
        )

        XCTAssertEqual(cloudProviders.map(\.id), ["cloud-asr"])
    }

    func testCloudASRStreamingClientProtocolCarriesConnectionAndMessageContract() async throws {
        let client = StubCloudASRStreamingClient()
        let configuration = CloudASRProviderConfiguration(
            providerID: "streaming-asr",
            displayName: "Streaming ASR",
            baseURL: "https://asr.example.com/realtime",
            model: "realtime-model",
            apiKeyRef: "streaming-key",
            timeoutSeconds: 30
        )
        let recorder = StreamingMessageRecorder()

        let health = try await client.testConnection(configuration: configuration)
        try await client.transcribe(
            configuration: configuration,
            audioChunks: AsyncStream { continuation in
                continuation.yield(Data([0, 1, 2]))
                continuation.finish()
            },
            onMessage: { recorder.append($0) }
        )

        XCTAssertEqual(health.status, .ok)
        XCTAssertEqual(recorder.values(), ["streaming transcript"])
    }
}

private final class StubCloudASRClient: CloudASRProviderClient {
    let providerID = "cloud-asr"
    let displayName = "Cloud ASR"

    func testConnection(
        configuration: CloudASRProviderConfiguration
    ) async throws -> ASRProviderHealthResult {
        ASRProviderHealthResult(status: .ok, message: "OK", latencyMS: 12)
    }

    func transcribeFile(
        _ request: CloudASRFileRequest,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> CloudASRTranscriptionResult {
        progress(1)
        return CloudASRTranscriptionResult(
            text: "云端转写结果",
            durationSeconds: 2.5,
            providerID: providerID,
            warnings: []
        )
    }
}

private final class StubCloudASRStreamingClient: CloudASRStreamingClient {
    func testConnection(
        configuration: CloudASRProviderConfiguration
    ) async throws -> ASRProviderHealthResult {
        ASRProviderHealthResult(status: .ok, message: configuration.displayName, latencyMS: 8)
    }

    func transcribe(
        configuration: CloudASRProviderConfiguration,
        audioChunks: AsyncStream<Data>,
        onMessage: @escaping @Sendable (String) -> Void
    ) async throws {
        for await chunk in audioChunks where !chunk.isEmpty {
            onMessage("streaming transcript")
            return
        }
    }
}

private final class StreamingMessageRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    func append(_ value: String) {
        lock.withLock { storage.append(value) }
    }

    func values() -> [String] {
        lock.withLock { storage }
    }
}
