import XCTest
import VoxFlowModelStore
import VoxFlowProviderQwen3
@testable import VoxFlowApp

final class ASRCoordinatorTests: XCTestCase {
    func testCoordinatorOwnsMenuVariantSelectionState() {
        let suiteName = "test.ASRCoordinator.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let manager = ASRManager(defaults: defaults)
        let coordinator = ASRCoordinator(
            manager: manager,
            qwenAvailableOnDisk: { $0 == .size0_6B },
            funASRAvailable: { $0 == .fp32 },
            whisperAvailable: { $0 == .turbo }
        )
        let qwen06 = ASRMenuModel(engineType: .qwen3, modelSize: .size0_6B, title: "Qwen 0.6B")
        let qwen17 = ASRMenuModel(engineType: .qwen3, modelSize: .size1_7B, title: "Qwen 1.7B")

        XCTAssertTrue(coordinator.isMenuOptionEnabled(qwen06))
        XCTAssertFalse(coordinator.isMenuOptionEnabled(qwen17))

        XCTAssertTrue(coordinator.selectMenuOption(qwen06))
        XCTAssertEqual(manager.qwen3ModelSize, .size0_6B)
        XCTAssertTrue(coordinator.isMenuOptionSelected(qwen06))

        XCTAssertFalse(coordinator.selectMenuOption(qwen17))
        XCTAssertEqual(manager.qwen3ModelSize, .size0_6B)
    }

    func testCoordinatorBuildsDictationConfigurationFromEffectiveEngineAndLanguage() {
        let suiteName = "test.ASRCoordinator.configuration.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let manager = ASRManager(defaults: defaults)
        manager.selectedEngineType = .qwen3
        let coordinator = ASRCoordinator(manager: manager)

        let configuration = coordinator.dictationConfiguration(for: .english)

        XCTAssertEqual(configuration.engineType, .apple)
        XCTAssertEqual(configuration.locale.identifier, "en-US")
        XCTAssertEqual(configuration.languageIdentifier, "en-US")
        XCTAssertEqual(configuration.asrProviderID, ASREngineType.apple.providerID)
    }

    func testCoordinatorBuildsQwenDictationConfigurationWithModelMetadata() throws {
        let suiteName = "test.ASRCoordinator.qwenMetadata.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let modelURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ASRCoordinatorTests-\(UUID().uuidString)")
        try createLoadableQwen3ModelDirectory(at: modelURL)
        defer { try? FileManager.default.removeItem(at: modelURL) }
        let stateRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("ASRCoordinatorTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: stateRoot) }
        let manager = ASRManager(
            defaults: defaults,
            modelInstallationRepository: FileModelInstallationStateRepository(
                fileURL: stateRoot.appendingPathComponent("installation-states.json")
            )
        )
        manager.markQwen3ModelReady(at: modelURL.path, size: .size0_6B)
        let coordinator = ASRCoordinator(manager: manager)
        XCTAssertTrue(manager.selectEngine(.qwen3))

        let configuration = coordinator.dictationConfiguration(for: .english)

        XCTAssertEqual(configuration.engineType, .qwen3)
        XCTAssertEqual(configuration.asrProviderID, ASRProviderID.qwen3)
        XCTAssertEqual(configuration.modelID, "qwen3-asr-0.6b-coreml-int8")
        XCTAssertEqual(configuration.modelVersion, "c081689ec58bcf29c2ef7c474ef78a164bda672b")
        XCTAssertEqual(configuration.languageIdentifier, "en-US")
    }

    func testCoordinatorShowsQwenWaitingIndicatorOnlyForDictationQwen() throws {
        let suiteName = "test.ASRCoordinator.waiting.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let modelURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ASRCoordinatorTests-\(UUID().uuidString)")
        try createLoadableQwen3ModelDirectory(at: modelURL)
        defer { try? FileManager.default.removeItem(at: modelURL) }
        let stateRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("ASRCoordinatorTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: stateRoot) }
        let manager = ASRManager(
            defaults: defaults,
            modelInstallationRepository: FileModelInstallationStateRepository(
                fileURL: stateRoot.appendingPathComponent("installation-states.json")
            )
        )
        manager.markQwen3ModelReady(at: modelURL.path, size: .size0_6B)
        let coordinator = ASRCoordinator(
            manager: manager,
            qwenAvailableOnDisk: { _ in true },
            funASRAvailable: { _ in false },
            whisperAvailable: { _ in false }
        )
        let qwen06 = ASRMenuModel(engineType: .qwen3, modelSize: .size0_6B, title: "Qwen 0.6B")
        XCTAssertTrue(coordinator.selectMenuOption(qwen06))

        XCTAssertTrue(coordinator.shouldShowWaitingIndicator(activeVoiceAction: .dictation))
        XCTAssertFalse(coordinator.shouldShowWaitingIndicator(activeVoiceAction: .agentCompose))
    }

    func testFinalizingLocalEnginesRequireRecognitionIndicator() {
        XCTAssertFalse(ASRCoordinator.requiresFinalRecognitionIndicator(for: .apple))
        XCTAssertTrue(ASRCoordinator.requiresFinalRecognitionIndicator(for: .qwen3))
        XCTAssertTrue(ASRCoordinator.requiresFinalRecognitionIndicator(for: .whisper))
        XCTAssertTrue(ASRCoordinator.requiresFinalRecognitionIndicator(for: .senseVoice))
        XCTAssertTrue(ASRCoordinator.requiresFinalRecognitionIndicator(for: .funASR))
        XCTAssertTrue(ASRCoordinator.requiresFinalRecognitionIndicator(for: .paraformer))
        XCTAssertFalse(ASRCoordinator.requiresFinalRecognitionIndicator(for: .nvidiaNemotron))
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
