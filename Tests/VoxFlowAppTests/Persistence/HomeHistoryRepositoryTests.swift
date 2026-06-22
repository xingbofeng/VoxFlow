import XCTest
@testable import VoxFlowApp

final class HomeHistoryRepositoryTests: XCTestCase {
    func testDashboardAggregateComputesStatsAndDailyActivityWithoutLoadingEntities() throws {
        let fixture = try makeFixture()
        try insertHistory(id: "today-valid", text: "12345", createdAt: "2026-06-23T09:00:00Z", into: fixture.queue, durationMS: 60_000, charCount: 100)
        try insertHistory(id: "today-short", text: "short", createdAt: "2026-06-23T10:00:00Z", into: fixture.queue, durationMS: 200, charCount: 50)
        try insertHistory(id: "yesterday", text: "old", createdAt: "2026-06-22T09:00:00Z", into: fixture.queue, durationMS: 30_000, charCount: 30)
        try insertHistory(id: "outside-activity", text: "ancient", createdAt: "2025-01-01T09:00:00Z", into: fixture.queue, durationMS: 10_000, charCount: 10)
        try insertHistory(id: "deleted", text: "deleted", createdAt: "2026-06-23T11:00:00Z", into: fixture.queue, durationMS: 10_000, charCount: 999)
        try SQLiteHistoryRepository(databaseQueue: fixture.queue).softDelete(
            id: "deleted",
            deletedAt: date("2026-06-23T12:00:00Z")
        )

        let aggregate = try fixture.repository.dashboardAggregate(
            focusStartDate: date("2026-06-23T00:00:00Z"),
            focusEndDate: date("2026-06-24T00:00:00Z"),
            activityStartDate: date("2026-06-22T00:00:00Z"),
            activityEndDate: date("2026-06-24T00:00:00Z")
        )

        XCTAssertEqual(aggregate.totalCharacters, 140)
        XCTAssertEqual(aggregate.totalDurationMS, 100_000)
        XCTAssertEqual(aggregate.focusedCharacters, 150)
        XCTAssertEqual(
            aggregate.activityDays,
            [
                HomeHistoryActivityDay(date: date("2026-06-22T00:00:00Z"), characters: 30),
                HomeHistoryActivityDay(date: date("2026-06-23T00:00:00Z"), characters: 150),
            ]
        )
    }

    func testDashboardActivityGroupsAcrossUTCMidnightUsingCallerTimeZone() throws {
        let fixture = try makeFixture()
        try insertHistory(id: "before-local-midnight", text: "before", createdAt: "2026-06-22T15:59:00Z", into: fixture.queue, charCount: 10)
        try insertHistory(id: "after-local-midnight", text: "after", createdAt: "2026-06-22T16:01:00Z", into: fixture.queue, charCount: 20)

        let aggregate = try fixture.repository.dashboardAggregate(
            focusStartDate: date("2026-06-21T16:00:00Z"),
            focusEndDate: date("2026-06-22T16:00:00Z"),
            activityStartDate: date("2026-06-21T16:00:00Z"),
            activityEndDate: date("2026-06-23T16:00:00Z"),
            activityTimeZoneOffsetSeconds: 8 * 60 * 60
        )

        XCTAssertEqual(
            aggregate.activityDays,
            [
                HomeHistoryActivityDay(date: date("2026-06-21T16:00:00Z"), characters: 10),
                HomeHistoryActivityDay(date: date("2026-06-22T16:00:00Z"), characters: 20),
            ]
        )
    }

    func testMixedPaginationUsesStableGlobalOrderingWithoutGapsOrDuplicates() throws {
        let fixture = try makeFixture()
        try insertHistory(id: "history-old", text: "old", createdAt: "2026-06-21T08:00:00Z", into: fixture.queue)
        try insertTask(id: "task-new", mode: "agentCompose", status: "completed", text: "new", createdAt: "2026-06-23T08:00:00Z", into: fixture.queue)
        try insertHistory(id: "history-tie", text: "tie history", createdAt: "2026-06-22T08:00:00Z", into: fixture.queue)
        try insertTask(id: "task-tie", mode: "agentDispatch", status: "failed", text: "tie task", createdAt: "2026-06-22T08:00:00Z", into: fixture.queue)
        try insertTask(id: "ignored-dictation", mode: "dictation", status: "completed", text: "ignored", createdAt: "2026-06-24T08:00:00Z", into: fixture.queue)
        try insertTask(id: "ignored-progress", mode: "agentCompose", status: "inProgress", text: "ignored", createdAt: "2026-06-24T08:00:00Z", into: fixture.queue)

        let first = try fixture.repository.page(query: .init(limit: 2, offset: 0))
        let second = try fixture.repository.page(query: .init(limit: 2, offset: 2))

        XCTAssertEqual(first.totalCount, 4)
        XCTAssertEqual(first.records.map(\.id), ["task-new", "history-tie"])
        XCTAssertEqual(second.records.map(\.id), ["task-tie", "history-old"])
        XCTAssertEqual(Set(first.records.map(\.id)).intersection(second.records.map(\.id)), [])
    }

    func testCountAndPagesApplySearchAndDateToBothSources() throws {
        let fixture = try makeFixture()
        try insertHistory(id: "history-match", text: "Alpha history", createdAt: "2026-06-22T09:00:00Z", into: fixture.queue)
        try insertTask(id: "task-match", mode: "agentCompose", status: "completed", text: "alpha task", createdAt: "2026-06-22T10:00:00Z", into: fixture.queue)
        try insertHistory(id: "outside-date", text: "alpha old", createdAt: "2026-06-20T09:00:00Z", into: fixture.queue)
        try insertTask(id: "outside-search", mode: "agentDispatch", status: "completed", text: "beta", createdAt: "2026-06-22T11:00:00Z", into: fixture.queue)

        let page = try fixture.repository.page(
            query: .init(
                searchText: "ALPHA",
                startDate: date("2026-06-22T00:00:00Z"),
                endDate: date("2026-06-23T00:00:00Z"),
                limit: 1,
                offset: 1
            )
        )

        XCTAssertEqual(page.totalCount, 2)
        XCTAssertEqual(page.records.map(\.id), ["history-match"])
    }

    func testClearAllSoftDeletesDictationAndDeletesOnlyFinishedAgentTasksInOneTransaction() throws {
        let fixture = try makeFixture()
        try insertHistory(id: "history", text: "history", createdAt: "2026-06-22T09:00:00Z", into: fixture.queue)
        try insertTask(id: "finished", mode: "agentCompose", status: "completed", text: "done", createdAt: "2026-06-22T10:00:00Z", into: fixture.queue)
        try insertTask(id: "progress", mode: "agentDispatch", status: "inProgress", text: "working", createdAt: "2026-06-22T11:00:00Z", into: fixture.queue)

        try fixture.repository.clearAll(deletedAt: date("2026-06-23T00:00:00Z"))

        XCTAssertEqual(try fixture.repository.page(query: .init(limit: 20, offset: 0)).totalCount, 0)
        let state = try fixture.queue.read { connection -> (String?, Int, Int) in
            let history = try connection.prepare("SELECT deleted_at FROM dictation_history WHERE id = 'history'")
            _ = try history.step()
            let finished = try connection.prepare("SELECT COUNT(*) FROM voice_tasks WHERE id = 'finished'")
            _ = try finished.step()
            let progress = try connection.prepare("SELECT COUNT(*) FROM voice_tasks WHERE id = 'progress'")
            _ = try progress.step()
            return (history.columnString(at: 0), finished.columnInt(at: 0), progress.columnInt(at: 0))
        }
        XCTAssertNotNil(state.0)
        XCTAssertEqual(state.1, 0)
        XCTAssertEqual(state.2, 1)
    }

    func testClearAllRollsBackSoftDeletesWhenAgentDeletionFails() throws {
        let fixture = try makeFixture()
        try insertHistory(id: "history", text: "history", createdAt: "2026-06-22T09:00:00Z", into: fixture.queue)
        try insertTask(id: "finished", mode: "agentCompose", status: "completed", text: "done", createdAt: "2026-06-22T10:00:00Z", into: fixture.queue)
        try fixture.queue.write { connection in
            try connection.execute(
                """
                CREATE TRIGGER reject_finished_task_delete
                BEFORE DELETE ON voice_tasks
                WHEN OLD.id = 'finished'
                BEGIN
                    SELECT RAISE(ABORT, 'delete rejected');
                END
                """
            )
        }

        XCTAssertThrowsError(
            try fixture.repository.clearAll(deletedAt: date("2026-06-23T00:00:00Z"))
        )

        let page = try fixture.repository.page(query: .init(limit: 20, offset: 0))
        XCTAssertEqual(page.totalCount, 2)
        XCTAssertEqual(Set(page.records.map(\.id)), ["history", "finished"])
    }

    private func makeFixture() throws -> (queue: DatabaseQueue, repository: HomeHistoryRepository) {
        let queue = try DatabaseQueue(connection: .inMemory())
        try AppDatabase.migrator().migrate(queue)
        return (queue, HomeHistoryRepository(databaseQueue: queue))
    }

    private func insertHistory(
        id: String,
        text: String,
        createdAt: String,
        into queue: DatabaseQueue,
        durationMS: Int = 1000,
        charCount: Int? = nil
    ) throws {
        try queue.write { connection in
            try connection.execute(
                """
                INSERT INTO dictation_history
                    (id, raw_text, final_text, language, duration_ms, char_count, cpm, created_at, updated_at)
                VALUES ('\(id)', '\(text)', '\(text)', 'zh-CN', \(durationMS), \(charCount ?? text.count), 120, '\(createdAt)', '\(createdAt)')
                """
            )
        }
    }

    private func insertTask(
        id: String,
        mode: String,
        status: String,
        text: String,
        createdAt: String,
        into queue: DatabaseQueue
    ) throws {
        try queue.write { connection in
            try connection.execute(
                """
                INSERT INTO voice_tasks
                    (id, mode, stage, status, raw_transcript, final_text, warnings_json, created_at, updated_at)
                VALUES ('\(id)', '\(mode)', 'outputting', '\(status)', '\(text)', '\(text)', '[]', '\(createdAt)', '\(createdAt)')
                """
            )
        }
    }

    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }
}
