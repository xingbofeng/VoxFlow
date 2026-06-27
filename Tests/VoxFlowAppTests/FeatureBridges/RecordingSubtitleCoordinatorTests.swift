import XCTest
@testable import VoxFlowApp

@MainActor
final class RecordingSubtitleCoordinatorTests: XCTestCase {
    nonisolated(unsafe) private var paths: ApplicationSupportPaths!
    nonisolated(unsafe) private var tempRoot: URL!
    nonisolated(unsafe) private var repository: FakeSubtitleRepository!
    nonisolated(unsafe) private var draftStore: RecordingSubtitleDraftStore!
    nonisolated(unsafe) private var transcriber: FakeTranscriber!
    nonisolated(unsafe) private var burner: FakeBurner!
    nonisolated(unsafe) private var clock: FakeClock!
    nonisolated(unsafe) private var stateChanges: [String]!
    nonisolated(unsafe) private var draftReadyCalls: [String]!
    nonisolated(unsafe) private var burnedVideoReadyCalls: [URL]!
    private var coordinator: RecordingSubtitleCoordinator!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoxFlowSubtitleCoord-\(UUID().uuidString)", isDirectory: true)
        paths = ApplicationSupportPaths(applicationSupportDirectory: tempRoot)
        try paths.ensureDirectories()
        repository = FakeSubtitleRepository()
        draftStore = RecordingSubtitleDraftStore(paths: paths)
        transcriber = FakeTranscriber()
        burner = FakeBurner()
        clock = FakeClock(now: Date(timeIntervalSince1970: 1_750_000_000))
        stateChanges = []
        draftReadyCalls = []
        burnedVideoReadyCalls = []
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempRoot)
        super.tearDown()
    }

    // MARK: - 5.3 / 3.1 无声录屏不生成

    func testSilentRecordingDoesNotStartGeneration() async throws {
        coordinator = makeCoordinator()
        let record = makeRecording(audioMode: .none)
        try repository.save(record)

        coordinator.startGeneration(recordID: record.id)
        // 等待可能的后台任务（应立即结束）。
        try await Task.sleep(nanoseconds: 50_000_000)

        let state = coordinator.currentState(for: record.id)
        XCTAssertEqual(state.status, .none)
        XCTAssertEqual(transcriber.transcribeCallCount, 0)
    }

    func testScreenshotDoesNotStartGeneration() async throws {
        coordinator = makeCoordinator()
        let screenshot = MediaRecord(
            id: UUID().uuidString,
            mediaType: .screenshot,
            ocrText: "text",
            imagePath: "/tmp/shot.png",
            createdAt: clock.now,
            updatedAt: clock.now
        )
        try repository.save(screenshot)

        coordinator.startGeneration(recordID: screenshot.id)
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(coordinator.currentState(for: screenshot.id).status, .none)
        XCTAssertEqual(transcriber.transcribeCallCount, 0)
    }

    // MARK: - 3.6 生成成功：保存草稿 JSON、导出 SRT、状态 draftReady、不自动烧录

    func testGenerationSuccessSavesDraftAndSRTAndOpensEditor() async throws {
        coordinator = makeCoordinator()
        let record = makeRecording(audioMode: .microphone)
        try repository.save(record)
        transcriber.segments = [
            TimedSpeechSegment(startMS: 0, durationMS: 1_000, text: "你好"),
            TimedSpeechSegment(startMS: 1_000, durationMS: 1_000, text: "世界")
        ]

        coordinator.startGeneration(recordID: record.id)
        try await Task.sleep(nanoseconds: 80_000_000)

        let state = coordinator.currentState(for: record.id)
        XCTAssertEqual(state.status, .draftReady)
        XCTAssertNotNil(state.draftPath)
        XCTAssertNotNil(state.srtPath)
        XCTAssertEqual(draftReadyCalls, [record.id])

        let draft = try XCTUnwrap(try draftStore.load(mediaID: record.id))
        XCTAssertEqual(draft.segments.count, 2)
        XCTAssertEqual(draft.segments[0].text, "你好")

        let srt = try String(contentsOf: paths.recordingSubtitleSRTURL(forID: record.id), encoding: .utf8)
        XCTAssertTrue(srt.contains("00:00:00,000 --> 00:00:01,000"))

        // 未确认不得调用烧录服务。
        XCTAssertEqual(burner.burnCallCount, 0)
        // 原视频路径保持不变。
        let fetched = try XCTUnwrap(repository.record(id: record.id))
        XCTAssertEqual(fetched.videoPath, record.videoPath)
    }

    // MARK: - 3.7 生成失败：状态 failed，保存错误信息，原视频可用

    func testGenerationFailureSetsFailedAndKeepsOriginalUsable() async throws {
        coordinator = makeCoordinator()
        let record = makeRecording(audioMode: .microphone)
        try repository.save(record)
        transcriber.error = .speechPermissionDenied

        coordinator.startGeneration(recordID: record.id)
        try await Task.sleep(nanoseconds: 80_000_000)

        let state = coordinator.currentState(for: record.id)
        XCTAssertEqual(state.status, .failed)
        XCTAssertEqual(state.errorMessage, RecordingSubtitleTranscriptionError.speechPermissionDenied.errorDescription)
        // 原视频未被触碰。
        let fetched = try XCTUnwrap(repository.record(id: record.id))
        XCTAssertEqual(fetched.videoPath, record.videoPath)
        // 草稿未生成。
        XCTAssertNil(try draftStore.load(mediaID: record.id))
    }

    // MARK: - 3.8 取消生成：状态回到 none

    func testCancelGenerationRestoresNone() async throws {
        coordinator = makeCoordinator()
        let record = makeRecording(audioMode: .microphone)
        try repository.save(record)
        transcriber.shouldHang = true

        coordinator.startGeneration(recordID: record.id)
        // 等待 transcriber 开始（此时状态已是 generating）。
        while transcriber.started == false {
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTAssertEqual(coordinator.currentState(for: record.id).status, .generating)

        await coordinator.cancelGeneration(recordID: record.id)

        XCTAssertEqual(coordinator.currentState(for: record.id).status, .none)
        XCTAssertNil(try draftStore.load(mediaID: record.id))
    }

    // MARK: - 5.1 addSubtitle 按状态选择动作

    func testAddSubtitleForDraftReadyOpensEditor() async throws {
        coordinator = makeCoordinator()
        let record = makeRecording(audioMode: .microphone)
        try repository.save(record)
        // 直接构造 draftReady 状态。
        try repository.updateSubtitleState(
            id: record.id,
            state: RecordingSubtitleState(
                status: .draftReady,
                draftPath: paths.recordingSubtitleDraftURL(forID: record.id).path,
                srtPath: nil,
                subtitledVideoPath: nil,
                errorMessage: nil,
                updatedAt: clock.now
            ),
            updatedAt: clock.now
        )

        coordinator.addSubtitle(recordID: record.id)
        try await Task.sleep(nanoseconds: 30_000_000)

        XCTAssertEqual(draftReadyCalls, [record.id])
        XCTAssertEqual(transcriber.transcribeCallCount, 0)
    }

    // MARK: - 4.2 / 4.6 烧录成功：新 mp4，原视频不变

    func testBurnSuccessCreatesSubtitledVideoAndKeepsOriginal() async throws {
        coordinator = makeCoordinator()
        let record = makeRecording(audioMode: .microphone)
        try repository.save(record)
        try seedDraftReady(recordID: record.id, segments: [.init(startMS: 0, endMS: 1_000, text: "hi")])
        burner.outputWriter = { url in try Data([0]).write(to: url) }

        coordinator.startBurn(recordID: record.id)
        try await Task.sleep(nanoseconds: 80_000_000)

        let state = coordinator.currentState(for: record.id)
        XCTAssertEqual(state.status, .burned)
        XCTAssertEqual(state.subtitledVideoPath, paths.recordingSubtitledVideoURL(forID: record.id).path)
        let fetched = try XCTUnwrap(repository.record(id: record.id))
        XCTAssertEqual(fetched.videoPath, record.videoPath, "原视频路径必须保持不变")
        XCTAssertTrue(FileManager.default.fileExists(atPath: state.subtitledVideoPath ?? ""))
        XCTAssertEqual(burner.burnCallCount, 1)
        XCTAssertEqual(burnedVideoReadyCalls, [paths.recordingSubtitledVideoURL(forID: record.id)])
    }

    // MARK: - 4.7 烧录失败：保留草稿，状态 failed，半成品删除

    func testBurnFailureKeepsDraftAndSetsFailed() async throws {
        coordinator = makeCoordinator()
        let record = makeRecording(audioMode: .microphone)
        try repository.save(record)
        try seedDraftReady(recordID: record.id, segments: [.init(startMS: 0, endMS: 1_000, text: "hi")])
        burner.error = .exportFailed("导出失败")

        coordinator.startBurn(recordID: record.id)
        try await Task.sleep(nanoseconds: 80_000_000)

        let state = coordinator.currentState(for: record.id)
        XCTAssertEqual(state.status, .failed)
        XCTAssertNil(state.subtitledVideoPath)
        // 草稿保留，可重试。
        XCTAssertNotNil(try draftStore.load(mediaID: record.id))
        let fetched = try XCTUnwrap(repository.record(id: record.id))
        XCTAssertEqual(fetched.videoPath, record.videoPath)
    }

    // MARK: - 4.8 取消烧录：保留草稿，恢复 draftReady

    func testCancelBurnRestoresDraftReady() async throws {
        coordinator = makeCoordinator()
        let record = makeRecording(audioMode: .microphone)
        try repository.save(record)
        try seedDraftReady(recordID: record.id, segments: [.init(startMS: 0, endMS: 1_000, text: "hi")])
        burner.shouldHang = true

        coordinator.startBurn(recordID: record.id)
        while burner.started == false {
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTAssertEqual(coordinator.currentState(for: record.id).status, .burning)

        await coordinator.cancelBurn(recordID: record.id)

        let state = coordinator.currentState(for: record.id)
        XCTAssertEqual(state.status, .draftReady)
        XCTAssertNil(state.subtitledVideoPath)
        XCTAssertNotNil(try draftStore.load(mediaID: record.id))
    }

    // MARK: - 编辑保存草稿

    func testSaveDraftPersistsEditedText() async throws {
        coordinator = makeCoordinator()
        let record = makeRecording(audioMode: .microphone)
        try repository.save(record)
        try seedDraftReady(recordID: record.id, segments: [.init(id: "s1", startMS: 0, endMS: 1_000, text: "原")])

        var draft = try XCTUnwrap(try coordinator.loadDraft(recordID: record.id))
        draft.segments[0].text = "改后"
        try coordinator.saveDraft(draft)

        let reloaded = try XCTUnwrap(try coordinator.loadDraft(recordID: record.id))
        XCTAssertEqual(reloaded.segments[0].text, "改后")
    }

    // MARK: - Helpers

    private func makeCoordinator() -> RecordingSubtitleCoordinator {
        RecordingSubtitleCoordinator(
            repository: repository,
            draftStore: draftStore,
            transcriber: transcriber,
            burner: burner,
            paths: paths,
            clock: clock,
            onStateChange: { [weak self] id in self?.stateChanges.append(id) },
            onDraftReady: { [weak self] id in self?.draftReadyCalls.append(id) },
            onBurnedVideoReady: { [weak self] url in self?.burnedVideoReadyCalls.append(url) }
        )
    }

    private func seedDraftReady(recordID: String, segments: [RecordingSubtitleSegment]) throws {
        let draft = RecordingSubtitleDraft(
            mediaRecordID: recordID,
            sourceVideoPath: "/tmp/rec.mp4",
            segments: segments,
            createdAt: clock.now,
            updatedAt: clock.now
        )
        try draftStore.save(draft)
        try repository.updateSubtitleState(
            id: recordID,
            state: RecordingSubtitleState(
                status: .draftReady,
                draftPath: draftStore.draftURL(for: recordID).path,
                srtPath: paths.recordingSubtitleSRTURL(forID: recordID).path,
                subtitledVideoPath: nil,
                errorMessage: nil,
                updatedAt: clock.now
            ),
            updatedAt: clock.now
        )
    }

    private func makeRecording(audioMode: MediaAudioMode) -> MediaRecord {
        MediaRecord(
            id: UUID().uuidString,
            mediaType: .screenRecording,
            videoPath: "/tmp/rec-\(UUID().uuidString).mp4",
            durationMs: 3_000,
            width: 1280,
            height: 720,
            fileSizeBytes: 512,
            audioMode: audioMode,
            createdAt: clock.now,
            updatedAt: clock.now
        )
    }
}

// MARK: - Fakes

private final class FakeSubtitleRepository: MediaRecordRepository {
    private var records: [String: MediaRecord] = [:]
    private var subtitleStates: [String: RecordingSubtitleState] = [:]
    private(set) var deletedIDs: Set<String> = []

    func save(_ record: MediaRecord) throws {
        records[record.id] = record
        if record.subtitleStatus != .none || record.subtitleDraftPath != nil {
            subtitleStates[record.id] = RecordingSubtitleState(
                status: record.subtitleStatus,
                draftPath: record.subtitleDraftPath,
                srtPath: record.subtitleSrtPath,
                subtitledVideoPath: record.subtitledVideoPath,
                errorMessage: record.subtitleErrorMessage,
                updatedAt: record.subtitleUpdatedAt
            )
        }
    }

    func record(id: String) throws -> MediaRecord? {
        guard let base = records[id] else { return nil }
        let state = subtitleStates[id] ?? .none
        return base.withSubtitleState(state)
    }

    func page(limit: Int, offset: Int, filter: MediaRecordFilter, search: String?) throws -> MediaRecordPage {
        var all = records.values.compactMap { try? self.record(id: $0.id) }
        all = all.filter { $0.deletedAt == nil }
        return MediaRecordPage(records: Array(all.dropFirst(offset).prefix(limit)), totalCount: all.count)
    }

    func toggleFavorite(id: String, isFavorited: Bool, updatedAt: Date) throws {
        records[id]?.isFavorited = isFavorited
    }

    func updateSubtitleState(id: String, state: RecordingSubtitleState, updatedAt: Date) throws {
        subtitleStates[id] = state
        if let existing = records[id] {
            records[id] = existing.withSubtitleState(state)
        }
    }

    func softDelete(id: String, deletedAt: Date) throws {
        deletedIDs.insert(id)
    }

    func stats() throws -> MediaRecordStats {
        MediaRecordStats(totalMedia: records.count, todayMedia: 0, screenshotCount: 0, recordingCount: records.count)
    }
}

private final class FakeClock: AppClock, @unchecked Sendable {
    var now: Date
    init(now: Date) { self.now = now }
    func sleep(nanoseconds: UInt64) async throws {
        try await Task.sleep(nanoseconds: nanoseconds)
    }
}

private final class FakeTranscriber: SystemRecordingSubtitleTranscriber, @unchecked Sendable {
    var segments: [TimedSpeechSegment] = []
    var error: RecordingSubtitleTranscriptionError?
    var shouldHang = false
    private(set) var started = false
    private(set) var transcribeCallCount = 0

    func transcribe(videoURL: URL, audioMode: MediaAudioMode) async throws -> RecordingTranscriptionResult {
        started = true
        transcribeCallCount += 1
        if let error { throw error }
        if shouldHang {
            try await Task.sleep(nanoseconds: 5_000_000_000)
        }
        return RecordingTranscriptionResult(segments: segments.map {
            RecordingSubtitleSegment(startMS: $0.startMS, endMS: $0.startMS + $0.durationMS, text: $0.text)
        })
    }
}

private final class FakeBurner: RecordingSubtitleBurner, @unchecked Sendable {
    var error: RecordingSubtitleBurnError?
    var shouldHang = false
    var outputWriter: ((URL) throws -> Void)?
    private(set) var started = false
    private(set) var burnCallCount = 0

    func burn(sourceVideoURL: URL, draft: RecordingSubtitleDraft, outputURL: URL) async throws -> RecordingSubtitleBurnResult {
        started = true
        burnCallCount += 1
        if let error { throw error }
        if shouldHang {
            try await Task.sleep(nanoseconds: 5_000_000_000)
        }
        if let outputWriter {
            try outputWriter(outputURL)
        }
        return RecordingSubtitleBurnResult(outputURL: outputURL)
    }
}
