import XCTest
@testable import VoxFlowApp

final class SQLiteTranscriptionJobAndSegmentRepositoryTests: XCTestCase {
    private var queue: DatabaseQueue!
    private var jobRepository: SQLiteTranscriptionJobRepository!
    private var segmentRepository: SQLiteTranscriptionSegmentRepository!
    private let formatter = ISO8601DateFormatter()

    private var testDate: Date { Date(timeIntervalSince1970: 1_800_000_000) }

    override func setUpWithError() throws {
        try super.setUpWithError()
        queue = try DatabaseQueue(connection: .inMemory())
        try AppDatabase.migrator().migrate(queue)
        jobRepository = SQLiteTranscriptionJobRepository(databaseQueue: queue)
        segmentRepository = SQLiteTranscriptionSegmentRepository(databaseQueue: queue)
    }

    override func tearDown() {
        queue = nil
        jobRepository = nil
        segmentRepository = nil
        super.tearDown()
    }

    // MARK: - Job repository

    func testSaveAndFetchJobWithDefaults() throws {
        let job = makeJob(id: "job-default", status: "queued")

        try jobRepository.save(job)

        let saved = try XCTUnwrap(try jobRepository.job(id: "job-default"))
        XCTAssertEqual(saved, job)
        XCTAssertEqual(saved.providerMode, nil)
        XCTAssertEqual(saved.segmentCount, 0)
        XCTAssertEqual(saved.segmentCompleted, 0)
        XCTAssertEqual(saved.translationStatus, TranslationStatus.none.rawValue)
        XCTAssertNil(saved.translationUpdatedAt)
    }

    func testSaveAndFetchJobWithPipelineFields() throws {
        let job = TranscriptionJobRecord(
            id: "job-extended",
            sourceFilePath: "/tmp/audio.m4a",
            sourceFileName: "audio.m4a",
            status: TranscriptionJobStatus.partiallyFailed.rawValue,
            progress: 0.6,
            rawText: "raw",
            finalText: "final",
            asrProviderID: "groq",
            styleID: nil,
            errorMessage: nil,
            durationMS: 60_000,
            createdAt: testDate,
            updatedAt: testDate,
            completedAt: nil,
            providerMode: TranscriptionProviderMode.segmentedCompatible.rawValue,
            segmentCount: 20,
            segmentCompleted: 12,
            partialFailureSummary: "段 5、段 13 失败"
        )

        try jobRepository.save(job)

        let saved = try XCTUnwrap(try jobRepository.job(id: "job-extended"))
        XCTAssertEqual(saved.status, TranscriptionJobStatus.partiallyFailed.rawValue)
        XCTAssertEqual(saved.providerMode, TranscriptionProviderMode.segmentedCompatible.rawValue)
        XCTAssertEqual(saved.segmentCount, 20)
        XCTAssertEqual(saved.segmentCompleted, 12)
        XCTAssertEqual(saved.partialFailureSummary, "段 5、段 13 失败")
    }

    func testSaveAndFetchJobWithTranslationFields() throws {
        let translatedAt = testDate.addingTimeInterval(60)
        let job = TranscriptionJobRecord(
            id: "job-translated",
            sourceFilePath: "/tmp/audio.m4a",
            sourceFileName: "audio.m4a",
            status: TranscriptionJobStatus.completed.rawValue,
            progress: 1,
            rawText: nil,
            finalText: "Hello",
            asrProviderID: nil,
            styleID: nil,
            errorMessage: nil,
            durationMS: 1_000,
            createdAt: testDate,
            updatedAt: translatedAt,
            completedAt: testDate,
            translatedText: "你好",
            translationTargetLanguage: "zh-Hans",
            translationProvider: "openaiCompatible",
            translationStatus: TranslationStatus.completed.rawValue,
            translationError: nil,
            translationUpdatedAt: translatedAt
        )

        try jobRepository.save(job)

        let saved = try XCTUnwrap(try jobRepository.job(id: "job-translated"))
        XCTAssertEqual(saved.translatedText, "你好")
        XCTAssertEqual(saved.translationTargetLanguage, "zh-Hans")
        XCTAssertEqual(saved.translationProvider, "openaiCompatible")
        XCTAssertEqual(saved.translationStatus, TranslationStatus.completed.rawValue)
        XCTAssertEqual(saved.translationUpdatedAt, translatedAt)
    }

    func testUpdateSegmentsAndProgressPersistsSegmentMetrics() throws {
        try jobRepository.save(makeJob(id: "job-seg", status: "queued"))

        try jobRepository.updateSegmentsAndProgress(
            id: "job-seg",
            status: TranscriptionJobStatus.running.rawValue,
            progress: 0.5,
            segmentCount: 10,
            segmentCompleted: 5,
            partialFailureSummary: nil,
            updatedAt: testDate
        )

        let saved = try XCTUnwrap(try jobRepository.job(id: "job-seg"))
        XCTAssertEqual(saved.status, TranscriptionJobStatus.running.rawValue)
        XCTAssertEqual(saved.progress, 0.5)
        XCTAssertEqual(saved.segmentCount, 10)
        XCTAssertEqual(saved.segmentCompleted, 5)
    }

    func testUpdateTranslationPersistsTranslationStateWithoutClobberingTranscript() throws {
        let job = TranscriptionJobRecord(
            id: "job-tr",
            sourceFilePath: "/tmp/audio.m4a",
            sourceFileName: "audio.m4a",
            status: TranscriptionJobStatus.completed.rawValue,
            progress: 1,
            rawText: "raw",
            finalText: "Hello world",
            asrProviderID: nil,
            styleID: nil,
            errorMessage: nil,
            durationMS: 1_000,
            createdAt: testDate,
            updatedAt: testDate,
            completedAt: testDate
        )
        try jobRepository.save(job)

        try jobRepository.updateTranslation(
            id: "job-tr",
            translatedText: "你好世界",
            targetLanguage: "zh-Hans",
            provider: "openaiCompatible",
            status: .completed,
            error: nil,
            updatedAt: testDate
        )

        let saved = try XCTUnwrap(try jobRepository.job(id: "job-tr"))
        XCTAssertEqual(saved.finalText, "Hello world")
        XCTAssertEqual(saved.translatedText, "你好世界")
        XCTAssertEqual(saved.translationStatus, TranslationStatus.completed.rawValue)
        XCTAssertEqual(saved.translationTargetLanguage, "zh-Hans")
    }

    func testUpdateTranslationFailedStatusKeepsOriginalTranscript() throws {
        try jobRepository.save(
            makeJob(
                id: "job-tr-fail",
                status: TranscriptionJobStatus.completed.rawValue,
                finalText: "原文"
            )
        )

        try jobRepository.updateTranslation(
            id: "job-tr-fail",
            translatedText: nil,
            targetLanguage: "zh-Hans",
            provider: "openaiCompatible",
            status: .failed,
            error: "timeout",
            updatedAt: testDate
        )

        let saved = try XCTUnwrap(try jobRepository.job(id: "job-tr-fail"))
        XCTAssertEqual(saved.status, TranscriptionJobStatus.completed.rawValue)
        XCTAssertEqual(saved.finalText, "原文")
        XCTAssertEqual(saved.translationStatus, TranslationStatus.failed.rawValue)
        XCTAssertEqual(saved.translationError, "timeout")
    }

    func testListReturnsJobsOrderedByCreatedAtDesc() throws {
        let earlier = makeJob(id: "earlier", status: "queued", createdAt: testDate.addingTimeInterval(-100))
        let later = makeJob(id: "later", status: "queued", createdAt: testDate)
        try jobRepository.save(earlier)
        try jobRepository.save(later)

        let list = try jobRepository.list()
        XCTAssertEqual(list.map(\.id), ["later", "earlier"])
    }

    func testDeleteJobAlsoRemovesSegmentsViaCascade() throws {
        try jobRepository.save(makeJob(id: "job-cascade", status: "queued"))
        try segmentRepository.save(makeSegment(id: "seg-1", jobID: "job-cascade", index: 0))
        try segmentRepository.save(makeSegment(id: "seg-2", jobID: "job-cascade", index: 1))

        try jobRepository.delete(id: "job-cascade")

        XCTAssertNil(try jobRepository.job(id: "job-cascade"))
        XCTAssertTrue(try segmentRepository.segments(forJob: "job-cascade").isEmpty)
    }

    // MARK: - Legacy job compatibility

    func testLegacyJobRowWithoutNewColumnsLoadsAsDefaultValues() throws {
        // 直接插入旧 schema 的列子集，模拟升级前数据库里的旧任务。
        try queue.write { connection in
            let stmt = try connection.prepare(
                """
                INSERT INTO transcription_jobs (
                    id, source_file_path, source_file_name, status, progress,
                    raw_text, final_text, asr_provider_id, style_id, error_message,
                    duration_ms, created_at, updated_at, completed_at
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """
            )
            try stmt.bind("legacy-job", at: 1)
            try stmt.bind("/tmp/legacy.mp3", at: 2)
            try stmt.bind("legacy.mp3", at: 3)
            try stmt.bind("completed", at: 4)
            try stmt.bind(1.0, at: 5)
            try stmt.bind("legacy raw", at: 6)
            try stmt.bind("legacy final", at: 7)
            try stmt.bind(nil as String?, at: 8)
            try stmt.bind(nil as String?, at: 9)
            try stmt.bind(nil as String?, at: 10)
            try stmt.bind(5_000, at: 11)
            try stmt.bind(formatter.string(from: testDate), at: 12)
            try stmt.bind(formatter.string(from: testDate), at: 13)
            try stmt.bind(formatter.string(from: testDate), at: 14)
            _ = try stmt.step()
        }

        let saved = try XCTUnwrap(try jobRepository.job(id: "legacy-job"))
        XCTAssertEqual(saved.status, "completed")
        XCTAssertEqual(saved.finalText, "legacy final")
        XCTAssertEqual(saved.durationMS, 5_000)
        XCTAssertEqual(saved.providerMode, nil)
        XCTAssertEqual(saved.segmentCount, 0)
        XCTAssertEqual(saved.segmentCompleted, 0)
        XCTAssertEqual(saved.translationStatus, TranslationStatus.none.rawValue)
        XCTAssertNil(saved.translationUpdatedAt)
    }

    // MARK: - Segment repository

    func testSaveAndFetchSegmentsOrderedByIndex() throws {
        try jobRepository.save(makeJob(id: "job-seg-order", status: "queued"))
        try segmentRepository.save(makeSegment(id: "seg-b", jobID: "job-seg-order", index: 1))
        try segmentRepository.save(makeSegment(id: "seg-a", jobID: "job-seg-order", index: 0))
        try segmentRepository.save(makeSegment(id: "seg-c", jobID: "job-seg-order", index: 2))

        let segments = try segmentRepository.segments(forJob: "job-seg-order")
        XCTAssertEqual(segments.map(\.index), [0, 1, 2])
    }

    func testSaveUpsertsExistingSegment() throws {
        try jobRepository.save(makeJob(id: "job-upsert", status: "queued"))
        try segmentRepository.save(
            makeSegment(id: "seg-up", jobID: "job-upsert", index: 0, status: .pending)
        )
        let original = try XCTUnwrap(try segmentRepository.segments(forJob: "job-upsert").first)
        try segmentRepository.save(
            TranscriptionSegmentRecord(
                id: original.id,
                jobID: "job-upsert",
                index: 0,
                startMS: 0,
                endMS: 30_000,
                status: TranscriptionSegmentStatus.completed.rawValue,
                rawText: "raw",
                finalText: "final",
                promptContext: "前文",
                fallbackReason: nil,
                retryCount: 0,
                providerID: "groq",
                providerMode: TranscriptionProviderMode.nativeFile.rawValue,
                errorMessage: nil,
                durationMS: 1_200,
                createdAt: original.createdAt,
                updatedAt: testDate,
                completedAt: testDate
            )
        )

        let segments = try segmentRepository.segments(forJob: "job-upsert")
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments.first?.status, TranscriptionSegmentStatus.completed.rawValue)
        XCTAssertEqual(segments.first?.finalText, "final")
        XCTAssertEqual(segments.first?.providerMode, TranscriptionProviderMode.nativeFile.rawValue)
    }

    func testDeleteAllForJobRemovesAllSegments() throws {
        try jobRepository.save(makeJob(id: "job-del-all", status: "queued"))
        try segmentRepository.save(makeSegment(id: "seg-1", jobID: "job-del-all", index: 0))
        try segmentRepository.save(makeSegment(id: "seg-2", jobID: "job-del-all", index: 1))

        try segmentRepository.deleteAll(forJob: "job-del-all")

        XCTAssertTrue(try segmentRepository.segments(forJob: "job-del-all").isEmpty)
    }

    func testDeleteSegmentByIdRemovesSingleSegment() throws {
        try jobRepository.save(makeJob(id: "job-del-one", status: "queued"))
        try segmentRepository.save(makeSegment(id: "seg-keep", jobID: "job-del-one", index: 0))
        try segmentRepository.save(makeSegment(id: "seg-drop", jobID: "job-del-one", index: 1))

        try segmentRepository.delete(id: "seg-drop")

        let remaining = try segmentRepository.segments(forJob: "job-del-one")
        XCTAssertEqual(remaining.map(\.id), ["seg-keep"])
    }

    func testMarkRunningSegmentsInterruptedUpdatesOnlyRunningRows() throws {
        try jobRepository.save(makeJob(id: "job-mark", status: "running"))
        try segmentRepository.save(
            makeSegment(id: "seg-running", jobID: "job-mark", index: 0, status: .running)
        )
        try segmentRepository.save(
            makeSegment(id: "seg-completed", jobID: "job-mark", index: 1, status: .completed)
        )
        try segmentRepository.save(
            makeSegment(id: "seg-failed", jobID: "job-mark", index: 2, status: .failed)
        )

        try segmentRepository.markRunningSegmentsInterrupted(jobID: "job-mark", updatedAt: testDate)

        let segments = try segmentRepository.segments(forJob: "job-mark")
        let byID = Dictionary(uniqueKeysWithValues: segments.map { ($0.id, $0) })
        XCTAssertEqual(byID["seg-running"]?.status, TranscriptionSegmentStatus.interrupted.rawValue)
        XCTAssertEqual(byID["seg-completed"]?.status, TranscriptionSegmentStatus.completed.rawValue)
        XCTAssertEqual(byID["seg-failed"]?.status, TranscriptionSegmentStatus.failed.rawValue)
    }

    // MARK: - Helpers

    private func makeJob(
        id: String,
        status: String,
        createdAt: Date = Date(timeIntervalSince1970: 1_800_000_000),
        finalText: String? = nil
    ) -> TranscriptionJobRecord {
        TranscriptionJobRecord(
            id: id,
            sourceFilePath: "/tmp/audio.m4a",
            sourceFileName: "audio.m4a",
            status: status,
            progress: 0,
            rawText: nil,
            finalText: finalText,
            asrProviderID: nil,
            styleID: nil,
            errorMessage: nil,
            durationMS: 0,
            createdAt: createdAt,
            updatedAt: createdAt,
            completedAt: nil
        )
    }

    private func makeSegment(
        id: String,
        jobID: String,
        index: Int,
        status: TranscriptionSegmentStatus = .pending
    ) -> TranscriptionSegmentRecord {
        TranscriptionSegmentRecord(
            id: id,
            jobID: jobID,
            index: index,
            startMS: index * 30_000,
            endMS: (index + 1) * 30_000,
            status: status.rawValue,
            rawText: nil,
            finalText: nil,
            promptContext: nil,
            fallbackReason: nil,
            retryCount: 0,
            providerID: nil,
            providerMode: nil,
            errorMessage: nil,
            durationMS: 0,
            createdAt: testDate,
            updatedAt: testDate,
            completedAt: nil
        )
    }
}
