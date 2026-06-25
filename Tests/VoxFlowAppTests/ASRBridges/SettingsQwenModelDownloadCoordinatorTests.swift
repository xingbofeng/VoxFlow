import XCTest
import VoxFlowModelStore
import VoxFlowProviderQwen3
@testable import VoxFlowApp

@MainActor
final class SettingsQwenModelDownloadCoordinatorTests: XCTestCase {
    func testDownloadRunsPrewarmCanaryBeforeReturningInstalledRoot() async throws {
        let manager = makeManager()
        let modelURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceInputTests-\(UUID().uuidString)")
        try createLoadableQwen3ModelDirectory(at: modelURL, size: .size0_6B)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: modelURL)
        }
        let readinessPreparer = CapturingQwen3ReadinessPreparer()
        let coordinator = SettingsQwenModelDownloadCoordinator(
            asrManager: manager,
            downloader: SettingsStubQwen3ModelDownloader(
                downloadedURL: modelURL,
                missingPaths: []
            ),
            readinessPreparer: readinessPreparer
        )

        let installedRoot = try await coordinator.downloadQwen3Model(size: .size0_6B) { _ in }

        XCTAssertEqual(installedRoot, modelURL)
        let preparedModels = await readinessPreparer.preparedModelsSnapshot()
        XCTAssertEqual(preparedModels.map(\.url), [modelURL])
        XCTAssertEqual(preparedModels.map(\.size), [.size0_6B])
        XCTAssertNil(manager.qwen3ModelPath)
        XCTAssertFalse(manager.isQwen3ModelAvailable)
    }

    func testDownloadDoesNotMarkModelReadyWhenPrewarmCanaryFails() async throws {
        let manager = makeManager()
        let modelURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceInputTests-\(UUID().uuidString)")
        try createLoadableQwen3ModelDirectory(at: modelURL, size: .size1_7B)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: modelURL)
        }
        let coordinator = SettingsQwenModelDownloadCoordinator(
            asrManager: manager,
            downloader: SettingsStubQwen3ModelDownloader(
                downloadedURL: modelURL,
                missingPaths: []
            ),
            readinessPreparer: CapturingQwen3ReadinessPreparer(
                result: .failure(Qwen3ModelReadinessTestError.canaryFailed)
            )
        )

        do {
            _ = try await coordinator.downloadQwen3Model(size: .size0_6B) { _ in }
            XCTFail("Expected prewarm/canary failure.")
        } catch {
            XCTAssertEqual(error as? Qwen3ModelReadinessTestError, .canaryFailed)
        }

        XCTAssertNil(manager.qwen3ModelPath)
        XCTAssertFalse(manager.isQwen3ModelAvailable)
    }

    func testQwen17DownloadPreparesModelWithoutExternalRuntimeProvisioning() async throws {
        let manager = makeManager()
        let modelURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceInputTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: modelURL, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: modelURL)
        }
        let readinessPreparer = CapturingQwen3ReadinessPreparer()
        let coordinator = SettingsQwenModelDownloadCoordinator(
            asrManager: manager,
            downloader: SettingsStubQwen3ModelDownloader(
                downloadedURL: modelURL,
                missingPaths: []
            ),
            readinessPreparer: readinessPreparer
        )

        let installedRoot = try await coordinator.downloadQwen3Model(size: .size1_7B) { _ in }

        XCTAssertEqual(installedRoot, modelURL)
        let preparedModels = await readinessPreparer.preparedModelsSnapshot()
        XCTAssertEqual(preparedModels.map(\.size), [.size1_7B])
        XCTAssertEqual(manager.qwen3ModelSize, .size0_6B)
        XCTAssertNil(manager.qwen3ModelPath)
    }

    private func makeManager() -> ASRManager {
        let suiteName = "test.SettingsQwenModelDownloadCoordinator.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let stateRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("SettingsQwenModelDownloadCoordinatorTests-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: stateRoot)
        }
        return ASRManager(
            defaults: defaults,
            modelInstallationRepository: FileModelInstallationStateRepository(
                fileURL: stateRoot.appendingPathComponent("installation-states.json")
            ),
            qwen3RuntimePreflight: { _ in .supported }
        )
    }

    private func createLoadableQwen3ModelDirectory(
        at modelURL: URL,
        size: ASRManager.ModelSize
    ) throws {
        let manifest = Qwen3ModelManifest.manifest(for: size)
        for relativePath in manifest.requiredLocalPaths {
            let fileURL = modelURL.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            XCTAssertTrue(FileManager.default.createFile(atPath: fileURL.path, contents: Data()))
        }
    }
}

private struct SettingsStubQwen3ModelDownloader: Qwen3ModelDownloading {
    let downloadedURL: URL
    let missingPaths: [String]

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
        missingPaths
    }
}

private enum Qwen3ModelReadinessTestError: Error, Equatable {
    case canaryFailed
}

private actor CapturingQwen3ReadinessPreparer: Qwen3ModelReadinessPreparing {
    private let result: Result<Void, Error>
    private(set) var preparedModels: [(url: URL, size: ASRManager.ModelSize)] = []

    init(result: Result<Void, Error> = .success(())) {
        self.result = result
    }

    func prepare(modelURL: URL, size: ASRManager.ModelSize) async throws {
        preparedModels.append((modelURL, size))
        try result.get()
    }

    func preparedModelsSnapshot() -> [(url: URL, size: ASRManager.ModelSize)] {
        preparedModels
    }
}
