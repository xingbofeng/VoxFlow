import XCTest
@testable import VoxFlowApp

@MainActor
final class GroqASRProviderViewModelTests: XCTestCase {
    func testSavingGroqConfigurationStoresKeyOutsideDefaultsAndEnablesProvider() throws {
        let suiteName = "test.GroqProviderViewModel.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let credentials = GroqViewModelCredentialStore()
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
        viewModel.groqAPIKeyInput = "secret"
        viewModel.groqBaseURLInput = "https://api.groq.com/openai/v1"
        viewModel.groqModelInput = "whisper-large-v3-turbo"

        viewModel.saveGroqConfiguration()

        XCTAssertTrue(viewModel.hasStoredGroqAPIKey)
        XCTAssertTrue(viewModel.providers.first(where: { $0.id == ASRProviderID.groqWhisper })?.isAvailable == true)
        XCTAssertEqual(try credentials.readCredential(account: ASRManager.groqAPIKeyAccount), "secret")
        XCTAssertFalse(try environment.settingsRepository.list().map(\.valueJSON).joined().contains("secret"))
        XCTAssertFalse(defaults.dictionaryRepresentation().values.contains { String(describing: $0).contains("secret") })
        XCTAssertEqual(viewModel.groqAPIKeyInput, ASRProviderViewModel.storedGroqAPIKeyMask)
    }

    func testExistingGroqCredentialShowsMaskedValueAndSavingMaskPreservesCredential() throws {
        let defaults = UserDefaults(suiteName: "test.GroqProviderDelete.\(UUID().uuidString)")!
        let environment = AppEnvironment(container: try DependencyContainer.inMemory(defaults: defaults))
        let manager = ASRManager(defaults: defaults, settingsRepository: environment.settingsRepository)
        try manager.saveGroqAPIKey("existing")
        let viewModel = ASRProviderViewModel(
            environment: environment,
            asrManager: manager,
            registry: ASRProviderRegistry(asrManager: manager)
        )

        XCTAssertEqual(viewModel.groqAPIKeyInput, ASRProviderViewModel.storedGroqAPIKeyMask)
        XCTAssertTrue(viewModel.isMaskedGroqAPIKey(text: viewModel.groqAPIKeyInput))
        XCTAssertEqual(viewModel.storedGroqAPIKeyForEditing(), "existing")

        viewModel.saveGroqConfiguration()
        XCTAssertEqual(manager.storedGroqAPIKey(), "existing")

        viewModel.deleteGroqAPIKey()

        XCTAssertEqual(manager.storedGroqAPIKey(), "")
        XCTAssertFalse(viewModel.hasStoredGroqAPIKey)
        XCTAssertFalse(viewModel.providers.first(where: { $0.id == ASRProviderID.groqWhisper })?.isAvailable == true)
    }

    func testLoadSyncsExternallySavedGroqCredentialIntoMaskedInput() throws {
        let defaults = UserDefaults(suiteName: "test.GroqProviderExternalSave.\(UUID().uuidString)")!
        let credentials = GroqViewModelCredentialStore()
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
        XCTAssertEqual(viewModel.groqAPIKeyInput, "")

        try manager.saveGroqAPIKey("external-secret")
        viewModel.load()

        XCTAssertTrue(viewModel.hasStoredGroqAPIKey)
        XCTAssertEqual(viewModel.groqAPIKeyInput, ASRProviderViewModel.storedGroqAPIKeyMask)
        XCTAssertEqual(viewModel.storedGroqAPIKeyForEditing(), "external-secret")
    }

    func testGroqModelOptionsAreLimitedToWhisperModels() throws {
        XCTAssertEqual(
            ASRProviderViewModel.supportedGroqModels.map(\.id),
            ["whisper-large-v3-turbo", "whisper-large-v3"]
        )

        let defaults = UserDefaults(suiteName: "test.GroqProviderModel.\(UUID().uuidString)")!
        let credentials = GroqViewModelCredentialStore()
        let environment = AppEnvironment(
            container: try DependencyContainer.inMemory(
                credentialStore: credentials,
                defaults: defaults
            )
        )
        let manager = ASRManager(defaults: defaults, credentialStore: credentials)
        let viewModel = ASRProviderViewModel(environment: environment, asrManager: manager)
        viewModel.groqAPIKeyInput = "secret"
        viewModel.groqModelInput = "llama-3.1-8b-instant"

        viewModel.saveGroqConfiguration()

        XCTAssertEqual(viewModel.lastError, "Groq 仅支持 Whisper 转写模型。")
        XCTAssertFalse(manager.isGroqConfigured)
    }

    func testProviderViewDescribesGroqCredentialAsLocalStorage() throws {
        let source = try String(
            contentsOfFile: "Sources/VoxFlowApp/Views/ASRProviderView.swift",
            encoding: .utf8
        )
        let zhHans = try String(
            contentsOfFile: "Sources/VoxFlowApp/Resources/zh-Hans.lproj/Localizable.strings",
            encoding: .utf8
        )

        XCTAssertTrue(source.contains(#"asr.provider.groq.privacy_note"#))
        XCTAssertTrue(zhHans.contains("访问密钥保存在本地凭据文件"))
        XCTAssertFalse(source.contains("录音会发送到 Groq。访问密钥保存在系统钥匙串"))
    }

    func testRejectsNonHTTPSGroqEndpoint() throws {
        let defaults = UserDefaults(suiteName: "test.GroqProviderURL.\(UUID().uuidString)")!
        let credentials = GroqViewModelCredentialStore()
        let environment = AppEnvironment(
            container: try DependencyContainer.inMemory(
                credentialStore: credentials,
                defaults: defaults
            )
        )
        let manager = ASRManager(defaults: defaults, credentialStore: credentials)
        let viewModel = ASRProviderViewModel(environment: environment, asrManager: manager)
        viewModel.groqAPIKeyInput = "secret"
        viewModel.groqBaseURLInput = "http://insecure.example.com/v1"

        viewModel.saveGroqConfiguration()

        XCTAssertEqual(viewModel.lastError, "Groq 地址必须是有效的 HTTPS URL。")
        XCTAssertFalse(manager.isGroqConfigured)
    }
}

private final class GroqViewModelCredentialStore: CredentialStore {
    private var values: [String: String] = [:]

    func readCredential(account: String) throws -> String? { values[account] }
    func saveCredential(_ value: String, account: String) throws { values[account] = value }
    func deleteCredential(account: String) throws { values.removeValue(forKey: account) }
}
