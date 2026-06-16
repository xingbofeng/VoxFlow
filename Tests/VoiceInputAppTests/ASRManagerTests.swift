import XCTest
@testable import VoiceInputApp

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
        XCTAssertEqual(manager.paraformerLanguage, .chinese)

        manager.funASRPrecision = .fp32
        manager.whisperVariant = .largeV3
        manager.paraformerLanguage = .english

        let reloaded = ASRManager(defaults: defaults)
        XCTAssertEqual(reloaded.funASRPrecision, .fp32)
        XCTAssertEqual(reloaded.whisperVariant, .largeV3)
        XCTAssertEqual(reloaded.paraformerLanguage, .english)
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

    func testQwen3ModelIsAvailableWhenPathExists() throws {
        let modelURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceInputTests-\(UUID().uuidString)")
        try createLoadableQwen3ModelDirectory(at: modelURL)
        defer { try? FileManager.default.removeItem(at: modelURL) }

        manager.qwen3ModelPath = modelURL.path

        XCTAssertTrue(manager.isQwen3ModelAvailable)
        XCTAssertTrue(manager.canSelectEngine(.qwen3))
        XCTAssertTrue(manager.selectEngine(.qwen3))
        XCTAssertEqual(manager.effectiveSelectedEngineType, .qwen3)
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

    func testMakeQwen3EngineReturnsQwen3Engine() throws {
        let modelURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceInputTests-\(UUID().uuidString)")
        try createLoadableQwen3ModelDirectory(at: modelURL)
        defer { try? FileManager.default.removeItem(at: modelURL) }

        manager.qwen3ModelPath = modelURL.path
        let engine = manager.makeEngine(type: .qwen3)
        XCTAssertTrue(engine is Qwen3ASREngine, "Expected Qwen3ASREngine but got \(type(of: engine))")
        XCTAssertTrue(engine.isAvailable)
    }

    func testMakeParaformerEngineReturnsRealLocalEngine() {
        XCTAssertTrue(manager.makeEngine(type: .paraformer) is SherpaBatchASREngine)
    }

    func testMakeSenseVoiceEngineReturnsRealLocalEngine() {
        XCTAssertTrue(manager.makeEngine(type: .senseVoice) is FluidAudioBatchASREngine)
    }

    func testMakeFunASREngineReturnsSherpaEngine() {
        XCTAssertTrue(manager.makeEngine(type: .funASR) is SherpaBatchASREngine)
    }

    func testMakeWhisperEngineReturnsWhisperKitEngine() {
        XCTAssertTrue(manager.makeEngine(type: .whisper) is WhisperKitBatchASREngine)
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
