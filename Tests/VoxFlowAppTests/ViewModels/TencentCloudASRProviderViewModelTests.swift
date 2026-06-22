import XCTest
@testable import VoxFlowApp

@MainActor
final class TencentCloudASRProviderViewModelTests: XCTestCase {
    func testSavingTencentCloudConfigurationStoresSecretsOutsideDefaultsAndEnablesProvider() throws {
        let suiteName = "test.TencentCloudProviderViewModel.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let credentials = TencentCloudViewModelCredentialStore()
        let environment = AppEnvironment(
            container: try DependencyContainer.inMemory(
                credentialStore: credentials,
                defaults: defaults
            )
        )
        let manager = ASRManager(
            defaults: defaults,
            credentialStore: credentials,
            settingsRepository: environment.settingsRepository
        )
        let viewModel = ASRProviderViewModel(
            environment: environment,
            asrManager: manager,
            registry: ASRProviderRegistry(asrManager: manager)
        )

        viewModel.tencentAppIDInput = "1259220000"
        viewModel.tencentSecretIDInput = "AKIDEXAMPLE"
        viewModel.tencentSecretKeyInput = "SECRETEXAMPLE"
        viewModel.tencentEngineModelTypeInput = "16k_zh"

        viewModel.saveTencentCloudConfiguration()

        XCTAssertTrue(viewModel.hasStoredTencentCloudCredentials)
        XCTAssertTrue(viewModel.providers.first(where: { $0.id == ASRProviderID.tencentCloudASR })?.isAvailable == true)
        let settingsJSON = try environment.settingsRepository.list().map(\.valueJSON).joined()
        XCTAssertEqual(try credentials.readCredential(account: ASRManager.tencentAppIDAccount), "1259220000")
        XCTAssertEqual(try credentials.readCredential(account: ASRManager.tencentSecretIDAccount), "AKIDEXAMPLE")
        XCTAssertEqual(try credentials.readCredential(account: ASRManager.tencentSecretKeyAccount), "SECRETEXAMPLE")
        XCTAssertFalse(settingsJSON.contains("1259220000"))
        XCTAssertFalse(settingsJSON.contains("AKIDEXAMPLE"))
        XCTAssertFalse(settingsJSON.contains("SECRETEXAMPLE"))
        XCTAssertFalse(defaults.dictionaryRepresentation().values.contains { String(describing: $0).contains("SECRETEXAMPLE") })
        XCTAssertEqual(viewModel.tencentSecretKeyInput, ASRProviderViewModel.storedTencentSecretMask)
    }

    func testProviderViewShowsTencentCloudConfigurationGuide() throws {
        let sourceURL = Self.repositoryRoot()
            .appendingPathComponent("Sources/VoxFlowApp/Views/ASRProviderView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("腾讯云配置"))
        XCTAssertTrue(source.contains("应用 ID"))
        XCTAssertTrue(source.contains("密钥 ID"))
        XCTAssertTrue(source.contains("密钥"))
        XCTAssertTrue(source.contains("实时流式语音识别"))
        XCTAssertTrue(source.contains("系统钥匙串"))
    }

    private static func repositoryRoot() -> URL {
        var directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        for _ in 0..<5 {
            if FileManager.default.fileExists(atPath: directory.appendingPathComponent("Package.swift").path) {
                return directory
            }
            directory.deleteLastPathComponent()
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }
}

private final class TencentCloudViewModelCredentialStore: CredentialStore {
    private var values: [String: String] = [:]

    func readCredential(account: String) throws -> String? { values[account] }
    func saveCredential(_ value: String, account: String) throws { values[account] = value }
    func deleteCredential(account: String) throws { values.removeValue(forKey: account) }
}
