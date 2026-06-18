import Foundation
import XCTest
@testable import VoxFlowApp

final class VoiceTaskAudioCleanupTests: XCTestCase {
    private var tempDirectory: URL!
    private var paths: ApplicationSupportPaths!
    private var databaseQueue: DatabaseQueue!
    private var repository: VoiceTaskRepository!
    private var fileManager: FileManager!

    override func setUpWithError() throws {
        try super.setUpWithError()
        fileManager = FileManager.default
        tempDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("VoiceTaskAudioTests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let appSupportURL = tempDirectory.appendingPathComponent("AppSupport", isDirectory: true)
        paths = ApplicationSupportPaths(applicationSupportDirectory: appSupportURL)
        try paths.ensureDirectories(fileManager: fileManager)

        databaseQueue = try DatabaseQueue(connection: .inMemory())
        try AppDatabase.migrator(clock: SystemClock()).migrate(databaseQueue)
    }

    override func tearDown() {
        try? fileManager.removeItem(at: tempDirectory)
        repository = nil
        databaseQueue = nil
        paths = nil
        tempDirectory = nil
        fileManager = nil
        super.tearDown()
    }

    // MARK: - Successful transcription: audio deleted promptly

    func testSuccessfulTaskAudioIsDeleted() throws {
        let clock = FixedClock(now: Date(timeIntervalSince1970: 1_800_000_000))
        repository = VoiceTaskRepository(databaseQueue: databaseQueue, clock: clock)
        let service = VoiceTaskAudioService(
            paths: paths,
            repository: repository,
            clock: clock,
            fileManager: fileManager
        )

        let taskID = "task-success"
        let task = makeTask(id: taskID, stage: .transcribing, status: .completed, clock: clock)
        try repository.create(task)

        let audioURL = paths.voiceTaskAudioURL(forTaskID: taskID)
        try Data("fake-audio".utf8).write(to: audioURL)
        XCTAssertTrue(fileManager.fileExists(atPath: audioURL.path))

        try service.cleanupAfterSuccessfulTranscription(taskID: taskID)

        XCTAssertFalse(fileManager.fileExists(atPath: audioURL.path))
    }

    // MARK: - Failed transcription: audio retained

    func testFailedTaskAudioIsRetained() throws {
        let clock = FixedClock(now: Date(timeIntervalSince1970: 1_800_000_000))
        repository = VoiceTaskRepository(databaseQueue: databaseQueue, clock: clock)
        let service = VoiceTaskAudioService(
            paths: paths,
            repository: repository,
            clock: clock,
            fileManager: fileManager
        )

        let taskID = "task-fail"
        let task = makeTask(id: taskID, stage: .transcribing, status: .failed, clock: clock)
        try repository.create(task)

        let audioURL = paths.voiceTaskAudioURL(forTaskID: taskID)
        try Data("fake-audio".utf8).write(to: audioURL)

        try service.cleanupAfterSuccessfulTranscription(taskID: taskID)

        // Audio should still exist because task status is failed
        XCTAssertTrue(fileManager.fileExists(atPath: audioURL.path))
    }

    // MARK: - Cleanup deletes audio older than 24 hours for failed tasks

    func testCleanupDeletesAudioOlderThan24Hours() throws {
        let oldTime = Date(timeIntervalSince1970: 1_800_000_000)
        let oldClock = FixedClock(now: oldTime)
        repository = VoiceTaskRepository(databaseQueue: databaseQueue, clock: oldClock)

        let taskID = "task-old-fail"
        let task = makeTask(id: taskID, stage: .transcribing, status: .failed, clock: oldClock)
        try repository.create(task)

        let audioURL = paths.voiceTaskAudioURL(forTaskID: taskID)
        try Data("fake-audio".utf8).write(to: audioURL)

        // Run cleanup 25 hours later
        let cleanupTime = oldTime.addingTimeInterval(25 * 3600)
        let cleanupClock = FixedClock(now: cleanupTime)
        let service = VoiceTaskAudioService(
            paths: paths,
            repository: repository,
            clock: cleanupClock,
            fileManager: fileManager
        )

        try service.cleanupStaleAudio()

        XCTAssertFalse(fileManager.fileExists(atPath: audioURL.path))
    }

    // MARK: - Cleanup retains recent failed-task audio

    func testCleanupRetainsRecentFailedTaskAudio() throws {
        let recentTime = Date(timeIntervalSince1970: 1_800_000_000)
        let clock = FixedClock(now: recentTime)
        repository = VoiceTaskRepository(databaseQueue: databaseQueue, clock: clock)

        let taskID = "task-recent-fail"
        let task = makeTask(id: taskID, stage: .transcribing, status: .failed, clock: clock)
        try repository.create(task)

        let audioURL = paths.voiceTaskAudioURL(forTaskID: taskID)
        try Data("fake-audio".utf8).write(to: audioURL)

        // Run cleanup 1 hour later (within 24h window)
        let cleanupTime = recentTime.addingTimeInterval(3600)
        let cleanupClock = FixedClock(now: cleanupTime)
        let service = VoiceTaskAudioService(
            paths: paths,
            repository: repository,
            clock: cleanupClock,
            fileManager: fileManager
        )

        try service.cleanupStaleAudio()

        XCTAssertTrue(fileManager.fileExists(atPath: audioURL.path))
    }

    // MARK: - Injectable clock

    func testCleanupUsesInjectableClock() throws {
        // Verify that two different clocks produce different cleanup results
        // for the same task. This proves the clock is actually used.
        let taskCreationTime = Date(timeIntervalSince1970: 1_800_000_000)
        let creationClock = FixedClock(now: taskCreationTime)
        repository = VoiceTaskRepository(databaseQueue: databaseQueue, clock: creationClock)

        let taskID = "task-clock"
        let task = makeTask(id: taskID, stage: .transcribing, status: .failed, clock: creationClock)
        try repository.create(task)

        let audioURL = paths.voiceTaskAudioURL(forTaskID: taskID)
        try Data("fake-audio".utf8).write(to: audioURL)

        // First cleanup with "now" clock -> should retain
        let earlyClock = FixedClock(now: taskCreationTime.addingTimeInterval(60))
        let earlyService = VoiceTaskAudioService(
            paths: paths,
            repository: repository,
            clock: earlyClock,
            fileManager: fileManager
        )
        try earlyService.cleanupStaleAudio()
        XCTAssertTrue(fileManager.fileExists(atPath: audioURL.path),
                      "Audio should be retained with early clock")

        // Second cleanup with "far future" clock -> should delete
        let lateClock = FixedClock(now: taskCreationTime.addingTimeInterval(25 * 3600))
        let lateService = VoiceTaskAudioService(
            paths: paths,
            repository: repository,
            clock: lateClock,
            fileManager: fileManager
        )
        try lateService.cleanupStaleAudio()
        XCTAssertFalse(fileManager.fileExists(atPath: audioURL.path),
                       "Audio should be deleted with late clock")
    }

    // MARK: - Helpers

    private func makeTask(
        id: String,
        stage: VoiceTaskStage = .recording,
        status: VoiceTaskStatus = .inProgress,
        clock: FixedClock
    ) -> VoiceTask {
        VoiceTask(
            id: id,
            mode: .dictation,
            stage: stage,
            status: status,
            audioRelativePath: "voice-task-audio/\(id).m4a",
            createdAt: clock.now,
            updatedAt: clock.now
        )
    }
}

private struct FixedClock: AppClock {
    let now: Date

    func sleep(nanoseconds: UInt64) async throws {}
}
