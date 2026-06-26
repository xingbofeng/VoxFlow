import XCTest
@testable import VoxFlowApp

final class DependencyContainerTests: XCTestCase {
    func testInMemoryContainerCreatesMigratedRepositories() throws {
        let container = try DependencyContainer.inMemory()

        XCTAssertFalse(container.storageHealth.isPersistent)
        try container.settingsRepository.set("test.key", jsonValue: #"{"ok":true}"#)

        XCTAssertEqual(
            try container.settingsRepository.value(forKey: "test.key"),
            #"{"ok":true}"#
        )
    }

    func testAppEnvironmentExposesContainerServices() throws {
        let container = try DependencyContainer.inMemory()

        let environment = AppEnvironment(container: container)

        XCTAssertEqual(environment.storageHealth, container.storageHealth)
        try environment.historyRepository.save(
            DictationHistoryEntry(
                id: "entry",
                rawText: "raw",
                finalText: "final",
                language: "zh-CN",
                asrProviderID: "apple",
                llmProviderID: nil,
                styleID: nil,
                durationMS: 100,
                charCount: 5,
                cpm: 120,
                targetAppBundleID: nil,
                targetAppName: nil,
                processingWarningsJSON: nil,
                createdAt: Date(timeIntervalSince1970: 1_800_000_000),
                updatedAt: Date(timeIntervalSince1970: 1_800_000_000),
                deletedAt: nil
            )
        )

        XCTAssertEqual(try environment.historyRepository.listRecent(limit: 10).map(\.id), ["entry"])
        try environment.assetRepository.save(
            AssetItem(
                id: "asset",
                source: .clipboard,
                contentType: .text,
                title: "asset",
                previewText: nil,
                text: "asset text",
                rawText: nil,
                imagePath: nil,
                filePath: nil,
                url: nil,
                colorValue: nil,
                sourceAppName: nil,
                sourceAppBundleID: nil,
                contentHash: "hash-asset",
                captureReason: .userCopied,
                metadataJSON: nil,
                createdAt: Date(timeIntervalSince1970: 1_800_000_000),
                updatedAt: Date(timeIntervalSince1970: 1_800_000_000),
                deletedAt: nil
            )
        )

        XCTAssertEqual(try environment.assetRepository.page(query: .init(limit: 10, offset: 0)).items.map(\.id), ["asset"])
        XCTAssertTrue(environment.correctionTargetRepository is SQLiteCorrectionTargetRepository)
    }

    func testInMemoryContainerCanExposeLaunchFailureReason() throws {
        let container = try DependencyContainer.inMemory(
            storageHealth: .volatile(reason: "Persistent storage failed to initialize: disk locked")
        )

        XCTAssertEqual(
            container.storageHealth,
            .volatile(reason: "Persistent storage failed to initialize: disk locked")
        )
    }

    func testDefaultCredentialStoreUsesAppLocalApplicationSupportFile() throws {
        let paths = ApplicationSupportPaths(
            applicationSupportDirectory: FileManager.default.temporaryDirectory
                .appendingPathComponent("DependencyContainerTests-\(UUID().uuidString)", isDirectory: true)
        )

        let credentialStore = DependencyContainer.defaultCredentialStore(paths: paths)

        XCTAssertTrue(credentialStore is AppLocalCredentialStore)
    }

    func testStartupCleanupRemovesStaleScreenRecordingTemporaryFiles() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DependencyContainerRecCleanup-\(UUID().uuidString)", isDirectory: true)
        let paths = ApplicationSupportPaths(applicationSupportDirectory: root)
        try paths.ensureDirectories()
        defer { try? FileManager.default.removeItem(at: root) }

        let stale = paths.screenRecordingTemporaryDirectory.appendingPathComponent("stale.tmp.mp4")
        try Data("stale".utf8).write(to: stale)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 1_700_000_000)],
            ofItemAtPath: stale.path
        )
        let fresh = paths.screenRecordingTemporaryDirectory.appendingPathComponent("fresh.tmp.mp4")
        try Data("fresh".utf8).write(to: fresh)

        DependencyContainer.cleanupStaleScreenRecordingTemporaryFiles(
            paths: paths,
            now: Date(timeIntervalSince1970: 1_700_000_000 + 25 * 60 * 60)
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: stale.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fresh.path))
    }
}
