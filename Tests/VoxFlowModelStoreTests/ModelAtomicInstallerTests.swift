import XCTest
import VoxFlowModelStore

final class ModelAtomicInstallerTests: XCTestCase {
    func testInstallerValidatesStagingBeforeMovingToDestination() throws {
        let root = try makeTemporaryDirectory()
        let staging = root.appendingPathComponent("qwen3.partial", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        try Data("hello".utf8).write(to: staging.appendingPathComponent("encoder.bin"))

        let installation = try ModelAtomicInstaller().install(
            manifest: manifest(),
            stagingRoot: staging,
            storeRoot: root.appendingPathComponent("installed", isDirectory: true),
            runtimeVersion: "coreml-8"
        )

        XCTAssertEqual(installation.modelID.rawValue, "qwen3-asr-0.6b")
        XCTAssertEqual(installation.version, "2026.06.01")
        XCTAssertTrue(FileManager.default.fileExists(atPath: installation.installedRoot.appendingPathComponent("encoder.bin").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: staging.path))
    }

    func testInstallFailureDoesNotPolluteExistingVersion() throws {
        let root = try makeTemporaryDirectory()
        let storeRoot = root.appendingPathComponent("installed", isDirectory: true)
        let existing = storeRoot
            .appendingPathComponent("qwen3-asr-0.6b", isDirectory: true)
            .appendingPathComponent("2026.06.01", isDirectory: true)
        try FileManager.default.createDirectory(at: existing, withIntermediateDirectories: true)
        try Data("old".utf8).write(to: existing.appendingPathComponent("encoder.bin"))

        let staging = root.appendingPathComponent("qwen3.partial", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        try Data("wrong".utf8).write(to: staging.appendingPathComponent("encoder.bin"))

        XCTAssertThrowsError(
            try ModelAtomicInstaller().install(
                manifest: manifest(),
                stagingRoot: staging,
                storeRoot: storeRoot,
                runtimeVersion: "coreml-8"
            )
        )
        let existingData = try Data(contentsOf: existing.appendingPathComponent("encoder.bin"))
        XCTAssertEqual(String(data: existingData, encoding: .utf8), "old")
        XCTAssertTrue(FileManager.default.fileExists(atPath: staging.path))
    }

    func testCleanupRemovesExpiredPartialDirectoriesOnly() throws {
        let root = try makeTemporaryDirectory()
        let expired = root.appendingPathComponent("expired.partial", isDirectory: true)
        let recent = root.appendingPathComponent("recent.partial", isDirectory: true)
        let installed = root.appendingPathComponent("installed", isDirectory: true)
        for directory in [expired, recent, installed] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 100)],
            ofItemAtPath: expired.path
        )
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 1_000)],
            ofItemAtPath: recent.path
        )

        let removed = try ModelAtomicInstaller().cleanupExpiredStagingDirectories(
            in: root,
            olderThan: 500,
            referenceDate: Date(timeIntervalSince1970: 1_000)
        )

        XCTAssertEqual(removed.map { $0.lastPathComponent }, ["expired.partial"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: expired.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: recent.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: installed.path))
    }

    func testCoordinatorDeduplicatesConcurrentInstallForSameModel() async throws {
        let coordinator = ModelInstallCoordinator()
        let counter = InstallCounter()
        let key = ModelInstallKey(modelID: ModelID(rawValue: "qwen3-asr-0.6b"), version: "2026.06.01")

        async let first = coordinator.install(for: key) {
            try await counter.install()
        }
        async let second = coordinator.install(for: key) {
            try await counter.install()
        }

        let firstInstallation = try await first
        let secondInstallation = try await second

        XCTAssertEqual(
            [firstInstallation.installedRoot.path, secondInstallation.installedRoot.path],
            ["/tmp/install", "/tmp/install"]
        )
        let installCount = await counter.currentCount()
        XCTAssertEqual(installCount, 1)
    }

    private func manifest() -> ModelManifest {
        ModelManifest(
            schemaVersion: 1,
            components: [
                ModelComponentManifest(
                    providerID: ModelProviderID(rawValue: "qwen3"),
                    modelID: ModelID(rawValue: "qwen3-asr-0.6b"),
                    version: "2026.06.01",
                    runtimeVersion: "coreml-8",
                    downloadURL: URL(string: "https://example.com/encoder.bin")!,
                    expectedSizeBytes: 5,
                    sha256: SHA256Digest(rawValue: "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"),
                    localPath: "encoder.bin",
                    requirement: .required,
                    supportedArchitectures: [.arm64],
                    minimumOSVersion: "14.0",
                    minimumMemoryBytes: 8 * 1_024 * 1_024 * 1_024,
                    license: ModelLicense(name: "Apache-2.0", url: nil)
                )
            ]
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }
}

private actor InstallCounter {
    private(set) var count = 0

    func install() async throws -> ModelInstallation {
        count += 1
        try await Task.sleep(nanoseconds: 30_000_000)
        return ModelInstallation(
            modelID: ModelID(rawValue: "qwen3-asr-0.6b"),
            version: "2026.06.01",
            installedRoot: URL(fileURLWithPath: "/tmp/install")
        )
    }

    func currentCount() -> Int {
        count
    }
}
