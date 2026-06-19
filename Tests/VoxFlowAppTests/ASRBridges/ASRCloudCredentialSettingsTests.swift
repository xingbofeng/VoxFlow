import XCTest
@testable import VoxFlowApp

final class ASRCloudCredentialSettingsTests: XCTestCase {
    func testCloudASRCredentialsAreStoredInSettingsDatabaseWhenRepositoryIsAvailable() throws {
        let suiteName = "test.ASRCloudCredentialSettings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let keychain = FailingASRCloudCredentialStore()
        let manager = ASRManager(
            defaults: defaults,
            credentialStore: keychain,
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
        XCTAssertTrue(keychain.accessedAccounts.isEmpty)

        let records = try environment.settingsRepository.list()
        let allJSON = records.map(\.valueJSON).joined(separator: "\n")
        XCTAssertTrue(allJSON.contains("groq-secret"))
        XCTAssertTrue(allJSON.contains("TENCENTSECRET"))
        XCTAssertTrue(allJSON.contains("aliyun-secret"))
        XCTAssertFalse(defaults.dictionaryRepresentation().values.contains { String(describing: $0).contains("SECRET") })
    }

    func testCloudASRConfigurationCanBeReloadedFromSettingsDatabaseWithoutKeychainAccess() throws {
        let suiteName = "test.ASRCloudCredentialSettings.reload.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        var manager = ASRManager(
            defaults: defaults,
            credentialStore: FailingASRCloudCredentialStore(),
            settingsRepository: environment.settingsRepository
        )
        try manager.saveAliyunDashScopeAPIKey("aliyun-secret")
        try manager.saveTencentCloudCredentials(
            appID: "1259220000",
            secretID: "AKIDEXAMPLE",
            secretKey: "TENCENTSECRET"
        )

        let keychain = FailingASRCloudCredentialStore()
        manager = ASRManager(
            defaults: defaults,
            credentialStore: keychain,
            settingsRepository: environment.settingsRepository
        )

        XCTAssertEqual(try manager.aliyunDashScopeConfiguration().apiKey, "aliyun-secret")
        XCTAssertEqual(try manager.tencentCloudConfiguration().secretKey, "TENCENTSECRET")
        XCTAssertTrue(keychain.accessedAccounts.isEmpty)
    }
}

private final class FailingASRCloudCredentialStore: CredentialStore {
    private(set) var accessedAccounts: [String] = []

    func readCredential(account: String) throws -> String? {
        accessedAccounts.append(account)
        XCTFail("ASR cloud credentials should not read Keychain when SettingsRepository is available.")
        return nil
    }

    func saveCredential(_ value: String, account: String) throws {
        accessedAccounts.append(account)
        XCTFail("ASR cloud credentials should not write Keychain when SettingsRepository is available.")
    }

    func deleteCredential(account: String) throws {
        accessedAccounts.append(account)
        XCTFail("ASR cloud credentials should not delete Keychain when SettingsRepository is available.")
    }
}
