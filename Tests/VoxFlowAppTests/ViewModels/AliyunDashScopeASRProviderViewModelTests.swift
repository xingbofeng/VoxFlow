import XCTest
@testable import VoxFlowApp

@MainActor
final class AliyunDashScopeASRProviderViewModelTests: XCTestCase {
    func testSavingAliyunConfigurationStoresAPIKeyOutsideDefaultsAndMakesProviderAvailable() throws {
        let suiteName = "test.AliyunDashScopeASRProviderViewModel.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let manager = ASRManager(defaults: defaults, settingsRepository: environment.settingsRepository)
        let viewModel = ASRProviderViewModel(
            environment: environment,
            asrManager: manager
        )

        viewModel.aliyunDashScopeAPIKeyInput = " sk-example "
        viewModel.aliyunDashScopeModelInput = "fun-asr-realtime"

        viewModel.saveAliyunDashScopeConfiguration()

        XCTAssertTrue(try environment.settingsRepository.list().map(\.valueJSON).joined().contains("sk-example"))
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
        XCTAssertTrue(source.contains("API Key 保存在本地数据库"))
    }
}
