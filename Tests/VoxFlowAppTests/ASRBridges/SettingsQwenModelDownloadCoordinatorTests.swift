import XCTest
import VoxFlowModelStore
import VoxFlowProviderQwen3
@testable import VoxFlowApp

@MainActor
final class SettingsQwenModelDownloadCoordinatorTests: XCTestCase {
    func testDownloadRunsPrewarmCanaryBeforeMarkingModelReady() async throws {
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

        let installedRoot = try await coordinator.downloadQwen3Model(size: .size0_6B) { _ in }

        XCTAssertEqual(installedRoot, modelURL)
        let preparedModels = await readinessPreparer.preparedModelsSnapshot()
        XCTAssertEqual(preparedModels.map(\.url), [modelURL])
        XCTAssertEqual(preparedModels.map(\.size), [.size0_6B])
        XCTAssertEqual(manager.qwen3ModelPath, modelURL.path)
        XCTAssertTrue(manager.isQwen3ModelAvailable)
    }

    func testDownloadDoesNotMarkModelReadyWhenPrewarmCanaryFails() async throws {
        let manager = makeManager()
        let modelURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceInputTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: modelURL, withIntermediateDirectories: true)
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

    func testQwen17DownloadProvisionsRuntimeBeforeDownloadingAndPreparingModel() async throws {
        let manager = makeManager()
        let modelURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceInputTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: modelURL, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: modelURL)
        }
        let runtimeProvisioner = CapturingQwen3RuntimeProvisioner()
        let readinessPreparer = CapturingQwen3ReadinessPreparer()
        let coordinator = SettingsQwenModelDownloadCoordinator(
            asrManager: manager,
            downloader: SettingsStubQwen3ModelDownloader(
                downloadedURL: modelURL,
                missingPaths: []
            ),
            readinessPreparer: readinessPreparer,
            runtimeProvisioner: runtimeProvisioner
        )

        let installedRoot = try await coordinator.downloadQwen3Model(size: .size1_7B) { _ in }

        XCTAssertEqual(installedRoot, modelURL)
        let prepareCallCount = await runtimeProvisioner.prepareCallCount
        XCTAssertEqual(prepareCallCount, 1)
        let preparedModels = await readinessPreparer.preparedModelsSnapshot()
        XCTAssertEqual(preparedModels.map(\.size), [.size1_7B])
        XCTAssertEqual(manager.qwen3ModelPath, modelURL.path)
    }

    func testDownloadRejectsQwen17WhenRuntimeProvisioningFailsBeforeDownloaderOrReadiness() async throws {
        let manager = makeManager()
        let readinessPreparer = CapturingQwen3ReadinessPreparer()
        let coordinator = SettingsQwenModelDownloadCoordinator(
            asrManager: manager,
            downloader: SettingsFailingQwen3ModelDownloader(),
            readinessPreparer: readinessPreparer,
            runtimeProvisioner: CapturingQwen3RuntimeProvisioner(
                result: .failure(Qwen3ModelReadinessTestError.runtimeProvisionFailed)
            )
        )

        do {
            _ = try await coordinator.downloadQwen3Model(size: .size1_7B) { _ in }
            XCTFail("Expected Qwen 1.7B runtime provisioning failure.")
        } catch {
            XCTAssertEqual(error as? Qwen3ModelReadinessTestError, .runtimeProvisionFailed)
        }

        XCTAssertNil(manager.qwen3ModelPath)
        XCTAssertFalse(manager.isQwen3ModelAvailable)
        let preparedModels = await readinessPreparer.preparedModelsSnapshot()
        XCTAssertTrue(preparedModels.isEmpty)
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
            )
        )
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

private struct SettingsFailingQwen3ModelDownloader: Qwen3ModelDownloading {
    func download(
        manifest: Qwen3ModelManifest,
        progress: @escaping Qwen3ModelDownloader.ProgressHandler
    ) async throws -> URL {
        XCTFail("Qwen 1.7B should fail before invoking the downloader.")
        return URL(fileURLWithPath: "/tmp/unreachable-qwen17", isDirectory: true)
    }

    func missingRequiredLocalPaths(
        size: ASRManager.ModelSize,
        at directory: URL,
        fileManager: FileManager
    ) -> [String] {
        XCTFail("Qwen 1.7B should fail before checking downloaded files.")
        return []
    }
}

private enum Qwen3ModelReadinessTestError: Error, Equatable {
    case canaryFailed
    case runtimeProvisionFailed
}

private actor CapturingQwen3RuntimeProvisioner: Qwen3MLXRuntimeProvisioning {
    private let result: Result<URL, Error>
    private(set) var prepareCallCount = 0

    init(
        result: Result<URL, Error> = .success(
            URL(fileURLWithPath: "/tmp/qwen3-managed-python")
        )
    ) {
        self.result = result
    }

    func prepare() async throws -> URL {
        prepareCallCount += 1
        return try result.get()
    }
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
