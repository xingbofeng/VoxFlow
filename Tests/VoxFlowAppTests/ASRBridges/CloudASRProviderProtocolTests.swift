import Foundation
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
        XCTAssertTrue(client.capabilities.contains(.cloud))
        XCTAssertTrue(client.capabilities.contains(.fileTranscription))
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
}

private final class StubCloudASRClient: CloudASRProviderClient {
    let providerID = "cloud-asr"
    let displayName = "Cloud ASR"
    let capabilities: ASRProviderCapabilities = [.cloud, .fileTranscription, .multilingual]

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
