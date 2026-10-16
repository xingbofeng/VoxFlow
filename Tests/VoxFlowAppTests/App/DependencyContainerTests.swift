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

    func testDefaultCredentialStoreUsesLocalCredentialsFile() throws {
        let paths = ApplicationSupportPaths(
            applicationSupportDirectory: FileManager.default.temporaryDirectory
                .appendingPathComponent("DependencyContainerTests-\(UUID().uuidString)", isDirectory: true)
        )

        let credentialStore = DependencyContainer.defaultCredentialStore(paths: paths)

        XCTAssertTrue(credentialStore is AppLocalCredentialStore)
    }

    func testInMemoryContainerKeepsCredentialsInTemporaryLocalStore() throws {
        let container = try DependencyContainer.inMemory()

        XCTAssertTrue(container.credentialStore is AppLocalCredentialStore)
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

    func testStartupCleanupRemovesStaleVoiceTaskAudio() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DependencyContainerVoiceAudioCleanup-\(UUID().uuidString)", isDirectory: true)
        let paths = ApplicationSupportPaths(applicationSupportDirectory: root)
        try paths.ensureDirectories()
        defer { try? FileManager.default.removeItem(at: root) }

        let databaseQueue = try DatabaseQueue(connection: .inMemory())
        try AppDatabase.migrator(clock: SystemClock()).migrate(databaseQueue)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let clock = StartupCleanupFixedClock(now: now)
        let repository = VoiceTaskRepository(databaseQueue: databaseQueue, clock: clock)

        func makeTask(id: String, status: VoiceTaskStatus, updatedAt: Date) -> VoiceTask {
            VoiceTask(
                id: id,
                mode: .dictation,
                stage: .transcribing,
                status: status,
                audioRelativePath: "voice-task-audio/\(id).m4a",
                createdAt: updatedAt,
                updatedAt: updatedAt
            )
        }

        // Expired failed-task audio (older than the 24h retention) is removed.
        try repository.create(makeTask(id: "task-expired", status: .failed, updatedAt: now.addingTimeInterval(-25 * 60 * 60)))
        let expiredAudio = paths.voiceTaskAudioURL(forTaskID: "task-expired")
        try Data("expired".utf8).write(to: expiredAudio)

        // Fresh failed-task audio within retention is kept.
        try repository.create(makeTask(id: "task-fresh", status: .failed, updatedAt: now.addingTimeInterval(-3600)))
        let freshAudio = paths.voiceTaskAudioURL(forTaskID: "task-fresh")
        try Data("fresh".utf8).write(to: freshAudio)

        // Orphan audio with no task record is removed.
        let orphanAudio = paths.voiceTaskAudioURL(forTaskID: "task-orphan")
        try Data("orphan".utf8).write(to: orphanAudio)

        // Completed-task audio is outside this cleanup's contract (handled by
        // cleanupAfterSuccessfulTranscription) and must be kept.
        try repository.create(makeTask(id: "task-completed", status: .completed, updatedAt: now.addingTimeInterval(-48 * 60 * 60)))
        let completedAudio = paths.voiceTaskAudioURL(forTaskID: "task-completed")
        try Data("completed".utf8).write(to: completedAudio)

        DependencyContainer.cleanupStaleVoiceTaskAudio(
            paths: paths,
            repository: repository,
            clock: clock
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: expiredAudio.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: freshAudio.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphanAudio.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: completedAudio.path))
    }
}

private struct StartupCleanupFixedClock: AppClock {
    let now: Date

    func sleep(nanoseconds: UInt64) async throws {}
}
