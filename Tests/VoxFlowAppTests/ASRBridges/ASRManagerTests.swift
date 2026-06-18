import XCTest
import VoxFlowModelStore
import VoxFlowProviderFunASR
import VoxFlowProviderQwen3
import VoxFlowProviderSenseVoice
import VoxFlowProviderWhisper
@testable import VoxFlowApp

final class ASRManagerTests: XCTestCase {
    var manager: ASRManager!
    var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "test.ASRManager")!
        defaults.removePersistentDomain(forName: "test.ASRManager")
        manager = ASRManager(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: "test.ASRManager")
        super.tearDown()
    }

    func testDefaultEngineIsApple() {
        XCTAssertEqual(manager.selectedEngineType, .apple)
    }

    func testSetAndGetSelectedEngine() {
        manager.selectedEngineType = .qwen3
        XCTAssertEqual(manager.selectedEngineType, .qwen3)
    }

    func testEffectiveSelectedEngineFallsBackToAppleWhenQwen3ModelIsMissing() {
        manager.selectedEngineType = .qwen3
        XCTAssertEqual(manager.effectiveSelectedEngineType, .apple)
    }

    func testDefaultModelSizeIs0_6B() {
        XCTAssertEqual(manager.qwen3ModelSize, .size0_6B)
    }

    func testQwen3ModelSizesExposeBothReleasedVariants() {
        XCTAssertEqual(ASRManager.ModelSize.allCases, [.size0_6B, .size1_7B])
    }

    func testLocalProviderConfigurationDefaultsAndPersistence() {
        XCTAssertEqual(manager.funASRPrecision, .int8)
        XCTAssertEqual(manager.whisperVariant, .turbo)

        manager.funASRPrecision = .fp32
        manager.whisperVariant = .largeV3

        let reloaded = ASRManager(defaults: defaults)
        XCTAssertEqual(reloaded.funASRPrecision, .fp32)
        XCTAssertEqual(reloaded.whisperVariant, .largeV3)
    }

    func testParaformerEngineSelectionFallsBackToAppleUntilModelIsReady() {
        defaults.set("Paraformer", forKey: "ASRManager.selectedEngineType")

        XCTAssertEqual(manager.selectedEngineType, .paraformer)
        XCTAssertEqual(manager.effectiveSelectedEngineType, .apple)
        XCTAssertFalse(manager.canSelectEngine(.paraformer))
    }

    func testDefaultModelPathIsNil() {
        XCTAssertNil(manager.qwen3ModelPath)
    }

    func testSetAndGetModelPath() {
        let path = "/path/to/model"
        manager.qwen3ModelPath = path
        XCTAssertEqual(manager.qwen3ModelPath, path)
    }

    func testQwen3ModelIsUnavailableWithoutExistingPath() {
        manager.qwen3ModelPath = "/path/to/missing/model.mlmodelc"
        XCTAssertFalse(manager.isQwen3ModelAvailable)
        XCTAssertFalse(manager.canSelectEngine(.qwen3))
        XCTAssertTrue(manager.canSelectEngine(.apple))
    }

    func testQwen3LoadablePathIsNotDiscoverableWithoutLifecycleReadyState() throws {
        let modelURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoxFlowTests-\(UUID().uuidString)")
        try createLoadableQwen3ModelDirectory(at: modelURL)
        defer { try? FileManager.default.removeItem(at: modelURL) }

        manager.qwen3ModelPath = modelURL.path

        XCTAssertNil(manager.qwen3ModelPath(for: .size0_6B))
        XCTAssertFalse(manager.isQwen3ModelAvailable)
        XCTAssertFalse(manager.canSelectEngine(.qwen3))
        XCTAssertFalse(manager.selectEngine(.qwen3))
        XCTAssertEqual(manager.effectiveSelectedEngineType, .apple)
    }

    func testQwen3ModelStoreReadyStateIsRecordedInInstallationRepository() throws {
        let stateFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceInputTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("installation-states.json")
        let repository = FileModelInstallationStateRepository(fileURL: stateFileURL)
        manager = ASRManager(defaults: defaults, modelInstallationRepository: repository)
        let modelURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceInputTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: modelURL, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: stateFileURL.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: modelURL)
        }

        manager.markQwen3ModelReady(at: modelURL.path, size: .size0_6B)

        let metadata = try Qwen3ModelStoreMetadata.metadata(for: Qwen3ModelManifest.manifest(for: .size0_6B))
        let key = ModelInstallKey(modelID: metadata.modelID, version: metadata.version)
        XCTAssertEqual(
            try repository.state(for: key),
            .ready(ModelInstallation(modelID: metadata.modelID, version: metadata.version, installedRoot: modelURL))
        )
        XCTAssertEqual(manager.qwen3ModelPath, modelURL.path)
        XCTAssertTrue(manager.isQwen3ModelAvailable)
    }

    func testQwen17ReadyStateIsBlockedByRuntimePreflightUntilMLXWorkerExists() throws {
        let stateFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceInputTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("installation-states.json")
        let repository = FileModelInstallationStateRepository(fileURL: stateFileURL)
        manager = ASRManager(defaults: defaults, modelInstallationRepository: repository)
        manager.qwen3ModelSize = .size1_7B
        let modelURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceInputTests-\(UUID().uuidString)", isDirectory: true)
        try createLoadableQwen17MLXModelDirectory(at: modelURL)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: stateFileURL.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: modelURL)
        }

        let metadata = try Qwen3ModelStoreMetadata.metadata(for: Qwen3ModelManifest.manifest(for: .size1_7B))
        let installation = ModelInstallation(
            modelID: metadata.modelID,
            version: metadata.version,
            installedRoot: modelURL
        )
        try repository.save(.ready(installation), for: ModelInstallKey(modelID: metadata.modelID, version: metadata.version))

        XCTAssertEqual(
            manager.qwen3ModelInstallationState(for: .size1_7B),
            .runtimeUnsupported(reason: "Qwen3-ASR 1.7B 需要 MLX 本地 worker：voxflow-qwen3-mlx-worker。")
        )
        XCTAssertFalse(manager.isQwen3ModelAvailable)
        XCTAssertFalse(manager.canSelectEngine(.qwen3))
        XCTAssertFalse(manager.selectEngine(.qwen3))
        XCTAssertEqual(manager.effectiveSelectedEngineType, .apple)
    }

    func testFunASRModelStoreReadyStateIsRecordedInInstallationRepository() throws {
        let stateFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceInputTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("installation-states.json")
        let repository = FileModelInstallationStateRepository(fileURL: stateFileURL)
        manager = ASRManager(defaults: defaults, modelInstallationRepository: repository)
        let modelURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceInputTests-\(UUID().uuidString)", isDirectory: true)
        try createLoadableFunASRModelDirectory(at: modelURL, variant: .int8)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: stateFileURL.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: modelURL)
        }

        manager.markFunASRModelReady(at: modelURL.path, precision: .int8)

        let key = ModelInstallKey(
            modelID: ModelID(rawValue: "funasr-int8"),
            version: FunASRModelVariant.int8.directoryName
        )
        XCTAssertEqual(
            try repository.state(for: key),
            .ready(ModelInstallation(modelID: key.modelID, version: key.version, installedRoot: modelURL))
        )
        XCTAssertTrue(manager.isFunASRModelAvailable)
        XCTAssertTrue(manager.canSelectEngine(.funASR))
    }

    func testFunASRReadyStateWithoutCompleteFilesDoesNotMakeModelAvailable() throws {
        let stateFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceInputTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("installation-states.json")
        let repository = FileModelInstallationStateRepository(fileURL: stateFileURL)
        manager = ASRManager(defaults: defaults, modelInstallationRepository: repository)
        let modelURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceInputTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: modelURL, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: stateFileURL.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: modelURL)
        }

        manager.markFunASRModelReady(at: modelURL.path, precision: .int8)

        XCTAssertFalse(manager.isFunASRModelAvailable)
        XCTAssertFalse(manager.canSelectEngine(.funASR))
    }

    func testParaformerModelStoreReadyStateMakesModelSelectable() throws {
        let stateFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceInputTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("installation-states.json")
        let repository = FileModelInstallationStateRepository(fileURL: stateFileURL)
        manager = ASRManager(defaults: defaults, modelInstallationRepository: repository)
        let modelURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceInputTests-\(UUID().uuidString)", isDirectory: true)
        try createLoadableParaformerModelDirectory(at: modelURL)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: stateFileURL.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: modelURL)
        }

        manager.markParaformerModelReady(at: modelURL.path)

        let key = ModelInstallKey(
            modelID: ModelID(rawValue: "paraformer-large-zh-coreml-int8"),
            version: "paraformer-large-zh-coreml-int8"
        )
        XCTAssertEqual(
            try repository.state(for: key),
            .ready(ModelInstallation(modelID: key.modelID, version: key.version, installedRoot: modelURL))
        )
        XCTAssertTrue(manager.isParaformerModelAvailable)
        XCTAssertTrue(manager.canSelectEngine(.paraformer))
    }

    func testParaformerReadyStateWithoutCompleteFilesDoesNotMakeModelAvailable() throws {
        let stateFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceInputTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("installation-states.json")
        let repository = FileModelInstallationStateRepository(fileURL: stateFileURL)
        manager = ASRManager(defaults: defaults, modelInstallationRepository: repository)
        let modelURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceInputTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: modelURL, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: stateFileURL.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: modelURL)
        }

        manager.markParaformerModelReady(at: modelURL.path)

        XCTAssertFalse(manager.isParaformerModelAvailable)
        XCTAssertFalse(manager.canSelectEngine(.paraformer))
    }

    func testSenseVoiceModelStoreReadyStateIsRecordedInInstallationRepository() throws {
        let stateFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceInputTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("installation-states.json")
        let repository = FileModelInstallationStateRepository(fileURL: stateFileURL)
        manager = ASRManager(defaults: defaults, modelInstallationRepository: repository)
        let modelURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceInputTests-\(UUID().uuidString)", isDirectory: true)
        try createLoadableSenseVoiceModelDirectory(at: modelURL)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: stateFileURL.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: modelURL)
        }

        manager.markSenseVoiceModelReady(at: modelURL.path)

        let key = ModelInstallKey(
            modelID: ModelID(rawValue: SenseVoiceModel.modelID),
            version: SenseVoiceModel.version
        )
        XCTAssertEqual(
            try repository.state(for: key),
            .ready(ModelInstallation(modelID: key.modelID, version: key.version, installedRoot: modelURL))
        )
        XCTAssertTrue(manager.isSenseVoiceModelAvailable)
        XCTAssertTrue(manager.canSelectEngine(.senseVoice))
    }

    func testSenseVoiceReadyStateWithoutCompleteFilesDoesNotMakeModelAvailable() throws {
        let stateFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceInputTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("installation-states.json")
        let repository = FileModelInstallationStateRepository(fileURL: stateFileURL)
        manager = ASRManager(defaults: defaults, modelInstallationRepository: repository)
        let modelURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceInputTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: modelURL, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: stateFileURL.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: modelURL)
        }

        manager.markSenseVoiceModelReady(at: modelURL.path)

        XCTAssertFalse(manager.isSenseVoiceModelAvailable)
        XCTAssertFalse(manager.canSelectEngine(.senseVoice))
    }

    func testSelectingQwen3WithoutModelFallsBackToApple() {
        XCTAssertFalse(manager.selectEngine(.qwen3))
        XCTAssertEqual(manager.selectedEngineType, .apple)
    }

    func testQwen3DownloadURLsUseOfficialHuggingFaceModels() {
        XCTAssertEqual(
            ASRManager.downloadURL(for: .size0_6B).absoluteString,
            "https://huggingface.co/Qwen/Qwen3-ASR-0.6B"
        )
        XCTAssertEqual(
            ASRManager.downloadURL(for: .size1_7B).absoluteString,
            "https://huggingface.co/Qwen/Qwen3-ASR-1.7B"
        )
    }

    func testQwen3CoreMLManifestUsesDirectDownloadURLs() {
        let manifest = Qwen3ModelManifest.manifest(for: .size0_6B)

        XCTAssertEqual(manifest.repository, "FluidInference/qwen3-asr-0.6b-coreml")
        let embeddingsFile = Qwen3ModelManifest.File(
            remotePath: "int8/qwen3_asr_embeddings.bin",
            localPath: "qwen3_asr_embeddings.bin"
        )
        XCTAssertTrue(manifest.files.contains(embeddingsFile))
        XCTAssertEqual(
            manifest.remoteURL(for: embeddingsFile).absoluteString,
            "https://huggingface.co/FluidInference/qwen3-asr-0.6b-coreml/resolve/main/int8/qwen3_asr_embeddings.bin"
        )
    }

    func testQwen3SupportedModelExistsRejectsEmbeddingWithWrongShape() throws {
        let modelURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceInputTests-\(UUID().uuidString)")
        try createLoadableQwen3ModelDirectory(at: modelURL)
        defer { try? FileManager.default.removeItem(at: modelURL) }

        let embeddingURL = modelURL.appendingPathComponent("qwen3_asr_embeddings.bin")
        try makeEmbeddingFile(at: embeddingURL, hiddenSize: 2048)

        XCTAssertFalse(Qwen3ModelManifest.supportedModelExists(at: modelURL))
        manager.qwen3ModelPath = modelURL.path
        XCTAssertFalse(manager.isQwen3ModelAvailable)
    }

    func testMakeAppleEngineReturnsSpeechRecognizer() {
        let engine = manager.makeEngine(type: .apple)
        XCTAssertTrue(engine is SpeechRecognizer)
    }

    func testMakeQwen3EngineReturnsProviderBackedAdapterWhenModelStoreReady() throws {
        let stateFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceInputTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("installation-states.json")
        let repository = FileModelInstallationStateRepository(fileURL: stateFileURL)
        manager = ASRManager(defaults: defaults, modelInstallationRepository: repository)
        let modelURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceInputTests-\(UUID().uuidString)")
        try createLoadableQwen3ModelDirectory(at: modelURL)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: stateFileURL.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: modelURL)
        }

        manager.markQwen3ModelReady(at: modelURL.path, size: .size0_6B)
        let engine = manager.makeEngine(type: .qwen3)
        XCTAssertTrue(engine is ASRCoreBackedASREngine, "Expected ASRCoreBackedASREngine but got \(type(of: engine))")
        XCTAssertTrue(engine.isAvailable)
    }

    func testMakeQwen3EngineIsUnavailableUntilModelStoreLifecycleIsReady() {
        manager.qwen3ModelPath = "/tmp/qwen3-loadable-looking-but-not-ready"

        let engine = manager.makeEngine(type: .qwen3)

        XCTAssertTrue(engine is ASRCoreBackedASREngine, "Expected ASRCoreBackedASREngine but got \(type(of: engine))")
        XCTAssertFalse(engine.isAvailable)
    }

    func testMakeSenseVoiceEngineReturnsProviderBackedAdapter() {
        let engine = manager.makeEngine(type: .senseVoice)
        XCTAssertTrue(engine is ASRCoreBackedASREngine, "Expected ASRCoreBackedASREngine but got \(type(of: engine))")
        XCTAssertFalse(engine.isAvailable)
    }

    func testMakeFunASREngineReturnsProviderBackedAdapter() {
        let engine = manager.makeEngine(type: .funASR)
        XCTAssertTrue(engine is ASRCoreBackedASREngine, "Expected ASRCoreBackedASREngine but got \(type(of: engine))")
        XCTAssertFalse(engine.isAvailable)
    }

    func testMakeParaformerEngineReturnsProviderBackedAdapter() {
        let engine = manager.makeEngine(type: .paraformer)
        XCTAssertTrue(engine is ASRCoreBackedASREngine, "Expected ASRCoreBackedASREngine but got \(type(of: engine))")
        XCTAssertFalse(engine.isAvailable)
    }

    func testMakeWhisperEngineReturnsProviderBackedAdapter() {
        let engine = manager.makeEngine(type: .whisper)
        XCTAssertTrue(engine is ASRCoreBackedASREngine, "Expected ASRCoreBackedASREngine but got \(type(of: engine))")
        XCTAssertFalse(engine.isAvailable)
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
        try makeEmbeddingFile(
            at: modelURL.appendingPathComponent("qwen3_asr_embeddings.bin"),
            hiddenSize: 1024
        )
    }

    private func createLoadableQwen17MLXModelDirectory(at modelURL: URL) throws {
        let manifest = Qwen3ModelManifest.manifest(for: .size1_7B)
        for relativePath in manifest.requiredLocalPaths {
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

    private func makeEmbeddingFile(at url: URL, hiddenSize: UInt32) throws {
        var header = Data()
        var vocabSize = UInt32(151_936).littleEndian
        var hiddenSize = hiddenSize.littleEndian
        withUnsafeBytes(of: &vocabSize) { header.append(contentsOf: $0) }
        withUnsafeBytes(of: &hiddenSize) { header.append(contentsOf: $0) }
        try header.write(to: url)
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: 8 + UInt64(151_936) * UInt64(hiddenSize) * 2)
        try handle.close()
    }
}
