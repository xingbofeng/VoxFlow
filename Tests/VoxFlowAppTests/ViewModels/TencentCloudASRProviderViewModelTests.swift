import XCTest
@testable import VoxFlowApp

@MainActor
final class TencentCloudASRProviderViewModelTests: XCTestCase {
    func testSavingTencentCloudConfigurationStoresSecretsOutsideDefaultsAndEnablesProvider() throws {
        let suiteName = "test.TencentCloudProviderViewModel.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let environment = AppEnvironment(container: try DependencyContainer.inMemory(defaults: defaults))
        let manager = ASRManager(defaults: defaults, settingsRepository: environment.settingsRepository)
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
        XCTAssertTrue(settingsJSON.contains("1259220000"))
        XCTAssertTrue(settingsJSON.contains("AKIDEXAMPLE"))
        XCTAssertTrue(settingsJSON.contains("SECRETEXAMPLE"))
        XCTAssertFalse(defaults.dictionaryRepresentation().values.contains { String(describing: $0).contains("SECRETEXAMPLE") })
        XCTAssertEqual(viewModel.tencentSecretKeyInput, ASRProviderViewModel.storedTencentSecretMask)
    }

    func testProviderViewShowsTencentCloudConfigurationGuide() throws {
        let sourceURL = Self.repositoryRoot()
            .appendingPathComponent("Sources/VoxFlowApp/Views/ASRProviderView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("腾讯云配置"))
        XCTAssertTrue(source.contains("AppID"))
        XCTAssertTrue(source.contains("SecretId"))
        XCTAssertTrue(source.contains("SecretKey"))
        XCTAssertTrue(source.contains("实时流式语音识别"))
        XCTAssertTrue(source.contains("本地数据库"))
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
