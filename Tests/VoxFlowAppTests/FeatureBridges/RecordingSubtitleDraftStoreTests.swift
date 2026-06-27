import XCTest
@testable import VoxFlowApp

final class RecordingSubtitleDraftStoreTests: XCTestCase {
    private var paths: ApplicationSupportPaths!
    private var store: RecordingSubtitleDraftStore!
    private var tempRoot: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoxFlowSubtitle-\(UUID().uuidString)", isDirectory: true)
        paths = ApplicationSupportPaths(applicationSupportDirectory: tempRoot)
        try paths.ensureDirectories()
        store = RecordingSubtitleDraftStore(paths: paths)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempRoot)
        super.tearDown()
    }

    // MARK: - 2.1 / 2.3 草稿 JSON 保存、读取、覆盖更新

    func testSaveAndLoadDraftRoundTrips() throws {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let draft = RecordingSubtitleDraft(
            mediaRecordID: "rec-1",
            sourceVideoPath: "/tmp/rec-1.mp4",
            segments: [
                RecordingSubtitleSegment(id: "s1", startMS: 0, endMS: 1_500, text: "第一句"),
                RecordingSubtitleSegment(id: "s2", startMS: 1_500, endMS: 3_000, text: "第二句")
            ],
            createdAt: now,
            updatedAt: now
        )

        try store.save(draft)

        let loaded = try XCTUnwrap(try store.load(mediaID: "rec-1"))
        XCTAssertEqual(loaded, draft)
        XCTAssertEqual(loaded.segments.count, 2)
    }

    func testOverwriteDraftReplacesPreviousContent() throws {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        var draft = RecordingSubtitleDraft(
            mediaRecordID: "rec-2",
            sourceVideoPath: "/tmp/rec-2.mp4",
            segments: [RecordingSubtitleSegment(id: "a", startMS: 0, endMS: 500, text: "旧")],
            createdAt: now,
            updatedAt: now
        )
        try store.save(draft)

        draft.segments = [RecordingSubtitleSegment(id: "b", startMS: 0, endMS: 1_000, text: "新内容")]
        draft.updatedAt = now.addingTimeInterval(60)
        try store.save(draft)

        let loaded = try XCTUnwrap(try store.load(mediaID: "rec-2"))
        XCTAssertEqual(loaded.segments.count, 1)
        XCTAssertEqual(loaded.segments.first?.text, "新内容")
        XCTAssertEqual(loaded.updatedAt, now.addingTimeInterval(60))
    }

    func testLoadMissingDraftReturnsNil() throws {
        XCTAssertNil(try store.load(mediaID: "missing"))
    }

    func testRemoveDraftIsIdempotentForMissingFile() throws {
        XCTAssertNoThrow(try store.remove(mediaID: "never-saved"))
    }

    func testRemoveDraftDeletesFile() throws {
        let now = Date()
        let draft = RecordingSubtitleDraft(
            mediaRecordID: "rec-3",
            sourceVideoPath: "/tmp/rec-3.mp4",
            segments: [RecordingSubtitleSegment(id: "x", startMS: 0, endMS: 1_000, text: "hi")],
            createdAt: now,
            updatedAt: now
        )
        try store.save(draft)
        XCTAssertNotNil(try store.load(mediaID: "rec-3"))

        try store.remove(mediaID: "rec-3")
        XCTAssertNil(try store.load(mediaID: "rec-3"))
    }

    func testSaveDraftEditsSegmentTextAndDeletesSegment() throws {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        var draft = RecordingSubtitleDraft(
            mediaRecordID: "rec-4",
            sourceVideoPath: "/tmp/rec-4.mp4",
            segments: [
                RecordingSubtitleSegment(id: "s1", startMS: 0, endMS: 1_000, text: "原文"),
                RecordingSubtitleSegment(id: "s2", startMS: 1_000, endMS: 2_000, text: "保留")
            ],
            createdAt: now,
            updatedAt: now
        )
        try store.save(draft)

        // 编辑第一段文本
        if let index = draft.segments.firstIndex(where: { $0.id == "s1" }) {
            draft.segments[index].text = "改后的文本"
        }
        // 删除第二段
        draft.segments.removeAll { $0.id == "s2" }
        draft.updatedAt = now.addingTimeInterval(30)
        try store.save(draft)

        let loaded = try XCTUnwrap(try store.load(mediaID: "rec-4"))
        XCTAssertEqual(loaded.segments.count, 1)
        XCTAssertEqual(loaded.segments.first?.text, "改后的文本")
    }

    // MARK: - 2.4 SRT 导出

    func testSRTExporterUsesHHMMSSmmmFormat() throws {
        let now = Date()
        let draft = RecordingSubtitleDraft(
            mediaRecordID: "rec-5",
            sourceVideoPath: "/tmp/rec-5.mp4",
            segments: [
                RecordingSubtitleSegment(id: "s1", startMS: 400, endMS: 2_100, text: "第一句"),
                RecordingSubtitleSegment(id: "s2", startMS: 2_100, endMS: 4_820, text: "第二句")
            ],
            createdAt: now,
            updatedAt: now
        )

        let srt = RecordingSubtitleSRTExporter.srt(for: draft)

        XCTAssertTrue(srt.contains("00:00:00,400 --> 00:00:02,100"))
        XCTAssertTrue(srt.contains("00:00:02,100 --> 00:00:04,820"))
        XCTAssertTrue(srt.contains("1\n00:00:00,400 --> 00:00:02,100\n第一句"))
        XCTAssertTrue(srt.contains("2\n00:00:02,100 --> 00:00:04,820\n第二句"))
    }

    func testSRTExporterWritesFile() throws {
        let now = Date()
        let draft = RecordingSubtitleDraft(
            mediaRecordID: "rec-6",
            sourceVideoPath: "/tmp/rec-6.mp4",
            segments: [RecordingSubtitleSegment(id: "s1", startMS: 0, endMS: 1_000, text: "字幕")],
            createdAt: now,
            updatedAt: now
        )

        let url = paths.recordingSubtitleSRTURL(forID: "rec-6")
        try RecordingSubtitleSRTExporter.export(draft: draft, to: url)

        let content = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(content.contains("00:00:00,000 --> 00:00:01,000"))
        XCTAssertTrue(content.contains("字幕"))
    }

    func testSRTExporterHandlesEmptySegments() {
        let now = Date()
        let draft = RecordingSubtitleDraft(
            mediaRecordID: "rec-7",
            sourceVideoPath: "/tmp/rec-7.mp4",
            segments: [],
            createdAt: now,
            updatedAt: now
        )
        let srt = RecordingSubtitleSRTExporter.srt(for: draft)
        XCTAssertEqual(srt, "")
    }
}
