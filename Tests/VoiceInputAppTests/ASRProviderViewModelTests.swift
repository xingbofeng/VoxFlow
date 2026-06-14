import XCTest
@testable import VoiceInputApp

@MainActor
final class ASRProviderViewModelTests: XCTestCase {
    func testLoadShowsBuiltInProvidersAndPersistsRepositoryRecords() throws {
        let manager = makeManager()
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let viewModel = ASRProviderViewModel(
            environment: environment,
            asrManager: manager,
            registry: ASRProviderRegistry(asrManager: manager)
        )

        XCTAssertEqual(viewModel.providers.map(\.id), [ASRProviderID.appleSpeech, ASRProviderID.qwen3])
        XCTAssertEqual(viewModel.providers.first?.isDefault, true)
        XCTAssertEqual(viewModel.providers[1].statusMessage, "尚未安装本地模型")
        XCTAssertEqual(try environment.asrProviderRepository.list().count, 2)
    }

    func testTagFilterNarrowsVisibleProviders() throws {
        let manager = makeManager()
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let viewModel = ASRProviderViewModel(
            environment: environment,
            asrManager: manager,
            registry: ASRProviderRegistry(asrManager: manager)
        )

        viewModel.toggleTag("本地")

        XCTAssertEqual(viewModel.visibleProviders.map(\.id), [ASRProviderID.qwen3])
    }

    func testSelectingUnavailableQwenDoesNotForceAppleFallback() throws {
        let manager = makeManager()
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let viewModel = ASRProviderViewModel(
            environment: environment,
            asrManager: manager,
            registry: ASRProviderRegistry(asrManager: manager)
        )

        viewModel.selectDefaultProvider(id: ASRProviderID.qwen3)

        XCTAssertEqual(manager.selectedEngineType, .apple)
        XCTAssertEqual(viewModel.providers.first?.id, ASRProviderID.appleSpeech)
        XCTAssertNotNil(viewModel.lastError)
    }

    func testSelectingUnavailableQwenSizeKeepsQwenHighlighted() throws {
        let manager = makeManager()
        manager.selectedEngineType = .qwen3
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let viewModel = ASRProviderViewModel(
            environment: environment,
            asrManager: manager,
            registry: ASRProviderRegistry(asrManager: manager)
        )

        viewModel.selectQwenModelSize(.size1_7B)

        XCTAssertEqual(manager.selectedEngineType, .qwen3)
        XCTAssertEqual(viewModel.providers.first(where: \.isDefault)?.id, ASRProviderID.qwen3)
        XCTAssertFalse(viewModel.providers.first(where: { $0.id == ASRProviderID.qwen3 })?.isAvailable ?? true)
    }

    func testSelectingAvailableProviderMovesDefaultWithoutPersistentSuccessBanner() throws {
        let manager = makeManager()
        let modelURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceInputTests-\(UUID().uuidString)")
        try createLoadableQwen3ModelDirectory(at: modelURL)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: modelURL)
        }
        manager.qwen3ModelPath = modelURL.path
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let viewModel = ASRProviderViewModel(
            environment: environment,
            asrManager: manager,
            registry: ASRProviderRegistry(asrManager: manager)
        )

        viewModel.selectDefaultProvider(id: ASRProviderID.qwen3)

        XCTAssertEqual(viewModel.providers.first(where: \.isDefault)?.id, ASRProviderID.qwen3)
        XCTAssertNil(viewModel.lastActionMessage)
        XCTAssertNil(viewModel.lastError)
    }

    func testDeleteLocalQwenModelClearsPathAndFallsBackToApple() throws {
        let manager = makeManager()
        let modelURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceInputTests-\(UUID().uuidString)")
        try createLoadableQwen3ModelDirectory(at: modelURL)
        manager.qwen3ModelPath = modelURL.path
        manager.selectedEngineType = .qwen3
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let viewModel = ASRProviderViewModel(
            environment: environment,
            asrManager: manager,
            registry: ASRProviderRegistry(asrManager: manager)
        )

        viewModel.deleteLocalQwenModel()

        XCTAssertFalse(FileManager.default.fileExists(atPath: modelURL.path))
        XCTAssertNil(manager.qwen3ModelPath)
        XCTAssertEqual(manager.selectedEngineType, .apple)
        XCTAssertEqual(viewModel.providers.first?.id, ASRProviderID.appleSpeech)
        XCTAssertEqual(viewModel.lastActionMessage, "已删除本地模型")
    }

    private func makeManager() -> ASRManager {
        let suiteName = "test.ASRProviderViewModel.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }
        return ASRManager(defaults: defaults)
    }

    private func createLoadableQwen3ModelDirectory(at modelURL: URL) throws {
        for relativePath in Qwen3ModelManifest.requiredLoadablePaths {
            let fileURL = modelURL.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            XCTAssertTrue(FileManager.default.createFile(atPath: fileURL.path, contents: Data()))
        }
    }
}
