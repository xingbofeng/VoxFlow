import Foundation
import XCTest
@testable import VoxFlowApp

final class VoiceTaskRepositoryTests: XCTestCase {
    private var repository: VoiceTaskRepository!
    private var databaseQueue: DatabaseQueue!
    private let clock = FixedClock(now: Date(timeIntervalSince1970: 1_800_000_000))

    override func setUpWithError() throws {
        try super.setUpWithError()
        databaseQueue = try DatabaseQueue(connection: .inMemory())
        try AppDatabase.migrator(clock: clock).migrate(databaseQueue)
        repository = VoiceTaskRepository(databaseQueue: databaseQueue, clock: clock)
    }

    override func tearDown() {
        repository = nil
        databaseQueue = nil
        super.tearDown()
    }

    // MARK: - create

    func testCreateVoiceTaskPersistsAllFields() throws {
        let task = makeTask(
            id: "task-1",
            mode: .agentCompose,
            stage: .recording,
            status: .inProgress,
            targetAppBundleID: "com.example.editor",
            targetAppName: "Editor",
            targetAppPID: 42,
            targetWindowID: "win-1",
            targetWindowTitle: "My Window",
            audioRelativePath: "voice-task-audio/task-1.m4a",
            warnings: ["low_volume"]
        )

        try repository.create(task)

        let fetched = try repository.fetch(id: "task-1")
        XCTAssertEqual(fetched, task)
    }

    func testCreateVoiceTaskPersistsASRMetadata() throws {
        let task = makeTask(
            id: "task-asr-metadata",
            asrMetadata: VoiceTaskASRMetadata(
                providerID: "qwen3_asr",
                modelID: "qwen3-asr-0.6b",
                modelVersion: "2025-09-01",
                language: "zh-Hans-CN",
                sessionID: "session-123",
                audioDurationMs: 1_250,
                finalLatencyMs: 480,
                droppedFrameCount: 2,
                errorCode: "final_timeout"
            )
        )

        try repository.create(task)

        let fetched = try XCTUnwrap(repository.fetch(id: "task-asr-metadata"))
        XCTAssertEqual(fetched.asrMetadata?.providerID, "qwen3_asr")
        XCTAssertEqual(fetched.asrMetadata?.modelID, "qwen3-asr-0.6b")
        XCTAssertEqual(fetched.asrMetadata?.modelVersion, "2025-09-01")
        XCTAssertEqual(fetched.asrMetadata?.language, "zh-Hans-CN")
        XCTAssertEqual(fetched.asrMetadata?.sessionID, "session-123")
        XCTAssertEqual(fetched.asrMetadata?.audioDurationMs, 1_250)
        XCTAssertEqual(fetched.asrMetadata?.finalLatencyMs, 480)
        XCTAssertEqual(fetched.asrMetadata?.droppedFrameCount, 2)
        XCTAssertEqual(fetched.asrMetadata?.errorCode, "final_timeout")
    }

    // MARK: - updateStage

    func testUpdateStageAdvancesTask() throws {
        var task = makeTask(id: "task-2", stage: .recording)
        try repository.create(task)

        task.stage = .transcribing
        task.updatedAt = clock.now
        try repository.updateStage(task)

        let fetched = try repository.fetch(id: "task-2")
        XCTAssertEqual(fetched?.stage, .transcribing)
    }

    func testUpdateStageRejectsBackwardsTransition() throws {
        let task = makeTask(id: "task-3", stage: .transcribing)
        try repository.create(task)

        var backwards = task
        backwards.stage = .recording

        XCTAssertThrowsError(try repository.updateStage(backwards)) { error in
            guard case VoiceTaskError.backwardsStageTransition = error else {
                XCTFail("Expected backwardsStageTransition, got \(error)")
                return
            }
        }

        // Original stage is unchanged
        let fetched = try repository.fetch(id: "task-3")
        XCTAssertEqual(fetched?.stage, .transcribing)
    }

    // MARK: - queryIncompleteTasks

    func testQueryIncompleteTasksReturnsOnlyInProgress() throws {
        let inProgress = makeTask(id: "ip", status: .inProgress)
        let completed = makeTask(id: "comp", status: .completed)
        let failed = makeTask(id: "fail", status: .failed)
        try repository.create(inProgress)
        try repository.create(completed)
        try repository.create(failed)

        let incomplete = try repository.queryIncompleteTasks()

        XCTAssertEqual(incomplete.map(\.id), ["ip"])
    }

    func testListRecentAgentComposeTasksReturnsNewestFirst() throws {
        try repository.create(makeTask(
            id: "older",
            mode: .agentCompose,
            status: .completed,
            createdAt: Date(timeIntervalSince1970: 100)
        ))
        try repository.create(makeTask(
            id: "newer",
            mode: .agentCompose,
            status: .completed,
            createdAt: Date(timeIntervalSince1970: 200)
        ))
        try repository.create(makeTask(
            id: "dictation",
            mode: .dictation,
            status: .completed,
            createdAt: Date(timeIntervalSince1970: 300)
        ))

        let tasks = try repository.listRecent(mode: .agentCompose, limit: 10)

        XCTAssertEqual(tasks.map(\.id), ["newer", "older"])
    }

    func testDeleteRemovesVoiceTask() throws {
        try repository.create(makeTask(id: "task"))

        try repository.delete(id: "task")

        XCTAssertNil(try repository.fetch(id: "task"))
    }

    func testQueryIncompleteTasksReturnsEmptyWhenNone() throws {
        let completed = makeTask(id: "comp", status: .completed)
        try repository.create(completed)

        let incomplete = try repository.queryIncompleteTasks()

        XCTAssertTrue(incomplete.isEmpty)
    }

    // MARK: - migration

    func testMigrationFromExistingSchemaSucceeds() throws {
        // The migration already ran in setUp, so verify the table exists by creating a task.
        let task = makeTask(id: "mig-task")
        XCTAssertNoThrow(try repository.create(task))

        let fetched = try repository.fetch(id: "mig-task")
        XCTAssertNotNil(fetched)
    }

    // MARK: - field-level updates

    func testUpdateRawTranscript() throws {
        let task = makeTask(id: "task-rt")
        try repository.create(task)

        try repository.updateRawTranscript(id: "task-rt", rawTranscript: "hello world")

        let fetched = try repository.fetch(id: "task-rt")
        XCTAssertEqual(fetched?.rawTranscript, "hello world")
    }

    func testUpdateFinalText() throws {
        let task = makeTask(id: "task-ft")
        try repository.create(task)

        try repository.updateFinalText(id: "task-ft", finalText: "Hello, world.")

        let fetched = try repository.fetch(id: "task-ft")
        XCTAssertEqual(fetched?.finalText, "Hello, world.")
    }

    func testUpdateOutputResult() throws {
        let task = makeTask(id: "task-or")
        try repository.create(task)
        let result = OutputResult.injected
        let encoded = String(data: try JSONEncoder().encode(result), encoding: .utf8)!

        try repository.updateOutputResult(id: "task-or", outputResult: encoded)

        let fetched = try repository.fetch(id: "task-or")
        XCTAssertEqual(fetched?.outputResult, encoded)
    }

    func testUpdateFailure() throws {
        let task = makeTask(id: "task-fail")
        try repository.create(task)
        let failure = VoiceTaskFailure(
            stage: "transcribing",
            code: "TIMEOUT",
            message: "Timed out",
            recoverable: true
        )
        let encoded = String(data: try JSONEncoder().encode(failure), encoding: .utf8)!

        try repository.updateFailure(id: "task-fail", failureJson: encoded, status: .failed)

        let fetched = try repository.fetch(id: "task-fail")
        XCTAssertEqual(fetched?.failureJson, encoded)
        XCTAssertEqual(fetched?.status, .failed)
    }

    func testUpdateASRMetadata() throws {
        let task = makeTask(id: "task-asr-update")
        try repository.create(task)
        let metadata = VoiceTaskASRMetadata(
            providerID: "qwen3_asr",
            modelID: "qwen3-asr-0.6b",
            language: "en-US",
            sessionID: "session-456",
            audioDurationMs: 2_500,
            finalLatencyMs: 900,
            droppedFrameCount: 1
        )

        try repository.updateASRMetadata(id: "task-asr-update", metadata: metadata)

        let fetched = try repository.fetch(id: "task-asr-update")
        XCTAssertEqual(fetched?.asrMetadata, metadata)
    }

    func testCompleteTaskSetsCompletedAt() throws {
        let task = makeTask(id: "task-done")
        try repository.create(task)

        try repository.complete(
            id: "task-done",
            status: .completed,
            outputResult: nil,
            completedAt: clock.now
        )

        let fetched = try repository.fetch(id: "task-done")
        XCTAssertEqual(fetched?.status, .completed)
        XCTAssertEqual(fetched?.completedAt, clock.now)
    }

    // MARK: - Helpers

    private func makeTask(
        id: String = UUID().uuidString,
        mode: VoiceTaskMode = .dictation,
        stage: VoiceTaskStage = .recording,
        status: VoiceTaskStatus = .inProgress,
        targetAppBundleID: String? = nil,
        targetAppName: String? = nil,
        targetAppPID: Int? = nil,
        targetWindowID: String? = nil,
        targetWindowTitle: String? = nil,
        audioRelativePath: String? = nil,
        asrMetadata: VoiceTaskASRMetadata? = nil,
        warnings: [String] = [],
        createdAt: Date? = nil
    ) -> VoiceTask {
        VoiceTask(
            id: id,
            mode: mode,
            stage: stage,
            status: status,
            targetAppBundleID: targetAppBundleID,
            targetAppName: targetAppName,
            targetAppPID: targetAppPID,
            targetWindowID: targetWindowID,
            targetWindowTitle: targetWindowTitle,
            audioRelativePath: audioRelativePath,
            asrMetadata: asrMetadata,
            warnings: warnings,
            createdAt: createdAt ?? clock.now,
            updatedAt: createdAt ?? clock.now
        )
    }
}

private struct FixedClock: AppClock {
    let now: Date

    func sleep(nanoseconds: UInt64) async throws {}
}
