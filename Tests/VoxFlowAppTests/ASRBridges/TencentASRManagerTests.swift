import XCTest
import VoxFlowProviderCloudCore
import VoxFlowProviderTencentCloud
@testable import VoxFlowApp

final class TencentASRManagerTests: XCTestCase {
    func testTencentCloudBecomesSelectableOnlyAfterCredentialsAreConfigured() throws {
        let suiteName = "test.TencentASRManager.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let credentials = TencentManagerCredentialStore()
        let manager = ASRManager(defaults: defaults, credentialStore: credentials)
        let registry = ASRProviderRegistry(asrManager: manager)

        XCTAssertFalse(manager.canSelectEngine(.tencentCloud))
        var descriptor = try XCTUnwrap(registry.descriptor(id: ASRProviderID.tencentCloudASR))
        XCTAssertFalse(descriptor.isAvailable)
        XCTAssertNil(descriptor.engineType)

        try manager.saveTencentCloudCredentials(
            appID: "1259220000",
            secretID: "AKIDEXAMPLE",
            secretKey: "SECRETEXAMPLE"
        )

        XCTAssertTrue(manager.canSelectEngine(.tencentCloud))
        descriptor = try XCTUnwrap(registry.descriptor(id: ASRProviderID.tencentCloudASR))
        XCTAssertTrue(descriptor.isAvailable)
        XCTAssertEqual(descriptor.engineType, .tencentCloud)
        XCTAssertTrue(manager.makeEngine(type: .tencentCloud) is TencentRealtimeASREngine)
        XCTAssertFalse(defaults.dictionaryRepresentation().values.contains { String(describing: $0).contains("SECRETEXAMPLE") })
    }

    func testTencentEnginePassesConfiguredHotwordsToStreamingClient() async throws {
        let client = CapturingTencentRealtimeClient()
        let engine = TencentRealtimeASREngine(
            client: client,
            configurationProvider: {
                TencentRealtimeASRConfiguration(
                    appID: "1259220000",
                    secretID: "AKIDEXAMPLE",
                    secretKey: "SECRETEXAMPLE"
                )
            }
        )

        engine.configureTermPrompt("VoxFlow|11,ContextBoost|11")
        try engine.start()
        try await waitUntil("Tencent client receives hotword_list") {
            client.capturedConfiguration?.hotwordList == "VoxFlow|11,ContextBoost|11"
        }
        engine.cancel()
    }

    private func waitUntil(
        _ description: String,
        timeout: TimeInterval = 1,
        condition: @escaping @Sendable () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Timed out waiting for \(description)")
    }
}

private final class TencentManagerCredentialStore: CredentialStore {
    private var values: [String: String] = [:]

    func readCredential(account: String) throws -> String? { values[account] }
    func saveCredential(_ value: String, account: String) throws { values[account] = value }
    func deleteCredential(account: String) throws { values.removeValue(forKey: account) }
}

private final class CapturingTencentRealtimeClient: TencentRealtimeASRStreamingClient, @unchecked Sendable {
    private let lock = NSLock()
    private var configuration: TencentRealtimeASRConfiguration?

    var capturedConfiguration: TencentRealtimeASRConfiguration? {
        lock.withLock { configuration }
    }

    func testConnection(configuration: TencentRealtimeASRConfiguration) async throws -> ASRProviderHealthResult {
        ASRProviderHealthResult(status: .ok, message: "ok", latencyMS: 0)
    }

    func transcribe(
        configuration: TencentRealtimeASRConfiguration,
        audioChunks: AsyncStream<Data>,
        onMessage: @escaping @Sendable (TencentRealtimeASRMessage) -> Void
    ) async throws {
        lock.withLock {
            self.configuration = configuration
        }
    }
}
