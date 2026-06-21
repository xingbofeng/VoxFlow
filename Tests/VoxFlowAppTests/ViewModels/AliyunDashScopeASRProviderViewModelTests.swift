import XCTest
@testable import VoxFlowApp

@MainActor
final class AliyunDashScopeASRProviderViewModelTests: XCTestCase {
    func testSavingAliyunConfigurationStoresAPIKeyOutsideDefaultsAndMakesProviderAvailable() throws {
        let suiteName = "test.AliyunDashScopeASRProviderViewModel.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let credentials = AliyunDashScopeViewModelCredentialStore()
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

        viewModel.aliyunDashScopeAPIKeyInput = " sk-example "
        viewModel.aliyunDashScopeModelInput = "fun-asr-realtime"

        viewModel.saveAliyunDashScopeConfiguration()

        XCTAssertEqual(try credentials.readCredential(account: ASRManager.aliyunDashScopeAPIKeyAccount), "sk-example")
        XCTAssertFalse(try environment.settingsRepository.list().map(\.valueJSON).joined().contains("sk-example"))
        XCTAssertEqual(manager.aliyunDashScopeModel, "fun-asr-realtime")
        XCTAssertTrue(manager.canSelectEngine(.aliyunDashScope))
        XCTAssertEqual(viewModel.aliyunDashScopeAPIKeyInput, ASRProviderViewModel.storedAliyunDashScopeAPIKeyMask)
        XCTAssertTrue(viewModel.providers.first { $0.id == ASRProviderID.qwenCloudASR }?.isAvailable == true)
        XCTAssertFalse(defaults.dictionaryRepresentation().values.contains { String(describing: $0).contains("sk-example") })
    }

    func testAliyunConfigurationGuideIsChineseAndMentionsDashScopeWebSocket() throws {
        let source = try String(
            contentsOfFile: "Sources/VoxFlowApp/Views/ASRProviderView.swift",
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("阿里云百炼配置"))
        XCTAssertTrue(source.contains("DashScope 实时语音识别 WebSocket"))
        XCTAssertTrue(source.contains("fun-asr-realtime"))
        XCTAssertTrue(source.contains("API Key 保存在系统钥匙串"))
    }
}

private final class AliyunDashScopeViewModelCredentialStore: CredentialStore {
    private var values: [String: String] = [:]

    func readCredential(account: String) throws -> String? { values[account] }
    func saveCredential(_ value: String, account: String) throws { values[account] = value }
    func deleteCredential(account: String) throws { values.removeValue(forKey: account) }
}
