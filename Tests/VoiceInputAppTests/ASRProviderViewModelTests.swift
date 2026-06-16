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

        // Sorted by displayName (Apple always first, then alphabetical)
        XCTAssertEqual(viewModel.providers.map(\.id),
                       [ASRProviderID.appleSpeech, ASRProviderID.funASR,
                        ASRProviderID.paraformer, ASRProviderID.qwen3,
                        ASRProviderID.senseVoice, ASRProviderID.whisper])
        XCTAssertEqual(viewModel.providers.first?.isDefault, true)
        XCTAssertEqual(viewModel.providers[1].statusMessage, "尚未安装本地模型")
        XCTAssertEqual(try environment.asrProviderRepository.list().count, 6)
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
                        ASRProviderID.paraformer, ASRProviderID.senseVoice])
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
        viewModel.selectWhisperVariant(.largeV3)
        viewModel.selectParaformerLanguage(.english)

        XCTAssertEqual(manager.funASRPrecision, .fp32)
        XCTAssertEqual(manager.whisperVariant, .largeV3)
        XCTAssertEqual(manager.paraformerLanguage, .english)
        XCTAssertEqual(viewModel.sherpaVariant(for: ASRProviderID.funASR), .funASRFP32)
        XCTAssertNil(viewModel.sherpaVariant(for: ASRProviderID.whisper))
        XCTAssertEqual(viewModel.whisperKitVariant(for: ASRProviderID.whisper), .largeV3)
        XCTAssertEqual(viewModel.sherpaVariant(for: ASRProviderID.paraformer), .paraformerEnglish)
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

    func testDownloadQwen17DoesNotCreateUnsupportedLocalModel() async throws {
        let manager = makeManager()
        manager.qwen3ModelSize = .size1_7B
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let viewModel = ASRProviderViewModel(
            environment: environment,
            asrManager: manager,
            registry: ASRProviderRegistry(asrManager: manager),
            downloader: FailingQwen3ModelDownloader()
        )

        await viewModel.downloadQwenModel()

        XCTAssertNil(manager.qwen3ModelPath)
        XCTAssertNil(viewModel.lastActionMessage)
        XCTAssertEqual(
            viewModel.lastError,
            "Qwen3-ASR 1.7B 的本地运行时尚未接入；当前 CoreML 引擎只支持 0.6B。"
        )
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
}

private struct StubQwen3ModelDownloader: Qwen3ModelDownloading {
    let downloadedURL: URL

    func download(
        manifest: Qwen3ModelManifest,
        progress: @escaping Qwen3ModelDownloader.ProgressHandler
    ) async throws -> URL {
        downloadedURL
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
