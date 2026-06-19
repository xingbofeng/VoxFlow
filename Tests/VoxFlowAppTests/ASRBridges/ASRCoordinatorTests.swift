import XCTest
import VoxFlowModelStore
import VoxFlowProviderQwen3
@testable import VoxFlowApp

@MainActor
final class ASRCoordinatorTests: XCTestCase {
    func testFactoryConformanceUsesSwift61CompatibleIsolationSyntax() throws {
        let sourceURL = repositoryRoot()
            .appendingPathComponent("Sources/VoxFlowApp/ASRBridges/ASRCoordinator.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("final class ASRCoordinator: @preconcurrency ASREngineFactory"))
        XCTAssertFalse(source.contains("final class ASRCoordinator: @MainActor ASREngineFactory"))
    }

    func testCoordinatorOwnsMenuVariantSelectionState() {
        let suiteName = "test.ASRCoordinator.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let manager = ASRManager(defaults: defaults, qwen3RuntimePreflight: { _ in .supported })
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

    func testCoordinatorReportsFallbackNoticeWhenSelectedEngineIsUnavailable() {
        let suiteName = "test.ASRCoordinator.fallbackNotice.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let manager = ASRManager(defaults: defaults)
        manager.selectedEngineType = .funASR
        let coordinator = ASRCoordinator(manager: manager)

        let notice = coordinator.selectionFallbackNotice

        XCTAssertEqual(notice?.selectedEngineType, .funASR)
        XCTAssertEqual(notice?.effectiveEngineType, .apple)
        XCTAssertEqual(coordinator.dictationConfiguration(for: .english).engineType, .apple)
    }

    func testMenuSelectionUsesEffectiveProviderWhenPersistedProviderIsUnavailable() {
        let suiteName = "test.ASRCoordinator.effectiveMenuSelection.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let manager = ASRManager(defaults: defaults)
        manager.selectedEngineType = .funASR
        manager.funASRPrecision = .int8
        let coordinator = ASRCoordinator(manager: manager)

        let apple = ASRMenuModel(engineType: .apple, title: "系统自带")
        let funASR = ASRMenuModel(engineType: .funASR, funASRPrecision: .int8, title: "FunASR INT8")

        XCTAssertTrue(coordinator.isMenuOptionSelected(apple))
        XCTAssertFalse(coordinator.isMenuOptionSelected(funASR))
        XCTAssertEqual(manager.selectedEngineType, .funASR)
        XCTAssertEqual(coordinator.dictationConfiguration(for: .english).engineType, .apple)
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
            ),
            qwen3RuntimePreflight: { _ in .supported }
        )
        manager.markQwen3ModelReady(at: modelURL.path, size: .size0_6B)
        let coordinator = ASRCoordinator(manager: manager)
        XCTAssertTrue(manager.selectEngine(.qwen3))

        let configuration = coordinator.dictationConfiguration(for: .english)

        XCTAssertEqual(configuration.engineType, .qwen3)
        XCTAssertEqual(configuration.asrProviderID, ASRProviderID.qwen3)
        XCTAssertEqual(configuration.modelID, "qwen3-asr-0.6b-mlx-4bit")
        XCTAssertEqual(configuration.modelVersion, "bc441bd1e4295c1f42d9879f056049a925b6e013")
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
            ),
            qwen3RuntimePreflight: { _ in .supported }
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
        XCTAssertTrue(ASRCoordinator.requiresFinalRecognitionIndicator(for: .nvidiaNemotron))
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

    private func repositoryRoot() -> URL {
        var directory = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 {
            directory.deleteLastPathComponent()
        }
        return directory
    }
}
