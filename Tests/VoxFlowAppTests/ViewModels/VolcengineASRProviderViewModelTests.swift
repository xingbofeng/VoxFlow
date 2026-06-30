import XCTest
import VoxFlowProviderVolcengine
@testable import VoxFlowApp

@MainActor
final class VolcengineASRProviderViewModelTests: XCTestCase {
    func testSavingVolcengineConfigurationStoresSecretsOutsideDefaultsAndEnablesProvider() throws {
        let suiteName = "test.VolcengineASRProviderViewModel.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let credentials = VolcengineViewModelCredentialStore()
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

        viewModel.volcengineAppIDInput = " 1234567890 "
        viewModel.volcengineAccessTokenInput = " token-example "
        viewModel.volcengineSecretKeyInput = " secret-key-example "

        viewModel.saveVolcengineConfiguration()

        XCTAssertEqual(try credentials.readCredential(account: ASRManager.volcengineAppIDAccount), "1234567890")
        XCTAssertEqual(try credentials.readCredential(account: ASRManager.volcengineAccessTokenAccount), "token-example")
        XCTAssertEqual(try credentials.readCredential(account: ASRManager.volcengineSecretKeyAccount), "secret-key-example")
        XCTAssertTrue(manager.canSelectEngine(.volcengineDoubao))
        XCTAssertTrue(viewModel.providers.first { $0.id == ASRProviderID.volcengineDoubao }?.isAvailable == true)
        XCTAssertEqual(viewModel.volcengineAccessTokenInput, ASRProviderViewModel.storedVolcengineSecretMask)
        XCTAssertEqual(viewModel.volcengineSecretKeyInput, ASRProviderViewModel.storedVolcengineSecretMask)

        let settingsJSON = try environment.settingsRepository.list().map(\.valueJSON).joined()
        XCTAssertFalse(settingsJSON.contains("token-example"))
        XCTAssertFalse(settingsJSON.contains("secret-key-example"))
        XCTAssertFalse(defaults.dictionaryRepresentation().values.contains { String(describing: $0).contains("token-example") })
        XCTAssertFalse(defaults.dictionaryRepresentation().values.contains { String(describing: $0).contains("secret-key-example") })
    }
}

private final class VolcengineViewModelCredentialStore: CredentialStore {
    private var values: [String: String] = [:]

    func readCredential(account: String) throws -> String? { values[account] }
    func saveCredential(_ value: String, account: String) throws { values[account] = value }
    func deleteCredential(account: String) throws { values.removeValue(forKey: account) }
}
