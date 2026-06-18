import XCTest
import VoxFlowModelStore
import VoxFlowProviderFunASR
import VoxFlowProviderQwen3
import VoxFlowProviderSenseVoice
import VoxFlowProviderWhisper
@testable import VoxFlowApp

final class ASRProviderRegistryTests: XCTestCase {
    private var defaults: UserDefaults!
    private var manager: ASRManager!
    private var registry: ASRProviderRegistry!

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

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "test.ASRProviderRegistry")!
        defaults.removePersistentDomain(forName: "test.ASRProviderRegistry")
        manager = ASRManager(defaults: defaults)
        registry = ASRProviderRegistry(asrManager: manager)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: "test.ASRProviderRegistry")
        super.tearDown()
    }

    func testBuiltInDescriptorsExposeCapabilitiesAndTags() throws {
        let apple = try XCTUnwrap(registry.descriptor(id: ASRProviderID.appleSpeech))
        let qwen = try XCTUnwrap(registry.descriptor(id: ASRProviderID.qwen3))

        XCTAssertEqual(apple.displayName, "系统自带")
        XCTAssertTrue(apple.capabilities.contains(.streaming))
        XCTAssertTrue(apple.capabilities.contains(.punctuation))
        XCTAssertTrue(qwen.capabilities.contains(.local))
        XCTAssertTrue(qwen.capabilities.contains(.multilingual))
        XCTAssertTrue(qwen.tags.contains("本地"))
        XCTAssertEqual(qwen.statusMessage, "尚未安装本地模型")
        XCTAssertEqual(
            qwen.privacySummary,
            "请先下载模型，或选择已有的模型文件夹。语音仅在本机处理，不会上传。"
        )
    }

    func testFilteringByCapabilityAndTag() {
        let localProviders = registry.descriptors(
            matching: ASRProviderFilter(requiredCapabilities: [.local], tags: ["本地"])
        )

        XCTAssertEqual(Set(localProviders.map(\.id)),
                       [ASRProviderID.funASR, ASRProviderID.whisper, ASRProviderID.qwen3,
                        ASRProviderID.senseVoice, ASRProviderID.paraformer,
                        ASRProviderID.nvidiaNemotron])
    }

    func testFunASRAndSenseVoiceExposeOnlyChineseEnglishBasicLanguageTargets() throws {
        let funASR = try XCTUnwrap(registry.descriptor(id: ASRProviderID.funASR))
        let senseVoice = try XCTUnwrap(registry.descriptor(id: ASRProviderID.senseVoice))

        for descriptor in [funASR, senseVoice] {
            XCTAssertTrue(descriptor.tags.contains("中文"))
            XCTAssertTrue(descriptor.tags.contains("English"))
            XCTAssertFalse(descriptor.tags.contains("日本語"))
            XCTAssertFalse(descriptor.tags.contains("日本语"))
            XCTAssertFalse(descriptor.tags.contains("粤语"))
            XCTAssertFalse(descriptor.tags.contains("한국어"))
            XCTAssertTrue(descriptor.privacySummary.contains("中文/English"))
        }
    }

    func testQwenProviderTagsUseProviderTargetChineseEnglishLanguages() throws {
        let qwen = try XCTUnwrap(registry.descriptor(id: ASRProviderID.qwen3))

        XCTAssertTrue(qwen.tags.contains("中文"))
        XCTAssertTrue(qwen.tags.contains("English"))
        XCTAssertFalse(qwen.tags.contains("多语言"))
    }

    func testNonStreamingProvidersExposeNonStreamingTag() throws {
        let descriptors = registry.descriptors()
        let nonStreaming = descriptors.filter { !$0.capabilities.contains(.streaming) }
        let streaming = descriptors.filter { $0.capabilities.contains(.streaming) }

        XCTAssertFalse(nonStreaming.isEmpty)
        for descriptor in nonStreaming {
            XCTAssertTrue(
                descriptor.tags.contains("非流式"),
                "\(descriptor.id) should be clearly marked as non-streaming."
            )
        }
        for descriptor in streaming {
            XCTAssertFalse(
                descriptor.tags.contains("非流式"),
                "\(descriptor.id) should not be marked as non-streaming."
            )
        }
    }

    func testParaformerAndNVIDIANemotronAreFormalProvidersButUnavailableUntilReady() throws {
        let paraformer = try XCTUnwrap(registry.descriptor(id: ASRProviderID.paraformer))
        let nvidia = try XCTUnwrap(registry.descriptor(id: ASRProviderID.nvidiaNemotron))

        XCTAssertEqual(paraformer.displayName, "Paraformer Large zh")
        XCTAssertEqual(nvidia.displayName, "NVIDIA Nemotron ASR 0.6B")
        XCTAssertTrue(paraformer.capabilities.contains(.streaming))
        XCTAssertTrue(nvidia.capabilities.contains(.streaming))
        XCTAssertFalse(paraformer.isAvailable)
        XCTAssertFalse(nvidia.isAvailable)
        XCTAssertEqual(paraformer.localModelAction, .download)
        XCTAssertEqual(nvidia.localModelAction, .download)
    }

    func testDefaultProviderFallsBackToAppleWhenQwenModelIsMissing() throws {
        manager.selectedEngineType = .qwen3

        let defaultProvider = try registry.defaultProvider()
        let qwenDescriptor = try XCTUnwrap(registry.descriptor(id: ASRProviderID.qwen3))
        let fallbackChain = registry.fallbackChain(startingAt: ASRProviderID.qwen3)

        XCTAssertTrue(qwenDescriptor.isDefault)
        XCTAssertEqual(defaultProvider.id, ASRProviderID.appleSpeech)
        XCTAssertEqual(fallbackChain.map(\.id), [ASRProviderID.appleSpeech])
    }

    func testDefaultProviderCanSelectAvailableQwenModel() throws {
        let modelURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceInputTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: modelURL, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: modelURL)
        }
        manager = ASRManager(
            defaults: defaults,
            modelInstallationRepository: makeInstallationRepository()
        )
        registry = ASRProviderRegistry(asrManager: manager)
        manager.markQwen3ModelReady(at: modelURL.path, size: .size0_6B)

        try registry.selectDefaultProvider(id: ASRProviderID.qwen3)

        let qwenDescriptor = try XCTUnwrap(registry.descriptor(id: ASRProviderID.qwen3))
        XCTAssertEqual(try registry.defaultProvider().id, ASRProviderID.qwen3)
        XCTAssertEqual(manager.selectedEngineType, .qwen3)
        XCTAssertEqual(qwenDescriptor.statusMessage, "本地模型已就绪")
        XCTAssertEqual(qwenDescriptor.privacySummary, "语音仅在本机处理，不会上传。")
    }

    func testDefaultProviderCanSelectAvailableFunASRModel() throws {
        let repository = makeInstallationRepository()
        manager = ASRManager(defaults: defaults, modelInstallationRepository: repository)
        registry = ASRProviderRegistry(asrManager: manager)
        let modelURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ASRProviderRegistryTests-\(UUID().uuidString)", isDirectory: true)
        try createLoadableFunASRModelDirectory(at: modelURL, variant: .int8)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: modelURL)
        }
        manager.markFunASRModelReady(at: modelURL.path, precision: .int8)

        try registry.selectDefaultProvider(id: ASRProviderID.funASR)

        let descriptor = try XCTUnwrap(registry.descriptor(id: ASRProviderID.funASR))
        XCTAssertEqual(try registry.defaultProvider().id, ASRProviderID.funASR)
        XCTAssertEqual(manager.selectedEngineType, .funASR)
        XCTAssertEqual(descriptor.statusMessage, "本地模型已就绪")
        XCTAssertEqual(descriptor.healthStatus, .ok)
        XCTAssertTrue(descriptor.tags.contains("中文"))
        XCTAssertTrue(descriptor.tags.contains("English"))
    }

    func testFunASRProviderCatalogTrustsLifecycleStateButSelectionStillVerifiesFiles() throws {
        let repository = makeInstallationRepository()
        manager = ASRManager(defaults: defaults, modelInstallationRepository: repository)
        registry = ASRProviderRegistry(asrManager: manager)
        let modelURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ASRProviderRegistryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: modelURL, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: modelURL)
        }
        manager.markFunASRModelReady(at: modelURL.path, precision: .int8)

        let descriptor = try XCTUnwrap(registry.descriptor(id: ASRProviderID.funASR))

        XCTAssertTrue(descriptor.isAvailable)
        XCTAssertEqual(descriptor.localModelAction, .delete)
        XCTAssertEqual(descriptor.healthStatus, .ok)
        XCTAssertThrowsError(try registry.selectDefaultProvider(id: ASRProviderID.funASR)) { error in
            guard case .providerUnavailable("FunASR Nano") = error as? ASRProviderRegistryError else {
                return XCTFail("Expected FunASR unavailable error, got \(error)")
            }
        }
    }

    func testDefaultProviderCanSelectAvailableSenseVoiceModel() throws {
        let repository = makeInstallationRepository()
        manager = ASRManager(defaults: defaults, modelInstallationRepository: repository)
        registry = ASRProviderRegistry(asrManager: manager)
        let modelURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ASRProviderRegistryTests-\(UUID().uuidString)", isDirectory: true)
        try createLoadableSenseVoiceModelDirectory(at: modelURL)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: modelURL)
        }
        manager.markSenseVoiceModelReady(at: modelURL.path)

        try registry.selectDefaultProvider(id: ASRProviderID.senseVoice)

        let descriptor = try XCTUnwrap(registry.descriptor(id: ASRProviderID.senseVoice))
        XCTAssertEqual(try registry.defaultProvider().id, ASRProviderID.senseVoice)
        XCTAssertEqual(manager.selectedEngineType, .senseVoice)
        XCTAssertEqual(descriptor.statusMessage, "本地模型已就绪")
        XCTAssertEqual(descriptor.healthStatus, .ok)
        XCTAssertTrue(descriptor.tags.contains("中文"))
        XCTAssertTrue(descriptor.tags.contains("English"))
    }

    func testSenseVoiceProviderIsUnavailableWhenOnlyFilesExistWithoutLifecycleState() throws {
        let modelURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ASRProviderRegistryTests-\(UUID().uuidString)", isDirectory: true)
        try createLoadableSenseVoiceModelDirectory(at: modelURL)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: modelURL)
        }

        let descriptor = try XCTUnwrap(registry.descriptor(id: ASRProviderID.senseVoice))

        XCTAssertFalse(descriptor.isAvailable)
        XCTAssertEqual(descriptor.localModelAction, .download)
        XCTAssertEqual(descriptor.healthStatus, .notInstalled)
        XCTAssertThrowsError(try registry.selectDefaultProvider(id: ASRProviderID.senseVoice)) { error in
            guard case .providerUnavailable("SenseVoice Small") = error as? ASRProviderRegistryError else {
                return XCTFail("Expected SenseVoice unavailable error, got \(error)")
            }
        }
    }

    func testQwenProviderIsUnavailableWhenOnlyLegacyLoadableDirectoryExists() throws {
        let modelURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceInputTests-\(UUID().uuidString)")
        try createLoadableQwen3ModelDirectory(at: modelURL)
        defer { try? FileManager.default.removeItem(at: modelURL) }
        manager.qwen3ModelPath = modelURL.path

        let qwenDescriptor = try XCTUnwrap(registry.descriptor(id: ASRProviderID.qwen3))

        XCTAssertFalse(qwenDescriptor.isAvailable)
        XCTAssertEqual(qwenDescriptor.statusMessage, "尚未安装本地模型")
        XCTAssertThrowsError(try registry.selectDefaultProvider(id: ASRProviderID.qwen3)) { error in
            guard case .providerUnavailable("Qwen3-ASR") = error as? ASRProviderRegistryError else {
                return XCTFail("Expected Qwen unavailable error, got \(error)")
            }
        }
    }

    func testQwenProviderShowsRepairWhenLifecycleStateIsCorrupt() throws {
        let repository = makeInstallationRepository()
        manager = ASRManager(defaults: defaults, modelInstallationRepository: repository)
        registry = ASRProviderRegistry(asrManager: manager)
        try saveQwenState(.corrupt(reason: "SHA 校验失败"), in: repository)

        let qwenDescriptor = try XCTUnwrap(registry.descriptor(id: ASRProviderID.qwen3))

        XCTAssertFalse(qwenDescriptor.isAvailable)
        XCTAssertEqual(qwenDescriptor.localModelAction, .repair)
        XCTAssertEqual(qwenDescriptor.statusMessage, "模型损坏，需要修复：SHA 校验失败")
        XCTAssertThrowsError(try registry.selectDefaultProvider(id: ASRProviderID.qwen3)) { error in
            guard case .providerUnavailable("Qwen3-ASR") = error as? ASRProviderRegistryError else {
                return XCTFail("Expected Qwen unavailable error, got \(error)")
            }
        }
    }

    func testCustomDescriptorCannotOverrideBuiltInQwenReadiness() throws {
        registry.register(
            ASRProviderDescriptor(
                id: ASRProviderID.qwen3,
                displayName: "Fake Ready Qwen",
                providerType: "qwen3",
                capabilities: [.streaming, .local],
                tags: ["mock"],
                isAvailable: true,
                isDefault: false,
                statusMessage: "Mock ready",
                privacySummary: "Mock provider should not be used.",
                modelSize: .size0_6B,
                engineType: .qwen3
            )
        )

        let qwenDescriptor = try XCTUnwrap(registry.descriptor(id: ASRProviderID.qwen3))

        XCTAssertEqual(qwenDescriptor.displayName, "Qwen3-ASR")
        XCTAssertFalse(qwenDescriptor.isAvailable)
        XCTAssertEqual(qwenDescriptor.healthStatus, .notInstalled)
        XCTAssertEqual(qwenDescriptor.statusMessage, "尚未安装本地模型")
        XCTAssertThrowsError(try registry.selectDefaultProvider(id: ASRProviderID.qwen3)) { error in
            guard case .providerUnavailable("Qwen3-ASR") = error as? ASRProviderRegistryError else {
                return XCTFail("Expected Qwen unavailable error, got \(error)")
            }
        }
    }

    func testQwen17ProviderAllowsDownloadActionWhileRuntimeIsProvisioning() throws {
        manager.qwen3ModelSize = .size1_7B

        let qwenDescriptor = try XCTUnwrap(registry.descriptor(id: ASRProviderID.qwen3))

        XCTAssertFalse(qwenDescriptor.isAvailable)
        XCTAssertEqual(qwenDescriptor.localModelAction, .download)
        XCTAssertEqual(qwenDescriptor.healthStatus, .notInstalled)
        XCTAssertEqual(qwenDescriptor.statusMessage, "尚未安装本地模型")
        XCTAssertThrowsError(try registry.selectDefaultProvider(id: ASRProviderID.qwen3)) { error in
            guard case .providerUnavailable("Qwen3-ASR") = error as? ASRProviderRegistryError else {
                return XCTFail("Expected Qwen unavailable error, got \(error)")
            }
        }
    }

    func testProviderCatalogDoesNotRunQwenRuntimePreflightDuringPresentation() throws {
        let source = try String(contentsOf: Self.repositoryRoot()
            .appendingPathComponent("Sources/VoxFlowApp/ASRBridges/ASRProviderRegistry.swift"))

        XCTAssertFalse(source.contains("ASRManager.isQwen3RuntimeSupported(size: size)"))
        XCTAssertFalse(source.contains("ASRManager.qwen3RuntimeUnsupportedMessage(for: size)"))
    }

    func testWhisperLargeV3ProviderOffersDownloadUntilModelStoreReady() throws {
        manager.whisperVariant = .largeV3

        let whisperDescriptor = try XCTUnwrap(registry.descriptor(id: ASRProviderID.whisper))

        XCTAssertFalse(whisperDescriptor.isAvailable)
        XCTAssertEqual(whisperDescriptor.localModelAction, .download)
        XCTAssertEqual(whisperDescriptor.healthStatus, .notInstalled)
        XCTAssertEqual(whisperDescriptor.statusMessage, "尚未安装本地模型")
        XCTAssertThrowsError(try registry.selectDefaultProvider(id: ASRProviderID.whisper)) { error in
            guard case .providerUnavailable("Whisper") = error as? ASRProviderRegistryError else {
                return XCTFail("Expected Whisper unavailable error, got \(error)")
            }
        }
    }

    func testDefaultProviderCanSelectAvailableWhisperLargeV3Model() throws {
        let repository = makeInstallationRepository()
        manager = ASRManager(defaults: defaults, modelInstallationRepository: repository)
        registry = ASRProviderRegistry(asrManager: manager)
        manager.whisperVariant = .largeV3
        let modelURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ASRProviderRegistryTests-\(UUID().uuidString)", isDirectory: true)
        try createLoadableWhisperModelDirectory(at: modelURL, variant: .largeV3)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: modelURL)
        }
        manager.markWhisperModelReady(at: modelURL.path, variant: .largeV3)

        try registry.selectDefaultProvider(id: ASRProviderID.whisper)

        let descriptor = try XCTUnwrap(registry.descriptor(id: ASRProviderID.whisper))
        XCTAssertEqual(try registry.defaultProvider().id, ASRProviderID.whisper)
        XCTAssertEqual(manager.selectedEngineType, .whisper)
        XCTAssertTrue(descriptor.isAvailable)
        XCTAssertEqual(descriptor.statusMessage, "本地模型已就绪")
        XCTAssertTrue(descriptor.tags.contains("Large V3"))
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

    private func makeInstallationRepository() -> FileModelInstallationStateRepository {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ASRProviderRegistryTests-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }
        return FileModelInstallationStateRepository(
            fileURL: root.appendingPathComponent("installation-states.json")
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
}
