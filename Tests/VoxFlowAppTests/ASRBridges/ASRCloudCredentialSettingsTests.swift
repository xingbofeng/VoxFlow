import XCTest
@testable import VoxFlowApp

final class ASRCloudCredentialSettingsTests: XCTestCase {
    func testCloudASRCredentialsAreStoredInCredentialStoreWhenSettingsRepositoryIsAvailable() throws {
        let suiteName = "test.ASRCloudCredentialSettings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let credentials = CapturingASRCloudCredentialStore()
        let manager = ASRManager(
            defaults: defaults,
            credentialStore: credentials,
            settingsRepository: environment.settingsRepository
        )

        try manager.saveGroqAPIKey("groq-secret")
        try manager.saveTencentCloudCredentials(
            appID: "1259220000",
            secretID: "AKIDEXAMPLE",
            secretKey: "TENCENTSECRET"
        )
        try manager.saveAliyunDashScopeAPIKey("aliyun-secret")

        XCTAssertTrue(manager.isGroqConfigured)
        XCTAssertTrue(manager.isTencentCloudConfigured)
        XCTAssertTrue(manager.isAliyunDashScopeConfigured)
        XCTAssertEqual(manager.storedGroqAPIKey(), "groq-secret")
        XCTAssertEqual(manager.storedTencentCloudCredentials().secretKey, "TENCENTSECRET")
        XCTAssertEqual(manager.storedAliyunDashScopeAPIKey(), "aliyun-secret")
        XCTAssertEqual(credentials.values[ASRManager.groqAPIKeyAccount], "groq-secret")
        XCTAssertEqual(credentials.values[ASRManager.tencentSecretKeyAccount], "TENCENTSECRET")
        XCTAssertEqual(credentials.values[ASRManager.aliyunDashScopeAPIKeyAccount], "aliyun-secret")

        let records = try environment.settingsRepository.list()
        let allJSON = records.map(\.valueJSON).joined(separator: "\n")
        XCTAssertFalse(allJSON.contains("groq-secret"))
        XCTAssertFalse(allJSON.contains("TENCENTSECRET"))
        XCTAssertFalse(allJSON.contains("aliyun-secret"))
        XCTAssertFalse(defaults.dictionaryRepresentation().values.contains { String(describing: $0).contains("SECRET") })
    }

    func testCloudASRConfigurationCanBeReloadedFromCredentialStoreWhenSettingsRepositoryExists() throws {
        let suiteName = "test.ASRCloudCredentialSettings.reload.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let credentials = CapturingASRCloudCredentialStore()
        var manager = ASRManager(
            defaults: defaults,
            credentialStore: credentials,
            settingsRepository: environment.settingsRepository
        )
        try manager.saveAliyunDashScopeAPIKey("aliyun-secret")
        try manager.saveTencentCloudCredentials(
            appID: "1259220000",
            secretID: "AKIDEXAMPLE",
            secretKey: "TENCENTSECRET"
        )

        manager = ASRManager(
            defaults: defaults,
            credentialStore: credentials,
            settingsRepository: environment.settingsRepository
        )
        manager.aliyunDashScopeVocabularyID = "vocab-123"

        XCTAssertEqual(try manager.aliyunDashScopeConfiguration().apiKey, "aliyun-secret")
        XCTAssertEqual(try manager.aliyunDashScopeConfiguration().vocabularyID, "vocab-123")
        XCTAssertEqual(try manager.tencentCloudConfiguration().secretKey, "TENCENTSECRET")
        XCTAssertTrue(credentials.readAccounts.contains(ASRManager.aliyunDashScopeAPIKeyAccount))
        XCTAssertTrue(credentials.readAccounts.contains(ASRManager.tencentSecretKeyAccount))
    }

    func testLegacySettingsDatabaseCredentialsRemainReadableForMigration() throws {
        let suiteName = "test.ASRCloudCredentialSettings.legacy.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        try environment.settingsRepository.set(
            "ASRManager.cloudCredential.\(ASRManager.aliyunDashScopeAPIKeyAccount)",
            jsonValue: #"{"value":"legacy-aliyun-secret"}"#
        )
        let credentials = CapturingASRCloudCredentialStore()
        let manager = ASRManager(
            defaults: defaults,
            credentialStore: credentials,
            settingsRepository: environment.settingsRepository
        )

        XCTAssertEqual(manager.storedAliyunDashScopeAPIKey(), "legacy-aliyun-secret")
        XCTAssertTrue(credentials.readAccounts.contains(ASRManager.aliyunDashScopeAPIKeyAccount))
    }
}

private final class CapturingASRCloudCredentialStore: CredentialStore {
    private(set) var values: [String: String] = [:]
    private(set) var readAccounts: [String] = []

    func readCredential(account: String) throws -> String? {
        readAccounts.append(account)
        return values[account]
    }

    func saveCredential(_ value: String, account: String) throws {
        values[account] = value
    }

    func deleteCredential(account: String) throws {
        values.removeValue(forKey: account)
    }
}
