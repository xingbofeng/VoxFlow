import XCTest
import VoxFlowModelStore
import VoxFlowProviderFunASR
import VoxFlowProviderParaformer
import VoxFlowProviderQwen3
import VoxFlowProviderSenseVoice
import VoxFlowProviderWhisper
@testable import VoxFlowApp

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

        viewModel.load()

        let providerIDs = Set(viewModel.providers.map(\.id))

        XCTAssertEqual(viewModel.providers.first?.id, ASRProviderID.appleSpeech)
        XCTAssertTrue(providerIDs.isSuperset(of: [
            ASRProviderID.appleSpeech,
            ASRProviderID.funASR,
            ASRProviderID.nvidiaNemotron,
            ASRProviderID.parakeetStreaming,
            ASRProviderID.omnilingualASR,
            ASRProviderID.paraformer,
            ASRProviderID.qwen3,
            ASRProviderID.senseVoice,
            ASRProviderID.whisper,
            ASRProviderID.groqWhisper,
            ASRProviderID.tencentCloudASR,
            ASRProviderID.qwenCloudASR,
            ASRProviderID.volcengineDoubao,
            ASRProviderID.mistralVoxtral,
            ASRProviderID.assemblyAI,
            ASRProviderID.elevenLabsScribe,
        ]))
        XCTAssertEqual(viewModel.providers.first?.isDefault, true)
        XCTAssertEqual(
            viewModel.providers.first { $0.id == ASRProviderID.funASR }?.statusMessage,
            "尚未安装本地模型"
        )
        XCTAssertEqual(try environment.asrProviderRepository.list().count, 16)
    }

    func testInitializationReadsProviderCatalogWithoutPersistingRecords() throws {
        let manager = makeManager()
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let viewModel = ASRProviderViewModel(
            environment: environment,
            asrManager: manager,
            registry: ASRProviderRegistry(asrManager: manager)
        )

        XCTAssertFalse(viewModel.providers.isEmpty)
        XCTAssertTrue(try environment.asrProviderRepository.list().isEmpty)
    }

    func testUnavailablePersistedLocalProviderKeepsUserSelectionWhileRuntimeFallsBackToApple() throws {
        let manager = makeManager()
        manager.selectedEngineType = .funASR
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let viewModel = ASRProviderViewModel(
            environment: environment,
            asrManager: manager,
            registry: ASRProviderRegistry(asrManager: manager)
        )

        let appleProvider = try XCTUnwrap(viewModel.providers.first { $0.id == ASRProviderID.appleSpeech })
        let funASRProvider = try XCTUnwrap(viewModel.providers.first { $0.id == ASRProviderID.funASR })

        XCTAssertEqual(manager.effectiveSelectedEngineType, .apple)
        XCTAssertFalse(appleProvider.isDefault)
        XCTAssertTrue(funASRProvider.isDefault)
        XCTAssertFalse(funASRProvider.isAvailable)
        XCTAssertEqual(
            funASRProvider.statusMessage,
            "尚未安装本地模型。请下载、修复或重新选择模型。"
        )
    }

    func testCorruptQwenProviderPersistsRepairRequiredHealth() throws {
        let (manager, modelStateRepository) = makeManagerAndRepository()
        try saveQwenState(.corrupt(reason: "缺少 decoder"), in: modelStateRepository)
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let viewModel = ASRProviderViewModel(
            environment: environment,
            asrManager: manager,
            registry: ASRProviderRegistry(asrManager: manager)
        )
        viewModel.load()

        let qwenProvider = try XCTUnwrap(viewModel.providers.first { $0.id == ASRProviderID.qwen3 })
        let record = try XCTUnwrap(environment.asrProviderRepository.provider(id: ASRProviderID.qwen3))

        XCTAssertFalse(qwenProvider.isAvailable)
        XCTAssertEqual(qwenProvider.localModelAction, .repair)
        XCTAssertEqual(record.lastHealthStatus, "repair_required")
        XCTAssertEqual(record.lastHealthMessage, "模型损坏，需要修复：缺少 decoder")
    }

    func testUninstalledQwenProviderPersistsNotInstalledHealth() throws {
        let manager = makeManager()
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let viewModel = ASRProviderViewModel(
            environment: environment,
            asrManager: manager,
            registry: ASRProviderRegistry(asrManager: manager)
        )
        viewModel.load()

        let record = try XCTUnwrap(environment.asrProviderRepository.provider(id: ASRProviderID.qwen3))

        XCTAssertEqual(record.lastHealthStatus, "not_installed")
        XCTAssertEqual(record.lastHealthMessage, "尚未安装本地模型")
    }

    func testManualQwenPathDoesNotMakeProviderAvailableWithoutModelStoreReadyState() throws {
        let manager = makeManager()
        let modelURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ASRProviderViewModelTests-\(UUID().uuidString)", isDirectory: true)
        try createLoadableQwen3ModelDirectory(at: modelURL)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: modelURL)
        }
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let viewModel = ASRProviderViewModel(
            environment: environment,
            asrManager: manager,
            registry: ASRProviderRegistry(asrManager: manager)
        )

        viewModel.setQwenModelPath(modelURL.path)

        let qwenProvider = try XCTUnwrap(viewModel.providers.first { $0.id == ASRProviderID.qwen3 })
        let record = try XCTUnwrap(environment.asrProviderRepository.provider(id: ASRProviderID.qwen3))
        XCTAssertEqual(manager.qwen3ModelPath, modelURL.path)
        XCTAssertFalse(qwenProvider.isAvailable)
        XCTAssertEqual(qwenProvider.localModelAction, .download)
        XCTAssertEqual(record.lastHealthStatus, "not_installed")
        XCTAssertFalse(manager.canSelectEngine(.qwen3))
    }

    func testRuntimeUnsupportedQwenProviderPersistsRuntimeUnsupportedHealth() throws {
        let (manager, modelStateRepository) = makeManagerAndRepository()
        try saveQwenState(.runtimeUnsupported(reason: "缺少本地 runtime"), in: modelStateRepository)
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let viewModel = ASRProviderViewModel(
            environment: environment,
            asrManager: manager,
            registry: ASRProviderRegistry(asrManager: manager)
        )
        viewModel.load()

        let qwenProvider = try XCTUnwrap(viewModel.providers.first { $0.id == ASRProviderID.qwen3 })
        let record = try XCTUnwrap(environment.asrProviderRepository.provider(id: ASRProviderID.qwen3))

        XCTAssertFalse(qwenProvider.isAvailable)
        XCTAssertEqual(qwenProvider.localModelAction, .none)
        XCTAssertEqual(record.lastHealthStatus, "runtime_unsupported")
        XCTAssertEqual(record.lastHealthMessage, "运行时不支持：缺少本地 runtime")
    }

    func testTagFilterUsesDisplayedProviderTagsInSingleRow() throws {
        let manager = makeManager()
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let viewModel = ASRProviderViewModel(
            environment: environment,
            asrManager: manager,
            registry: ASRProviderRegistry(asrManager: manager)
        )

        viewModel.toggleTag("CoreML")

        XCTAssertTrue(viewModel.availableTags.contains("CoreML"))
        XCTAssertEqual(viewModel.selectedTags, ["CoreML"])
        XCTAssertEqual(
            Set(viewModel.visibleProviders.map(\.id)),
            [
                ASRProviderID.nvidiaNemotron,
                ASRProviderID.parakeetStreaming,
                ASRProviderID.omnilingualASR,
            ]
        )
    }

    func testProviderScopeDefaultsToAllAndFiltersOnlineAndOfflineCatalogs() throws {
        let manager = makeManager()
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let viewModel = ASRProviderViewModel(
            environment: environment,
            asrManager: manager,
            registry: ASRProviderRegistry(asrManager: manager)
        )

        XCTAssertEqual(viewModel.providerScope, .all)
        XCTAssertTrue(viewModel.visibleProviders.contains { $0.id == ASRProviderID.appleSpeech })
        XCTAssertTrue(viewModel.visibleProviders.contains { $0.id == ASRProviderID.groqWhisper })

        viewModel.selectProviderScope(.online)

        XCTAssertEqual(
            viewModel.visibleProviders.map(\.id),
            [
                ASRProviderID.groqWhisper,
                ASRProviderID.tencentCloudASR,
                ASRProviderID.qwenCloudASR,
                ASRProviderID.volcengineDoubao,
                ASRProviderID.mistralVoxtral,
                ASRProviderID.assemblyAI,
                ASRProviderID.elevenLabsScribe,
            ]
        )
        XCTAssertFalse(viewModel.visibleProviders.contains { $0.id == ASRProviderID.appleSpeech })

        viewModel.selectProviderScope(.offline)

        XCTAssertEqual(viewModel.visibleProviders.first?.id, ASRProviderID.appleSpeech)
        XCTAssertFalse(viewModel.visibleProviders.contains { $0.id == ASRProviderID.groqWhisper })
        XCTAssertTrue(viewModel.availableTags.contains("流式"))
        XCTAssertTrue(viewModel.availableTags.contains("CoreML"))
        XCTAssertEqual(
            Set(viewModel.visibleProviders.map(\.id)),
            [
                ASRProviderID.appleSpeech,
                ASRProviderID.funASR,
                ASRProviderID.whisper,
                ASRProviderID.qwen3,
                ASRProviderID.senseVoice,
                ASRProviderID.paraformer,
                ASRProviderID.nvidiaNemotron,
                ASRProviderID.parakeetStreaming,
                ASRProviderID.omnilingualASR,
            ]
        )
    }

    func testProviderScopeControlOrderIsAllOfflineOnline() {
        XCTAssertEqual(ASRProviderScope.allCases, [.all, .offline, .online])
    }

    func testOfflineProviderScopeMatchesSystemAndLocalProvidersButNotCloudProviders() throws {
        let manager = makeManager()
        let registry = ASRProviderRegistry(asrManager: manager)
        let apple = try XCTUnwrap(registry.descriptor(id: ASRProviderID.appleSpeech))
        let qwen = try XCTUnwrap(registry.descriptor(id: ASRProviderID.qwen3))
        let groq = try XCTUnwrap(registry.descriptor(id: ASRProviderID.groqWhisper))

        XCTAssertTrue(ASRProviderScope.offline.matches(apple))
        XCTAssertTrue(ASRProviderScope.offline.matches(qwen))
        XCTAssertFalse(ASRProviderScope.offline.matches(groq))
    }

    func testProviderScopeMatchesNormalizedDisplayedTags() throws {
        let onlineDescriptor = ASRProviderDescriptor(
            id: "custom-online",
            displayName: "自定义在线",
            providerType: "custom",
            capabilities: [.streaming, .cloud],
            tags: [],
            isAvailable: true,
            isDefault: false,
            statusMessage: nil,
            privacySummary: "在线识别",
            modelSize: nil,
            engineType: nil,
            externalLinks: ASRProviderExternalLinks(
                apiKeyURL: URL(string: "https://example.com/key")!
            )
        )

        XCTAssertTrue(ASRProviderScope.online.matches(onlineDescriptor))
        XCTAssertFalse(ASRProviderScope.offline.matches(onlineDescriptor))
    }

    func testCurrentProviderIsPinnedToTopWhenVisible() throws {
        let manager = makeManager()
        manager.selectedEngineType = .funASR
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let viewModel = ASRProviderViewModel(
            environment: environment,
            asrManager: manager,
            registry: ASRProviderRegistry(asrManager: manager)
        )

        XCTAssertEqual(viewModel.visibleProviders.first?.id, ASRProviderID.funASR)

        viewModel.selectProviderScope(.online)

        XCTAssertNotEqual(viewModel.visibleProviders.first?.id, ASRProviderID.funASR)
        XCTAssertFalse(viewModel.visibleProviders.contains { $0.id == ASRProviderID.funASR })
    }

    func testOnlineProvidersExposeExternalAPIKeyAndModelLinks() throws {
        let manager = makeManager()
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let viewModel = ASRProviderViewModel(
            environment: environment,
            asrManager: manager,
            registry: ASRProviderRegistry(asrManager: manager)
        )

        viewModel.selectProviderScope(.online)

        for provider in viewModel.visibleProviders {
            let links = try XCTUnwrap(provider.externalLinks, "\(provider.displayName) should expose external links")
            XCTAssertEqual(links.apiKeyTitle, "获取 API 密钥")
            XCTAssertFalse(links.apiKeyURL.absoluteString.isEmpty)
            XCTAssertNotNil(links.modelsURL ?? links.guideURL)
        }
    }

    func testUnsupportedOnlineProvidersAreDisabledAndLabeledUnsupported() throws {
        let manager = makeManager()
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let viewModel = ASRProviderViewModel(
            environment: environment,
            asrManager: manager,
            registry: ASRProviderRegistry(asrManager: manager)
        )

        let expectedNames = [
            ASRProviderID.groqWhisper: "Groq（免费）",
            ASRProviderID.tencentCloudASR: "腾讯云",
            ASRProviderID.qwenCloudASR: "阿里云",
            ASRProviderID.volcengineDoubao: "火山云",
        ]
        for (id, name) in expectedNames {
            XCTAssertEqual(viewModel.providers.first { $0.id == id }?.displayName, name)
        }

        for id in [
            ASRProviderID.volcengineDoubao,
            ASRProviderID.mistralVoxtral,
            ASRProviderID.assemblyAI,
            ASRProviderID.elevenLabsScribe,
        ] {
            let provider = try XCTUnwrap(viewModel.providers.first { $0.id == id })
            XCTAssertFalse(provider.isAvailable)
            XCTAssertNil(provider.engineType)
            XCTAssertEqual(provider.statusMessage, "暂未支持")
        }

        let aliyun = try XCTUnwrap(viewModel.providers.first { $0.id == ASRProviderID.qwenCloudASR })
        XCTAssertFalse(aliyun.isAvailable)
        XCTAssertNil(aliyun.engineType)
        XCTAssertEqual(aliyun.statusMessage, "请先配置百炼访问密钥")

        let tencent = try XCTUnwrap(viewModel.providers.first { $0.id == ASRProviderID.tencentCloudASR })
        XCTAssertFalse(tencent.isAvailable)
        XCTAssertNil(tencent.engineType)
        XCTAssertEqual(tencent.statusMessage, "需要配置 AppID、SecretId 和 SecretKey")
    }

    func testQwenCloudLinksUseReachableOfficialAliyunDocumentation() throws {
        let manager = makeManager()
        let registry = ASRProviderRegistry(asrManager: manager)
        let provider = try XCTUnwrap(registry.descriptor(id: ASRProviderID.qwenCloudASR))
        let links = try XCTUnwrap(provider.externalLinks)

        XCTAssertEqual(links.modelsURL?.host, "help.aliyun.com")
        XCTAssertEqual(links.guideURL?.host, "help.aliyun.com")
    }

    func testAvailableTagsReflectCurrentScope() throws {
        let manager = makeManager()
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let viewModel = ASRProviderViewModel(
            environment: environment,
            asrManager: manager,
            registry: ASRProviderRegistry(asrManager: manager)
        )

        viewModel.selectProviderScope(.online)

        XCTAssertEqual(
            viewModel.availableTags,
            ["流式", "非流式", "快速", "准确", "中文", "多语言"]
        )
    }

    func testChangingProviderScopeKeepsOnlyAvailableTagSelection() throws {
        let manager = makeManager()
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let viewModel = ASRProviderViewModel(
            environment: environment,
            asrManager: manager,
            registry: ASRProviderRegistry(asrManager: manager)
        )

        viewModel.toggleTag("CoreML")
        XCTAssertEqual(viewModel.selectedTags, ["CoreML"])

        viewModel.selectProviderScope(.online)

        XCTAssertTrue(viewModel.selectedTags.isEmpty)
        XCTAssertFalse(viewModel.visibleProviders.isEmpty)
    }

    func testSelectingProviderVariantsUpdatesManagerAndDownloadTarget() throws {
        let manager = makeManager()
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let viewModel = ASRProviderViewModel(
            environment: environment,
            asrManager: manager,
            registry: ASRProviderRegistry(asrManager: manager)
        )

        viewModel.selectFunASRPrecision(.fp32)
        viewModel.selectWhisperVariant(.turbo)

        XCTAssertEqual(manager.funASRPrecision, .fp32)
        XCTAssertEqual(manager.whisperVariant, .turbo)
        XCTAssertEqual(viewModel.sherpaVariant(for: ASRProviderID.funASR), .funASRFP32)
        XCTAssertNil(viewModel.sherpaVariant(for: ASRProviderID.whisper))
        XCTAssertEqual(viewModel.whisperKitVariant(for: ASRProviderID.whisper), .turbo)
    }

    func testSelectingProviderVariantAlsoSelectsThatProviderWhenReady() throws {
        let manager = makeManager()
        let funASRURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FunASRReady-\(UUID().uuidString)", isDirectory: true)
        try createLoadableFunASRModelDirectory(at: funASRURL, variant: .fp32)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: funASRURL)
        }
        manager.markFunASRModelReady(at: funASRURL.path, precision: .fp32)
        manager.selectedEngineType = .apple
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let viewModel = ASRProviderViewModel(
            environment: environment,
            asrManager: manager,
            registry: ASRProviderRegistry(asrManager: manager)
        )

        viewModel.selectFunASRPrecision(.fp32, selectingProvider: true)

        XCTAssertEqual(manager.funASRPrecision, .fp32)
        XCTAssertEqual(manager.selectedEngineType, .funASR)
        XCTAssertEqual(viewModel.providers.first(where: \.isDefault)?.id, ASRProviderID.funASR)
    }

    func testParaformerAndNVIDIANemotronArePersistedAsFormalProviders() throws {
        let manager = makeManager()
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let viewModel = ASRProviderViewModel(
            environment: environment,
            asrManager: manager,
            registry: ASRProviderRegistry(asrManager: manager)
        )
        viewModel.load()

        XCTAssertNotNil(viewModel.providers.first { $0.id == ASRProviderID.paraformer })
        XCTAssertNotNil(viewModel.providers.first { $0.id == ASRProviderID.nvidiaNemotron })
        XCTAssertNil(viewModel.sherpaVariant(for: ASRProviderID.paraformer))
        XCTAssertNotNil(try environment.asrProviderRepository.provider(id: ASRProviderID.paraformer))
        XCTAssertNotNil(try environment.asrProviderRepository.provider(id: ASRProviderID.nvidiaNemotron))
    }

    func testParaformerAndNVIDIANemotronExposeDownloadActionsWhenUninstalled() throws {
        let manager = makeManager()
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let viewModel = ASRProviderViewModel(
            environment: environment,
            asrManager: manager,
            registry: ASRProviderRegistry(asrManager: manager)
        )

        XCTAssertEqual(
            viewModel.providers.first { $0.id == ASRProviderID.paraformer }?.localModelAction,
            .download
        )
        XCTAssertEqual(
            viewModel.providers.first { $0.id == ASRProviderID.nvidiaNemotron }?.localModelAction,
            .download
        )
    }

    func testSelectingWhisperLargeAndQwen17CanBeChosenForInstallation() throws {
        let manager = makeManager()
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let viewModel = ASRProviderViewModel(
            environment: environment,
            asrManager: manager,
            registry: ASRProviderRegistry(asrManager: manager)
        )

        viewModel.selectWhisperVariant(.largeV3)

        XCTAssertEqual(manager.whisperVariant, .largeV3)
        XCTAssertNil(viewModel.lastError)
        XCTAssertEqual(viewModel.lastActionMessage, "已切换模型配置")

        viewModel.clearFeedback()
        viewModel.selectQwenModelSize(.size1_7B)

        XCTAssertEqual(manager.qwen3ModelSize, .size1_7B)
        XCTAssertNil(viewModel.lastError)
        XCTAssertEqual(viewModel.lastActionMessage, "已切换模型配置")
        XCTAssertFalse(manager.isQwen3ModelAvailable)
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

    func testSelectingAvailableProviderMovesDefaultWithoutPersistentSuccessBanner() throws {
        let manager = makeManager()
        let modelURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceInputTests-\(UUID().uuidString)")
        try createLoadableQwen3ModelDirectory(at: modelURL)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: modelURL)
        }
        manager.markQwen3ModelReady(at: modelURL.path, size: .size0_6B)
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
        manager.markQwen3ModelReady(at: modelURL.path, size: .size0_6B)
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
        XCTAssertEqual(manager.qwen3ModelInstallationState, .notInstalled)
        XCTAssertEqual(manager.selectedEngineType, .apple)
        XCTAssertEqual(viewModel.providers.first?.id, ASRProviderID.appleSpeech)
        XCTAssertEqual(viewModel.lastActionMessage, "已删除本地模型")
    }

    func testDeleteAutoDiscoveredQwenModelRemovesModelStoreInstallation() throws {
        let suiteName = "test.ASRProviderViewModel.autodiscovered.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("QwenAutoDiscoveredDeleteTests-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }
        let stateRepository = FileModelInstallationStateRepository(
            fileURL: root.appendingPathComponent("installation-states.json")
        )
        let modelStoreRoot = root.appendingPathComponent("models", isDirectory: true)
        let metadata = try Qwen3ModelStoreMetadata.metadata(for: Qwen3ModelManifest.manifest(for: .size0_6B))
        let modelURL = modelStoreRoot
            .appendingPathComponent(metadata.modelID.rawValue, isDirectory: true)
            .appendingPathComponent(metadata.version, isDirectory: true)
        try createLoadableQwen3ModelDirectory(at: modelURL)
        let manager = ASRManager(
            defaults: defaults,
            modelInstallationRepository: stateRepository,
            credentialStore: ASRProviderViewModelTestCredentialStore(),
            qwen3RuntimePreflight: { _ in .supported },
            modelStoreRoot: modelStoreRoot
        )
        manager.selectedEngineType = .qwen3
        XCTAssertNil(manager.qwen3ModelPath)
        XCTAssertTrue(manager.isQwen3ModelAvailable)
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let viewModel = ASRProviderViewModel(
            environment: environment,
            asrManager: manager,
            registry: ASRProviderRegistry(asrManager: manager)
        )

        viewModel.deleteLocalQwenModel()

        XCTAssertFalse(FileManager.default.fileExists(atPath: modelURL.path))
        XCTAssertEqual(manager.qwen3ModelInstallationState, .notInstalled)
        XCTAssertEqual(manager.selectedEngineType, .apple)
    }

    func testDeleteQwenModelRemovesFailedDownloadStagingAndModelStoreCandidates() throws {
        let suiteName = "test.ASRProviderViewModel.qwen-staging-delete.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("QwenStagingDeleteTests-\(UUID().uuidString)", isDirectory: true)
        let modelStoreRoot = root.appendingPathComponent("Models", isDirectory: true)
        let stateRepository = FileModelInstallationStateRepository(
            fileURL: modelStoreRoot.appendingPathComponent("installation-states.json")
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }

        let manifest = Qwen3ModelManifest.manifest(for: .size1_7B)
        let metadata = try Qwen3ModelStoreMetadata.metadata(for: manifest)
        let key = ModelInstallKey(modelID: metadata.modelID, version: metadata.version)
        let canonicalURL = modelStoreRoot
            .appendingPathComponent(metadata.modelID.rawValue, isDirectory: true)
            .appendingPathComponent(metadata.version, isDirectory: true)
        let legacyURL = modelStoreRoot
            .appendingPathComponent(manifest.localDirectoryName, isDirectory: true)
            .appendingPathComponent(metadata.version, isDirectory: true)
        let stagingURL = modelStoreRoot
            .appendingPathComponent("staging", isDirectory: true)
            .appendingPathComponent("\(metadata.modelID.rawValue)-\(metadata.version).partial", isDirectory: true)
        for url in [canonicalURL, legacyURL, stagingURL] {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try Data("partial".utf8).write(to: url.appendingPathComponent("model.safetensors"))
        }

        let manager = ASRManager(
            defaults: defaults,
            modelInstallationRepository: stateRepository,
            credentialStore: ASRProviderViewModelTestCredentialStore(),
            qwen3RuntimePreflight: { _ in .supported },
            modelStoreRoot: modelStoreRoot
        )
        manager.qwen3ModelSize = .size1_7B
        try stateRepository.save(
            .downloading(
                progress: ModelDownloadProgress(
                    bytesWritten: 42,
                    totalBytes: 100,
                    componentID: ModelComponentID(rawValue: "model.safetensors")
                )
            ),
            for: key
        )
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let viewModel = ASRProviderViewModel(
            environment: environment,
            asrManager: manager,
            registry: ASRProviderRegistry(asrManager: manager)
        )

        viewModel.deleteLocalQwenModel()

        XCTAssertFalse(FileManager.default.fileExists(atPath: canonicalURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: stagingURL.path))
        XCTAssertEqual(try stateRepository.state(for: key), .notInstalled)
        XCTAssertEqual(viewModel.lastActionMessage, "已删除本地模型")
    }

    func testDeleteQwenModelRemovesStagingForOtherModelSizes() throws {
        let suiteName = "test.ASRProviderViewModel.qwen-cross-size-delete.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("QwenCrossSizeDeleteTests-\(UUID().uuidString)", isDirectory: true)
        let modelStoreRoot = root.appendingPathComponent("Models", isDirectory: true)
        let stateRepository = FileModelInstallationStateRepository(
            fileURL: modelStoreRoot.appendingPathComponent("installation-states.json")
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }

        let previousManifest = Qwen3ModelManifest.manifest(for: .size1_7B)
        let previousMetadata = try Qwen3ModelStoreMetadata.metadata(for: previousManifest)
        let previousKey = ModelInstallKey(
            modelID: previousMetadata.modelID,
            version: previousMetadata.version
        )
        let previousStagingURL = ResumableModelDownloader.stagingRoot(
            for: previousKey,
            storeRoot: modelStoreRoot
        )
        try FileManager.default.createDirectory(at: previousStagingURL, withIntermediateDirectories: true)
        try Data("partial".utf8).write(to: previousStagingURL.appendingPathComponent("model.safetensors"))

        let manager = ASRManager(
            defaults: defaults,
            modelInstallationRepository: stateRepository,
            credentialStore: ASRProviderViewModelTestCredentialStore(),
            qwen3RuntimePreflight: { _ in .supported },
            modelStoreRoot: modelStoreRoot
        )
        manager.qwen3ModelSize = .size0_6B
        try stateRepository.save(
            .downloading(
                progress: ModelDownloadProgress(
                    bytesWritten: 42,
                    totalBytes: 100,
                    componentID: ModelComponentID(rawValue: "model.safetensors")
                )
            ),
            for: previousKey
        )
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let viewModel = ASRProviderViewModel(
            environment: environment,
            asrManager: manager,
            registry: ASRProviderRegistry(asrManager: manager)
        )

        viewModel.deleteLocalQwenModel()

        XCTAssertFalse(FileManager.default.fileExists(atPath: previousStagingURL.path))
        XCTAssertEqual(try stateRepository.state(for: previousKey), .notInstalled)
        XCTAssertEqual(viewModel.lastActionMessage, "已删除本地模型")
    }

    func testDeleteLocalFunASRModelClearsModelStoreStateAndRefreshesProvider() throws {
        let manager = makeManager()
        manager.funASRPrecision = .int8
        let modelURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FunASRDeleteTests-\(UUID().uuidString)", isDirectory: true)
        try createLoadableFunASRModelDirectory(at: modelURL, variant: .int8)
        manager.markFunASRModelReady(at: modelURL.path, precision: .int8)
        manager.selectedEngineType = .funASR
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let viewModel = ASRProviderViewModel(
            environment: environment,
            asrManager: manager,
            registry: ASRProviderRegistry(asrManager: manager)
        )

        viewModel.deleteLocalModel(id: ASRProviderID.funASR)

        let provider = try XCTUnwrap(viewModel.providers.first { $0.id == ASRProviderID.funASR })
        XCTAssertFalse(FileManager.default.fileExists(atPath: modelURL.path))
        XCTAssertFalse(manager.isFunASRModelAvailable)
        XCTAssertEqual(manager.funASRModelInstallationState(for: .int8), .notInstalled)
        XCTAssertFalse(provider.isAvailable)
        XCTAssertEqual(provider.localModelAction, .download)
        XCTAssertEqual(provider.statusMessage, "尚未安装本地模型")
        XCTAssertEqual(manager.selectedEngineType, .apple)
        XCTAssertEqual(viewModel.providers.first?.id, ASRProviderID.appleSpeech)
        XCTAssertEqual(viewModel.lastActionMessage, "已删除本地模型")
    }

    func testDeleteLocalFunASRModelRemovesPartialArchive() throws {
        let manager = makeManager()
        manager.funASRPrecision = .int8
        let partialURL = manager.funASRModelVariant.partialArchiveURL
        try FileManager.default.createDirectory(
            at: partialURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("partial".utf8).write(to: partialURL)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: partialURL)
        }
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let viewModel = ASRProviderViewModel(
            environment: environment,
            asrManager: manager,
            registry: ASRProviderRegistry(asrManager: manager)
        )

        viewModel.deleteLocalModel(id: ASRProviderID.funASR)

        XCTAssertFalse(FileManager.default.fileExists(atPath: partialURL.path))
        XCTAssertEqual(viewModel.lastActionMessage, "已删除本地模型")
    }

    func testDownloadDoesNotSaveIncompleteModelDirectory() async throws {
        let manager = makeManager()
        let modelURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceInputTests-\(UUID().uuidString)")
        try createIncompleteQwenDirectory(at: modelURL)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: modelURL)
        }
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let viewModel = ASRProviderViewModel(
            environment: environment,
            asrManager: manager,
            registry: ASRProviderRegistry(asrManager: manager),
            downloader: StubQwen3ModelDownloader(downloadedURL: modelURL)
        )

        await viewModel.downloadQwenModel()

        XCTAssertNil(manager.qwen3ModelPath)
        XCTAssertFalse(manager.isQwen3ModelAvailable)
        XCTAssertNil(viewModel.lastActionMessage)
        XCTAssertEqual(
            viewModel.lastError,
            "模型下载完成但缺少必要文件：model.safetensors、model.safetensors.index.json"
        )
    }

    func testLocalModelSizeSummaryShowsQwenManifestDownloadSize() throws {
        let manager = makeManager()
        manager.qwen3ModelSize = .size0_6B
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let viewModel = ASRProviderViewModel(
            environment: environment,
            asrManager: manager,
            registry: ASRProviderRegistry(asrManager: manager)
        )

        XCTAssertEqual(
            viewModel.localModelSizeSummary(providerID: ASRProviderID.qwen3),
            "约 712.8 MB"
        )
    }

    func testLocalModelSizeSummaryShowsAllLocalASRDownloadSizes() throws {
        let manager = makeManager()
        manager.funASRPrecision = .int8
        manager.whisperVariant = .turbo
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let viewModel = ASRProviderViewModel(
            environment: environment,
            asrManager: manager,
            registry: ASRProviderRegistry(asrManager: manager)
        )

        XCTAssertEqual(viewModel.localModelSizeSummary(providerID: ASRProviderID.funASR), "约 841.7 MB")
        XCTAssertEqual(viewModel.localModelSizeSummary(providerID: ASRProviderID.whisper), "约 632 MB")
        XCTAssertEqual(viewModel.localModelSizeSummary(providerID: ASRProviderID.senseVoice), "约 1.65 GB")
        XCTAssertEqual(viewModel.localModelSizeSummary(providerID: ASRProviderID.paraformer), "约 653.2 MB")
        XCTAssertEqual(viewModel.localModelSizeSummary(providerID: ASRProviderID.nvidiaNemotron), "约 642.2 MB")
        XCTAssertEqual(viewModel.localModelSizeSummary(providerID: ASRProviderID.parakeetStreaming), "约 118.1 MB")
        XCTAssertEqual(viewModel.localModelSizeSummary(providerID: ASRProviderID.omnilingualASR), "约 326.9 MB")
    }

    func testQwenPartialDownloadShowsResumeOnlyForSelectedModelSize() throws {
        let manager = makeManager()
        manager.qwen3ModelSize = .size1_7B
        manager.markModelDownloading(for: .qwen3, progress: partialDownloadProgress())
        manager.qwen3ModelSize = .size0_6B
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let viewModel = ASRProviderViewModel(
            environment: environment,
            asrManager: manager,
            registry: ASRProviderRegistry(asrManager: manager)
        )

        var qwenProvider = try XCTUnwrap(viewModel.providers.first { $0.id == ASRProviderID.qwen3 })
        XCTAssertEqual(qwenProvider.localModelAction, .download)
        XCTAssertEqual(qwenProvider.statusMessage, "尚未安装本地模型")

        manager.qwen3ModelSize = .size1_7B
        viewModel.load()

        qwenProvider = try XCTUnwrap(viewModel.providers.first { $0.id == ASRProviderID.qwen3 })
        XCTAssertEqual(qwenProvider.localModelAction, .resume)
        XCTAssertEqual(qwenProvider.statusMessage, "已下载 42%，可继续下载")
        XCTAssertFalse(qwenProvider.isAvailable)
    }

    func testPartialLocalModelDownloadsShowResumeActionAndProgress() throws {
        let manager = makeManager()
        manager.funASRPrecision = .int8
        manager.whisperVariant = .turbo
        let partialProgress = partialDownloadProgress()
        let providers: [(String, ASREngineType)] = [
            (ASRProviderID.funASR, .funASR),
            (ASRProviderID.whisper, .whisper),
            (ASRProviderID.senseVoice, .senseVoice),
            (ASRProviderID.paraformer, .paraformer),
            (ASRProviderID.nvidiaNemotron, .nvidiaNemotron),
            (ASRProviderID.parakeetStreaming, .parakeetStreaming),
            (ASRProviderID.omnilingualASR, .omnilingualASR),
        ]
        for (_, engineType) in providers {
            manager.markModelDownloading(for: engineType, progress: partialProgress)
        }
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let viewModel = ASRProviderViewModel(
            environment: environment,
            asrManager: manager,
            registry: ASRProviderRegistry(asrManager: manager)
        )

        for (providerID, _) in providers {
            let provider = try XCTUnwrap(viewModel.providers.first { $0.id == providerID })
            XCTAssertEqual(provider.localModelAction, .resume, providerID)
            XCTAssertEqual(provider.statusMessage, "已下载 42%，可继续下载", providerID)
            XCTAssertFalse(provider.isAvailable, providerID)
        }
    }

    func testDownloadSavesModelStoreValidatedQwenRootWithoutLegacyPathShape() async throws {
        let manager = makeManager()
        let modelURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceInputTests-\(UUID().uuidString)")
        try createLoadableQwen3ModelDirectory(at: modelURL)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: modelURL)
        }
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let viewModel = ASRProviderViewModel(
            environment: environment,
            asrManager: manager,
            registry: ASRProviderRegistry(asrManager: manager),
            downloader: StubQwen3ModelDownloader(
                downloadedURL: modelURL,
                missingPaths: []
            ),
            qwenReadinessPreparer: CapturingQwen3ViewModelReadinessPreparer()
        )

        await viewModel.downloadQwenModel()

        XCTAssertEqual(manager.qwen3ModelPath, modelURL.path)
        XCTAssertTrue(viewModel.providers.first(where: { $0.id == ASRProviderID.qwen3 })?.isAvailable ?? false)
        XCTAssertNil(viewModel.lastError)
        XCTAssertEqual(viewModel.lastActionMessage, "本地模型下载完成")
    }

    func testDownloadQwenDoesNotMarkReadyWhenPrewarmCanaryFails() async throws {
        let manager = makeManager()
        let modelURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceInputTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: modelURL, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: modelURL)
        }
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let viewModel = ASRProviderViewModel(
            environment: environment,
            asrManager: manager,
            registry: ASRProviderRegistry(asrManager: manager),
            downloader: StubQwen3ModelDownloader(
                downloadedURL: modelURL,
                missingPaths: []
            ),
            qwenReadinessPreparer: CapturingQwen3ViewModelReadinessPreparer(
                result: .failure(Qwen3ViewModelReadinessTestError.canaryFailed)
            )
        )

        await viewModel.downloadQwenModel()

        XCTAssertNil(manager.qwen3ModelPath)
        XCTAssertFalse(manager.isQwen3ModelAvailable)
        XCTAssertNil(viewModel.lastActionMessage)
        XCTAssertEqual(viewModel.lastError, "Canary failed")
    }

    func testDownloadWhisperTurboDoesNotReportSuccessWhenDownloadedDirectoryIsIncomplete() async throws {
        let manager = makeManager()
        manager.whisperVariant = .turbo
        let modelURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("WhisperKitTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: modelURL, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: modelURL)
        }
        let downloader = StubWhisperKitModelDownloader(downloadedURL: modelURL)
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let viewModel = ASRProviderViewModel(
            environment: environment,
            asrManager: manager,
            registry: ASRProviderRegistry(asrManager: manager),
            whisperKitModelDownloader: downloader
        )

        await viewModel.downloadModel(id: ASRProviderID.whisper)

        let requestedVariants = await downloader.requestedVariants()
        XCTAssertEqual(requestedVariants, [.turbo])
        XCTAssertNil(viewModel.lastActionMessage)
        XCTAssertEqual(viewModel.lastError, ASREngineError.modelNotLoaded.localizedDescription)
    }

    func testDownloadWhisperLargeV3MarksModelStoreReadyState() async throws {
        let manager = makeManager()
        manager.whisperVariant = .largeV3
        let modelURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("WhisperLargeTests-\(UUID().uuidString)", isDirectory: true)
        try createLoadableWhisperModelDirectory(at: modelURL, variant: .largeV3)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: modelURL)
        }
        let downloader = StubWhisperKitModelDownloader(downloadedURL: modelURL)
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let viewModel = ASRProviderViewModel(
            environment: environment,
            asrManager: manager,
            registry: ASRProviderRegistry(asrManager: manager),
            whisperKitModelDownloader: downloader
        )

        await viewModel.downloadModel(id: ASRProviderID.whisper)

        let requestedVariants = await downloader.requestedVariants()
        XCTAssertEqual(requestedVariants, [.largeV3])
        XCTAssertEqual(viewModel.lastActionMessage, "本地模型下载完成")
        XCTAssertNil(viewModel.lastError)
        XCTAssertTrue(manager.isWhisperModelAvailable(for: .largeV3))
    }

    func testDownloadModelIgnoresReentryWhileDownloadIsRunning() async throws {
        let manager = makeManager()
        manager.whisperVariant = .largeV3
        let modelURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("WhisperReentryTests-\(UUID().uuidString)", isDirectory: true)
        try createLoadableWhisperModelDirectory(at: modelURL, variant: .largeV3)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: modelURL)
        }
        let downloader = BlockingWhisperKitModelDownloader(downloadedURL: modelURL)
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let viewModel = ASRProviderViewModel(
            environment: environment,
            asrManager: manager,
            registry: ASRProviderRegistry(asrManager: manager),
            whisperKitModelDownloader: downloader
        )

        let first = Task { @MainActor in
            await viewModel.downloadModel(id: ASRProviderID.whisper)
        }
        await downloader.waitUntilRequestCount(1)

        let second = Task { @MainActor in
            await viewModel.downloadModel(id: ASRProviderID.whisper)
        }
        try await Task.sleep(nanoseconds: 50_000_000)

        let requestCount = await downloader.requestCountSnapshot()
        XCTAssertEqual(requestCount, 1)

        await downloader.finishAll()
        await first.value
        await second.value
    }

    func testQwenDownloadPersistsPartialProgressForRequestedModelSize() async throws {
        let manager = makeManager()
        manager.qwen3ModelSize = .size1_7B
        let modelURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("QwenPartialProgressTests-\(UUID().uuidString)", isDirectory: true)
        try createLoadableQwen3ModelDirectory(at: modelURL)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: modelURL)
        }
        let downloader = BlockingQwen3ModelDownloader(downloadedURL: modelURL)
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let viewModel = ASRProviderViewModel(
            environment: environment,
            asrManager: manager,
            registry: ASRProviderRegistry(asrManager: manager),
            downloader: downloader,
            qwenReadinessPreparer: CapturingQwen3ViewModelReadinessPreparer()
        )

        let downloadTask = Task { @MainActor in
            await viewModel.downloadModel(id: ASRProviderID.qwen3)
        }
        await downloader.waitUntilRequestCount(1)
        manager.qwen3ModelSize = .size0_6B

        XCTAssertEqual(manager.qwen3ModelInstallationState(for: .size0_6B), .notInstalled)
        guard case let .downloading(progress) = manager.qwen3ModelInstallationState(for: .size1_7B) else {
            return XCTFail("Expected Qwen 1.7B partial download state")
        }
        XCTAssertEqual(progress.fractionCompleted ?? 0, 0.1, accuracy: 0.001)

        await downloader.finishAll()
        await downloadTask.value
    }

    func testWhisperDownloadPersistsPartialProgressForResumeDisplay() async throws {
        let manager = makeManager()
        manager.whisperVariant = .turbo
        let modelURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("WhisperPartialProgressTests-\(UUID().uuidString)", isDirectory: true)
        try createLoadableWhisperModelDirectory(at: modelURL, variant: .turbo)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: modelURL)
        }
        let downloader = BlockingWhisperKitModelDownloader(downloadedURL: modelURL)
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let viewModel = ASRProviderViewModel(
            environment: environment,
            asrManager: manager,
            registry: ASRProviderRegistry(asrManager: manager),
            whisperKitModelDownloader: downloader
        )

        let downloadTask = Task { @MainActor in
            await viewModel.downloadModel(id: ASRProviderID.whisper)
        }
        await downloader.waitUntilRequestCount(1)

        guard case let .downloading(progress) = manager.whisperModelInstallationState(for: .turbo) else {
            return XCTFail("Expected Whisper partial download state")
        }
        XCTAssertEqual(progress.fractionCompleted ?? 0, 0.1, accuracy: 0.001)

        await downloader.finishAll()
        await downloadTask.value
    }

    func testDeleteQwenDuringDownloadReenablesCleanupAndDownloadControls() async throws {
        let manager = makeManager()
        manager.qwen3ModelSize = .size1_7B
        let modelURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("QwenDeleteWhileDownloading-\(UUID().uuidString)", isDirectory: true)
        try createLoadableQwen3ModelDirectory(at: modelURL)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: modelURL)
        }
        let downloader = BlockingQwen3ModelDownloader(downloadedURL: modelURL)
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let viewModel = ASRProviderViewModel(
            environment: environment,
            asrManager: manager,
            registry: ASRProviderRegistry(asrManager: manager),
            downloader: downloader,
            qwenReadinessPreparer: CapturingQwen3ViewModelReadinessPreparer()
        )

        let downloadTask = Task { @MainActor in
            await viewModel.downloadModel(id: ASRProviderID.qwen3)
        }
        await downloader.waitUntilRequestCount(1)

        XCTAssertTrue(viewModel.isDownloading)

        viewModel.deleteLocalQwenModel()
        await waitUntil { !viewModel.isDownloading }

        XCTAssertFalse(viewModel.isDownloading)
        XCTAssertNil(viewModel.downloadingProviderID)
        let qwenProvider = try XCTUnwrap(viewModel.providers.first { $0.id == ASRProviderID.qwen3 })
        XCTAssertEqual(qwenProvider.localModelAction, .download)
        XCTAssertEqual(viewModel.lastActionMessage, "已删除本地模型")

        await downloader.finishAll()
        await downloadTask.value
    }

    func testDeletedQwenDownloadDoesNotMarkModelReadyAfterItFinishes() async throws {
        let manager = makeManager()
        manager.qwen3ModelSize = .size1_7B
        let modelURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("QwenDeletedDownloadCompletes-\(UUID().uuidString)", isDirectory: true)
        try createLoadableQwen3ModelDirectory(at: modelURL)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: modelURL)
        }
        let downloader = BlockingQwen3ModelDownloader(downloadedURL: modelURL)
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let viewModel = ASRProviderViewModel(
            environment: environment,
            asrManager: manager,
            registry: ASRProviderRegistry(asrManager: manager),
            downloader: downloader,
            qwenReadinessPreparer: CapturingQwen3ViewModelReadinessPreparer()
        )

        let downloadTask = Task { @MainActor in
            await viewModel.downloadModel(id: ASRProviderID.qwen3)
        }
        await downloader.waitUntilRequestCount(1)

        viewModel.deleteLocalQwenModel()
        await waitUntil { !viewModel.isDownloading }
        manager.qwen3ModelSize = .size0_6B
        await downloader.finishAll()
        await downloadTask.value

        XCTAssertNil(manager.qwen3ModelPath)
        XCTAssertEqual(manager.qwen3ModelSize, .size0_6B)
        XCTAssertFalse(manager.isQwen3ModelAvailable)
        XCTAssertEqual(viewModel.lastActionMessage, "已删除本地模型")
    }

    func testDeleteFunASRDuringDownloadCancelsAndIgnoresCompletedResult() async throws {
        let manager = makeManager()
        manager.funASRPrecision = .int8
        let modelURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FunASRDeletedDownloadCompletes-\(UUID().uuidString)", isDirectory: true)
        try createLoadableFunASRModelDirectory(at: modelURL, variant: .int8)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: modelURL)
        }
        let downloader = BlockingSherpaASRModelDownloader(downloadedURL: modelURL)
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let viewModel = ASRProviderViewModel(
            environment: environment,
            asrManager: manager,
            registry: ASRProviderRegistry(asrManager: manager),
            sherpaModelDownloader: downloader
        )

        let downloadTask = Task { @MainActor in
            await viewModel.downloadModel(id: ASRProviderID.funASR)
        }
        await downloader.waitUntilRequestCount(1)

        viewModel.deleteLocalModel(id: ASRProviderID.funASR)
        await waitUntil { !viewModel.isDownloading }
        let cancelCount = await downloader.cancelCountSnapshot()
        XCTAssertEqual(cancelCount, 1)

        await downloader.finishAll()
        await downloadTask.value

        XCTAssertFalse(manager.isFunASRModelAvailable)
        XCTAssertEqual(manager.funASRModelInstallationState(for: .int8), .notInstalled)
        XCTAssertEqual(viewModel.lastActionMessage, "已删除本地模型")
    }

    func testDownloadFunASRMarksModelStoreReadyState() async throws {
        let manager = makeManager()
        manager.funASRPrecision = .int8
        let modelURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FunASRTests-\(UUID().uuidString)", isDirectory: true)
        try createLoadableFunASRModelDirectory(at: modelURL, variant: .int8)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: modelURL)
        }
        let downloader = StubSherpaASRModelDownloader(downloadedURL: modelURL)
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let viewModel = ASRProviderViewModel(
            environment: environment,
            asrManager: manager,
            registry: ASRProviderRegistry(asrManager: manager),
            sherpaModelDownloader: downloader
        )

        await viewModel.downloadModel(id: ASRProviderID.funASR)

        let requestedVariants = await downloader.requestedVariants()
        XCTAssertEqual(requestedVariants, [.funASRInt8])
        XCTAssertTrue(manager.isFunASRModelAvailable)
        XCTAssertTrue(viewModel.providers.first(where: { $0.id == ASRProviderID.funASR })?.isAvailable ?? false)
        XCTAssertNil(viewModel.lastError)
        XCTAssertEqual(viewModel.lastActionMessage, "本地模型下载完成")
    }

    func testDownloadFunASRPublishesDownloadedBytes() async throws {
        let manager = makeManager()
        manager.funASRPrecision = .int8
        let modelURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FunASRProgressTests-\(UUID().uuidString)", isDirectory: true)
        try createLoadableFunASRModelDirectory(at: modelURL, variant: .int8)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: modelURL)
        }
        let downloader = StubSherpaASRModelDownloader(
            downloadedURL: modelURL,
            progressUpdates: [
                .init(
                    fractionCompleted: 0.42,
                    status: "下载 sherpa-onnx-funasr-nano-int8-2025-12-30.tar.bz2",
                    bytesWritten: 42,
                    totalBytes: 100
                ),
            ]
        )
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let viewModel = ASRProviderViewModel(
            environment: environment,
            asrManager: manager,
            registry: ASRProviderRegistry(asrManager: manager),
            sherpaModelDownloader: downloader
        )

        await viewModel.downloadModel(id: ASRProviderID.funASR)

        let progress = try XCTUnwrap(viewModel.downloadProgress)
        XCTAssertEqual(progress.bytesWritten, 42)
        XCTAssertEqual(progress.totalBytes, 100)
        XCTAssertTrue(progress.detailText.contains("42"))
        XCTAssertTrue(progress.detailText.contains("100"))
        XCTAssertTrue(progress.detailText.contains("42%"))
        XCTAssertEqual(progress.modelSizeText, "模型大小 841.7 MB")
    }

    func testDownloadSenseVoiceMarksModelStoreReadyState() async throws {
        let manager = makeManager()
        let modelURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SenseVoiceTests-\(UUID().uuidString)", isDirectory: true)
        try createLoadableSenseVoiceModelDirectory(at: modelURL)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: modelURL)
        }
        let downloader = StubSenseVoiceModelDownloader(downloadedURL: modelURL)
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let viewModel = ASRProviderViewModel(
            environment: environment,
            asrManager: manager,
            registry: ASRProviderRegistry(asrManager: manager),
            senseVoiceModelDownloader: downloader
        )

        await viewModel.downloadModel(id: ASRProviderID.senseVoice)

        let requestCount = await downloader.requestCount
        XCTAssertEqual(requestCount, 1)
        XCTAssertTrue(manager.isSenseVoiceModelAvailable)
        XCTAssertTrue(viewModel.providers.first(where: { $0.id == ASRProviderID.senseVoice })?.isAvailable ?? false)
        XCTAssertNil(viewModel.lastError)
        XCTAssertEqual(viewModel.lastActionMessage, "本地模型下载完成")
    }

    func testDownloadParaformerMarksModelStoreReadyState() async throws {
        let manager = makeManager()
        let modelURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ParaformerTests-\(UUID().uuidString)", isDirectory: true)
        try createLoadableParaformerModelDirectory(at: modelURL)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: modelURL)
        }
        let downloader = StubParaformerModelDownloader(downloadedURL: modelURL)
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let viewModel = ASRProviderViewModel(
            environment: environment,
            asrManager: manager,
            registry: ASRProviderRegistry(asrManager: manager),
            paraformerModelDownloader: downloader
        )

        await viewModel.downloadModel(id: ASRProviderID.paraformer)

        let requestCount = await downloader.requestCount
        XCTAssertEqual(requestCount, 1)
        XCTAssertTrue(manager.isParaformerModelAvailable)
        XCTAssertTrue(viewModel.providers.first(where: { $0.id == ASRProviderID.paraformer })?.isAvailable ?? false)
        XCTAssertNil(viewModel.lastError)
        XCTAssertEqual(viewModel.lastActionMessage, "本地模型下载完成")
    }

    private func makeManager() -> ASRManager {
        makeManagerAndRepository().manager
    }

    private func makeManagerAndRepository() -> (
        manager: ASRManager,
        repository: FileModelInstallationStateRepository
    ) {
        let suiteName = "test.ASRProviderViewModel.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let stateRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("ASRProviderViewModelTests-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: stateRoot)
        }
        let repository = FileModelInstallationStateRepository(
            fileURL: stateRoot.appendingPathComponent("installation-states.json")
        )
        return (
            ASRManager(
                defaults: defaults,
                modelInstallationRepository: repository,
                credentialStore: ASRProviderViewModelTestCredentialStore(),
                qwen3RuntimePreflight: { _ in .supported }
            ),
            repository
        )
    }

    private func saveQwenState(
        _ state: ModelInstallationState,
        in repository: FileModelInstallationStateRepository
    ) throws {
        let metadata = try Qwen3ModelStoreMetadata.metadata(for: Qwen3ModelManifest.manifest(for: .size0_6B))
        let key = ModelInstallKey(modelID: metadata.modelID, version: metadata.version)
        try repository.save(state, for: key)
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

    private func partialDownloadProgress() -> ModelDownloadProgress {
        ModelDownloadProgress(
            bytesWritten: 42,
            totalBytes: 100,
            componentID: ModelComponentID(rawValue: "model.safetensors")
        )
    }

    private func waitUntil(
        _ condition: () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<100 where !condition() {
            await Task.yield()
        }
        XCTAssertTrue(condition(), file: file, line: line)
    }

    private func createIncompleteQwenDirectory(at modelURL: URL) throws {
        let paths = [
            "config.json",
            "merges.txt",
            "tokenizer_config.json",
            "vocab.json",
        ]
        for relativePath in paths {
            let fileURL = modelURL.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            XCTAssertTrue(FileManager.default.createFile(atPath: fileURL.path, contents: Data()))
        }
    }

    private func createLoadableFunASRModelDirectory(
        at modelURL: URL,
        variant: FunASRModelVariant
    ) throws {
        for relativePath in variant.requiredPaths {
            let fileURL = modelURL.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data([1]).write(to: fileURL)
        }
    }

    private func createLoadableWhisperModelDirectory(
        at modelURL: URL,
        variant: WhisperKitModelVariant
    ) throws {
        for relativePath in variant.requiredPaths {
            let directoryURL = modelURL.appendingPathComponent(relativePath, isDirectory: true)
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            let fileURL = directoryURL.appendingPathComponent("weights.bin", isDirectory: false)
            XCTAssertTrue(FileManager.default.createFile(atPath: fileURL.path, contents: Data([1])))
        }
    }

    private func createLoadableSenseVoiceModelDirectory(at modelURL: URL) throws {
        let paths = [
            "SenseVoicePreprocessor.mlmodelc/coremldata.bin",
            "SenseVoiceSmall.mlmodelc/coremldata.bin",
            "vocab.json",
        ]
        for relativePath in paths {
            let fileURL = modelURL.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data([1]).write(to: fileURL)
        }
    }

    private func createLoadableParaformerModelDirectory(at modelURL: URL) throws {
        let paths = [
            "ParaformerPreprocessor.mlmodelc/coremldata.bin",
            "ParaformerEncoder_int8.mlmodelc/coremldata.bin",
            "ParaformerCifAlphas.mlmodelc/coremldata.bin",
            "ParaformerDecoder_int8.mlmodelc/coremldata.bin",
            "vocab.json",
        ]
        for relativePath in paths {
            let fileURL = modelURL.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data([1]).write(to: fileURL)
        }
    }

}

private struct StubQwen3ModelDownloader: Qwen3ModelDownloading {
    let downloadedURL: URL
    var missingPaths: [String]?

    func download(
        manifest: Qwen3ModelManifest,
        progress: @escaping Qwen3ModelDownloader.ProgressHandler
    ) async throws -> URL {
        downloadedURL
    }

    nonisolated func missingRequiredLocalPaths(
        size: ASRManager.ModelSize,
        at directory: URL,
        fileManager: FileManager
    ) -> [String] {
        if let missingPaths {
            return missingPaths
        }
        return Qwen3ModelManifest.manifest(for: size)
            .missingRequiredLocalPaths(at: directory, fileManager: fileManager)
    }
}

private actor BlockingQwen3ModelDownloader: Qwen3ModelDownloading {
    private let downloadedURL: URL
    private var requestCount = 0
    private var requestCountWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private var releaseContinuations: [CheckedContinuation<Void, Never>] = []
    private var released = false

    init(downloadedURL: URL) {
        self.downloadedURL = downloadedURL
    }

    func download(
        manifest: Qwen3ModelManifest,
        progress: @escaping Qwen3ModelDownloader.ProgressHandler
    ) async throws -> URL {
        requestCount += 1
        resumeSatisfiedRequestCountWaiters()
        await progress(.init(fileIndex: 0, fileCount: 1, fileName: "model.safetensors", fileProgress: 0.1))
        await waitForRelease()
        await progress(.init(fileIndex: 0, fileCount: 1, fileName: "model.safetensors", fileProgress: 1))
        return downloadedURL
    }

    nonisolated func missingRequiredLocalPaths(
        size: ASRManager.ModelSize,
        at directory: URL,
        fileManager: FileManager
    ) -> [String] {
        []
    }

    func waitUntilRequestCount(_ expected: Int) async {
        if requestCount >= expected { return }
        await withCheckedContinuation { continuation in
            requestCountWaiters.append((expected, continuation))
        }
    }

    func finishAll() {
        released = true
        let continuations = releaseContinuations
        releaseContinuations.removeAll()
        continuations.forEach { $0.resume() }
    }

    private func waitForRelease() async {
        if released { return }
        await withCheckedContinuation { continuation in
            releaseContinuations.append(continuation)
        }
    }

    private func resumeSatisfiedRequestCountWaiters() {
        let satisfied = requestCountWaiters.filter { requestCount >= $0.0 }
        requestCountWaiters.removeAll { requestCount >= $0.0 }
        satisfied.forEach { $0.1.resume() }
    }
}

private actor StubWhisperKitModelDownloader: WhisperKitModelDownloading {
    private let downloadedURL: URL
    private var variants: [WhisperKitModelVariant] = []

    init(downloadedURL: URL) {
        self.downloadedURL = downloadedURL
    }

    func download(
        variant: WhisperKitModelVariant,
        modelsDirectory: URL,
        progress: @escaping @MainActor @Sendable (WhisperKitModelDownloadProgress) -> Void
    ) async throws -> URL {
        variants.append(variant)
        await progress(.init(fractionCompleted: 1, status: "模型已就绪"))
        return downloadedURL
    }

    func requestedVariants() -> [WhisperKitModelVariant] {
        variants
    }
}

private actor BlockingWhisperKitModelDownloader: WhisperKitModelDownloading {
    private let downloadedURL: URL
    private var requestCount = 0
    private var requestCountWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private var releaseContinuations: [CheckedContinuation<Void, Never>] = []
    private var released = false

    init(downloadedURL: URL) {
        self.downloadedURL = downloadedURL
    }

    func download(
        variant: WhisperKitModelVariant,
        modelsDirectory: URL,
        progress: @escaping @MainActor @Sendable (WhisperKitModelDownloadProgress) -> Void
    ) async throws -> URL {
        requestCount += 1
        resumeSatisfiedRequestCountWaiters()
        await progress(.init(fractionCompleted: 0.1, status: "下载中"))
        await waitForRelease()
        await progress(.init(fractionCompleted: 1, status: "模型已就绪"))
        return downloadedURL
    }

    func waitUntilRequestCount(_ expected: Int) async {
        if requestCount >= expected { return }
        await withCheckedContinuation { continuation in
            requestCountWaiters.append((expected, continuation))
        }
    }

    func requestCountSnapshot() -> Int {
        requestCount
    }

    func finishAll() {
        released = true
        let continuations = releaseContinuations
        releaseContinuations.removeAll()
        continuations.forEach { $0.resume() }
    }

    private func waitForRelease() async {
        if released { return }
        await withCheckedContinuation { continuation in
            releaseContinuations.append(continuation)
        }
    }

    private func resumeSatisfiedRequestCountWaiters() {
        let satisfied = requestCountWaiters.filter { requestCount >= $0.0 }
        requestCountWaiters.removeAll { requestCount >= $0.0 }
        satisfied.forEach { $0.1.resume() }
    }
}

private actor StubSherpaASRModelDownloader: SherpaASRModelDownloading {
    private let downloadedURL: URL
    private let progressUpdates: [SherpaASRModelDownloadProgress]
    private var variants: [SherpaASRModelVariant] = []

    init(
        downloadedURL: URL,
        progressUpdates: [SherpaASRModelDownloadProgress] = [.init(fractionCompleted: 1, status: "模型已就绪")]
    ) {
        self.downloadedURL = downloadedURL
        self.progressUpdates = progressUpdates
    }

    func download(
        variant: SherpaASRModelVariant,
        progress: @escaping @MainActor @Sendable (SherpaASRModelDownloadProgress) -> Void
    ) async throws -> URL {
        variants.append(variant)
        for update in progressUpdates {
            await progress(update)
        }
        return downloadedURL
    }

    func requestedVariants() -> [SherpaASRModelVariant] {
        variants
    }
}

private actor BlockingSherpaASRModelDownloader: SherpaASRModelDownloading {
    private let downloadedURL: URL
    private var requestCount = 0
    private var cancelCount = 0
    private var requestCountWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private var releaseContinuations: [CheckedContinuation<Void, Never>] = []
    private var released = false

    init(downloadedURL: URL) {
        self.downloadedURL = downloadedURL
    }

    func download(
        variant: SherpaASRModelVariant,
        progress: @escaping @MainActor @Sendable (SherpaASRModelDownloadProgress) -> Void
    ) async throws -> URL {
        requestCount += 1
        resumeSatisfiedRequestCountWaiters()
        await progress(.init(fractionCompleted: 0.1, status: "下载中", bytesWritten: 42, totalBytes: 100))
        await waitForRelease()
        await progress(.init(fractionCompleted: 1, status: "模型已就绪", bytesWritten: 100, totalBytes: 100))
        return downloadedURL
    }

    func cancelDownload() async {
        cancelCount += 1
    }

    func waitUntilRequestCount(_ expected: Int) async {
        if requestCount >= expected { return }
        await withCheckedContinuation { continuation in
            requestCountWaiters.append((expected, continuation))
        }
    }

    func cancelCountSnapshot() -> Int {
        cancelCount
    }

    func finishAll() {
        released = true
        let continuations = releaseContinuations
        releaseContinuations.removeAll()
        continuations.forEach { $0.resume() }
    }

    private func waitForRelease() async {
        if released { return }
        await withCheckedContinuation { continuation in
            releaseContinuations.append(continuation)
        }
    }

    private func resumeSatisfiedRequestCountWaiters() {
        let satisfied = requestCountWaiters.filter { requestCount >= $0.0 }
        requestCountWaiters.removeAll { requestCount >= $0.0 }
        satisfied.forEach { $0.1.resume() }
    }
}

private actor StubSenseVoiceModelDownloader: SenseVoiceModelDownloading {
    private let downloadedURL: URL
    private(set) var requestCount = 0

    init(downloadedURL: URL) {
        self.downloadedURL = downloadedURL
    }

    func download(
        progress: @escaping @MainActor @Sendable (SenseVoiceModelDownloadProgress) -> Void
    ) async throws -> URL {
        requestCount += 1
        await progress(.init(fractionCompleted: 1, status: "模型已就绪"))
        return downloadedURL
    }
}

private final class ASRProviderViewModelTestCredentialStore: CredentialStore {
    func readCredential(account: String) throws -> String? { nil }
    func saveCredential(_ value: String, account: String) throws {}
    func deleteCredential(account: String) throws {}
}

private actor StubParaformerModelDownloader: ParaformerModelDownloading {
    private let downloadedURL: URL
    private(set) var requestCount = 0

    init(downloadedURL: URL) {
        self.downloadedURL = downloadedURL
    }

    func download(
        progress: @escaping @MainActor @Sendable (ParaformerModelDownloadProgress) -> Void
    ) async throws -> URL {
        requestCount += 1
        await progress(.init(fractionCompleted: 1, status: "模型已就绪"))
        return downloadedURL
    }
}

private enum Qwen3ViewModelReadinessTestError: Error, LocalizedError, Equatable {
    case canaryFailed

    var errorDescription: String? {
        switch self {
        case .canaryFailed:
            return "Canary failed"
        }
    }
}

private actor CapturingQwen3ViewModelReadinessPreparer: Qwen3ModelReadinessPreparing {
    private let result: Result<Void, Error>

    init(result: Result<Void, Error> = .success(())) {
        self.result = result
    }

    func prepare(modelURL: URL, size: ASRManager.ModelSize) async throws {
        try result.get()
    }
}
