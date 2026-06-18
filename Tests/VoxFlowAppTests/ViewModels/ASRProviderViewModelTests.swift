import XCTest
import VoxFlowModelStore
import VoxFlowProviderFunASR
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
            ASRProviderID.paraformer,
            ASRProviderID.qwen3,
            ASRProviderID.senseVoice,
            ASRProviderID.whisper,
            ASRProviderID.groqWhisper,
            ASRProviderID.qwenCloudASR,
            ASRProviderID.mistralVoxtral,
            ASRProviderID.assemblyAI,
            ASRProviderID.volcengineDoubao,
            ASRProviderID.elevenLabsScribe,
        ]))
        XCTAssertEqual(viewModel.providers.first?.isDefault, true)
        XCTAssertEqual(
            viewModel.providers.first { $0.id == ASRProviderID.funASR }?.statusMessage,
            "尚未安装本地模型"
        )
        XCTAssertEqual(try environment.asrProviderRepository.list().count, 13)
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

    func testTagFilterNarrowsVisibleProviders() throws {
        let manager = makeManager()
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let viewModel = ASRProviderViewModel(
            environment: environment,
            asrManager: manager,
            registry: ASRProviderRegistry(asrManager: manager)
        )

        viewModel.toggleTag("本地")

        XCTAssertEqual(Set(viewModel.visibleProviders.map(\.id)),
                       [ASRProviderID.funASR, ASRProviderID.whisper, ASRProviderID.qwen3,
                        ASRProviderID.senseVoice, ASRProviderID.paraformer,
                        ASRProviderID.nvidiaNemotron])
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
                ASRProviderID.qwenCloudASR,
                ASRProviderID.mistralVoxtral,
                ASRProviderID.assemblyAI,
                ASRProviderID.volcengineDoubao,
                ASRProviderID.elevenLabsScribe,
            ]
        )
        XCTAssertFalse(viewModel.visibleProviders.contains { $0.id == ASRProviderID.appleSpeech })

        viewModel.selectProviderScope(.offline)

        XCTAssertEqual(
            Set(viewModel.visibleProviders.map(\.id)),
            [
                ASRProviderID.funASR,
                ASRProviderID.whisper,
                ASRProviderID.qwen3,
                ASRProviderID.senseVoice,
                ASRProviderID.paraformer,
                ASRProviderID.nvidiaNemotron,
            ]
        )
    }

    func testProviderScopeControlOrderIsAllOfflineOnline() {
        XCTAssertEqual(ASRProviderScope.allCases, [.all, .offline, .online])
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

    func testQwenCloudLinksUseReachableOfficialAliyunDocumentation() throws {
        let manager = makeManager()
        let registry = ASRProviderRegistry(asrManager: manager)
        let provider = try XCTUnwrap(registry.descriptor(id: ASRProviderID.qwenCloudASR))
        let links = try XCTUnwrap(provider.externalLinks)

        XCTAssertEqual(links.modelsURL?.host, "help.aliyun.com")
        XCTAssertEqual(links.guideURL?.host, "help.aliyun.com")
    }

    func testAvailableTagsFollowSelectedProviderScope() throws {
        let manager = makeManager()
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let viewModel = ASRProviderViewModel(
            environment: environment,
            asrManager: manager,
            registry: ASRProviderRegistry(asrManager: manager)
        )

        viewModel.selectProviderScope(.online)

        XCTAssertTrue(viewModel.availableTags.contains("在线"))
        XCTAssertTrue(viewModel.availableTags.contains("实时"))
        XCTAssertFalse(viewModel.availableTags.contains("离线"))
        XCTAssertFalse(viewModel.availableTags.contains("CoreML"))
        XCTAssertFalse(viewModel.availableTags.contains("0.22B"))
    }

    func testChangingProviderScopeClearsIncompatibleTagSelection() throws {
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
        XCTAssertEqual(manager.selectedEngineType, .apple)
        XCTAssertEqual(viewModel.providers.first?.id, ASRProviderID.appleSpeech)
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
        XCTAssertEqual(viewModel.lastError, "模型下载完成但缺少必要文件：vocab.json")
    }

    func testDownloadSavesModelStoreValidatedQwenRootWithoutLegacyPathShape() async throws {
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

    func testDownloadQwen17AttemptsRuntimeProvisioningBeforeModelDownload() async throws {
        let manager = makeManager()
        manager.qwen3ModelSize = .size1_7B
        let runtimeProvisioner = CapturingQwen3ViewModelRuntimeProvisioner(
            result: .failure(Qwen3ViewModelReadinessTestError.runtimeProvisionFailed)
        )
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let viewModel = ASRProviderViewModel(
            environment: environment,
            asrManager: manager,
            registry: ASRProviderRegistry(asrManager: manager),
            downloader: FailingQwen3ModelDownloader(),
            qwenRuntimeProvisioner: runtimeProvisioner
        )

        await viewModel.downloadQwenModel()

        XCTAssertNil(manager.qwen3ModelPath)
        XCTAssertNil(viewModel.lastActionMessage)
        XCTAssertEqual(viewModel.lastError, "Runtime provision failed")
        let prepareCallCount = await runtimeProvisioner.prepareCallCount
        XCTAssertEqual(prepareCallCount, 1)
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
                modelInstallationRepository: repository
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
        try createValidEmbeddingFile(at: modelURL.appendingPathComponent("qwen3_asr_embeddings.bin"))
    }

    private func createValidEmbeddingFile(at url: URL) throws {
        var header = Data()
        var vocabSize = UInt32(151_936).littleEndian
        var hiddenSize = UInt32(1_024).littleEndian
        withUnsafeBytes(of: &vocabSize) { header.append(contentsOf: $0) }
        withUnsafeBytes(of: &hiddenSize) { header.append(contentsOf: $0) }
        try header.write(to: url)
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: 8 + UInt64(151_936) * 1_024 * 2)
        try handle.close()
    }

    private func createIncompleteQwenDirectory(at modelURL: URL) throws {
        let paths = [
            "qwen3_asr_audio_encoder_v2.mlmodelc/coremldata.bin",
            "qwen3_asr_decoder_stateful.mlmodelc/coremldata.bin",
            "qwen3_asr_embeddings.bin",
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

    func missingRequiredLocalPaths(
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

private struct FailingQwen3ModelDownloader: Qwen3ModelDownloading {
    func download(
        manifest: Qwen3ModelManifest,
        progress: @escaping Qwen3ModelDownloader.ProgressHandler
    ) async throws -> URL {
        XCTFail("1.7B should fail before invoking the downloader.")
        return URL(fileURLWithPath: "/tmp/unreachable")
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

private actor StubSherpaASRModelDownloader: SherpaASRModelDownloading {
    private let downloadedURL: URL
    private var variants: [SherpaASRModelVariant] = []

    init(downloadedURL: URL) {
        self.downloadedURL = downloadedURL
    }

    func download(
        variant: SherpaASRModelVariant,
        progress: @escaping @MainActor @Sendable (SherpaASRModelDownloadProgress) -> Void
    ) async throws -> URL {
        variants.append(variant)
        await progress(.init(fractionCompleted: 1, status: "模型已就绪"))
        return downloadedURL
    }

    func requestedVariants() -> [SherpaASRModelVariant] {
        variants
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

private enum Qwen3ViewModelReadinessTestError: Error, LocalizedError, Equatable {
    case canaryFailed
    case runtimeProvisionFailed

    var errorDescription: String? {
        switch self {
        case .canaryFailed:
            return "Canary failed"
        case .runtimeProvisionFailed:
            return "Runtime provision failed"
        }
    }
}

private actor CapturingQwen3ViewModelRuntimeProvisioner: Qwen3MLXRuntimeProvisioning {
    private let result: Result<URL, Error>
    private(set) var prepareCallCount = 0

    init(result: Result<URL, Error>) {
        self.result = result
    }

    func prepare() async throws -> URL {
        prepareCallCount += 1
        return try result.get()
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
