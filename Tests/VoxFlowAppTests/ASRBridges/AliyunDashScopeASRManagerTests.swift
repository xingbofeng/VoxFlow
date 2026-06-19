import XCTest
@testable import VoxFlowApp

final class AliyunDashScopeASRManagerTests: XCTestCase {
    func testAliyunDashScopeBecomesSelectableOnlyAfterAPIKeyIsConfigured() throws {
        let suiteName = "test.AliyunDashScopeASRManager.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let credentials = AliyunDashScopeManagerCredentialStore()
        let manager = ASRManager(defaults: defaults, credentialStore: credentials)
        let registry = ASRProviderRegistry(asrManager: manager)

        XCTAssertFalse(manager.canSelectEngine(.aliyunDashScope))
        var descriptor = try XCTUnwrap(registry.descriptor(id: ASRProviderID.qwenCloudASR))
        XCTAssertFalse(descriptor.isAvailable)
        XCTAssertNil(descriptor.engineType)

        try manager.saveAliyunDashScopeAPIKey("sk-example")

        XCTAssertTrue(manager.canSelectEngine(.aliyunDashScope))
        descriptor = try XCTUnwrap(registry.descriptor(id: ASRProviderID.qwenCloudASR))
        XCTAssertTrue(descriptor.isAvailable)
        XCTAssertEqual(descriptor.engineType, .aliyunDashScope)
        XCTAssertTrue(manager.makeEngine(type: .aliyunDashScope) is AliyunDashScopeRealtimeASREngine)
        XCTAssertFalse(defaults.dictionaryRepresentation().values.contains { String(describing: $0).contains("sk-example") })
    }
}

private final class AliyunDashScopeManagerCredentialStore: CredentialStore {
    private var values: [String: String] = [:]

    func readCredential(account: String) throws -> String? { values[account] }
    func saveCredential(_ value: String, account: String) throws { values[account] = value }
    func deleteCredential(account: String) throws { values.removeValue(forKey: account) }
}
