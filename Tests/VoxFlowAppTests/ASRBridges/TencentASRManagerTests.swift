import XCTest
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
}

private final class TencentManagerCredentialStore: CredentialStore {
    private var values: [String: String] = [:]

    func readCredential(account: String) throws -> String? { values[account] }
    func saveCredential(_ value: String, account: String) throws { values[account] = value }
    func deleteCredential(account: String) throws { values.removeValue(forKey: account) }
}
