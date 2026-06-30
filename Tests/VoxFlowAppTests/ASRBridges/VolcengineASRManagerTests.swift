import XCTest
import VoxFlowProviderVolcengine
@testable import VoxFlowApp

final class VolcengineASRManagerTests: XCTestCase {
    func testVolcengineBecomesSelectableOnlyAfterCredentialsAreConfigured() throws {
        let suiteName = "test.VolcengineASRManager.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let credentials = VolcengineManagerCredentialStore()
        let manager = ASRManager(defaults: defaults, credentialStore: credentials)
        let registry = ASRProviderRegistry(asrManager: manager)

        XCTAssertFalse(manager.canSelectEngine(.volcengineDoubao))
        var descriptor = try XCTUnwrap(registry.descriptor(id: ASRProviderID.volcengineDoubao))
        XCTAssertFalse(descriptor.isAvailable)
        XCTAssertNil(descriptor.engineType)

        try manager.saveVolcengineCredentials(
            appID: "1234567890",
            accessToken: "token-example",
            secretKey: "secret-key-example"
        )

        XCTAssertTrue(manager.canSelectEngine(.volcengineDoubao))
        descriptor = try XCTUnwrap(registry.descriptor(id: ASRProviderID.volcengineDoubao))
        XCTAssertTrue(descriptor.isAvailable)
        XCTAssertEqual(descriptor.engineType, .volcengineDoubao)
        XCTAssertTrue(manager.makeEngine(type: .volcengineDoubao) is VolcengineRealtimeASREngine)
        XCTAssertFalse(defaults.dictionaryRepresentation().values.contains { String(describing: $0).contains("token-example") })
        XCTAssertFalse(defaults.dictionaryRepresentation().values.contains { String(describing: $0).contains("secret-key-example") })
    }
}

private final class VolcengineManagerCredentialStore: CredentialStore {
    private var values: [String: String] = [:]

    func readCredential(account: String) throws -> String? { values[account] }
    func saveCredential(_ value: String, account: String) throws { values[account] = value }
    func deleteCredential(account: String) throws { values.removeValue(forKey: account) }
}
