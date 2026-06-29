import XCTest
@testable import VoxFlowApp

final class RecordingSubtitleEditorPresentationTests: XCTestCase {
    func testEditorPresentationContainsRequiredPreviewSegmentsStyleAndActions() {
        let draft = RecordingSubtitleDraft(
            mediaRecordID: "recording-1",
            sourceVideoPath: "/tmp/recording.mp4",
            segments: [
                RecordingSubtitleSegment(id: "s1", startMS: 400, endMS: 2_100, text: "这里是第一句字幕"),
                RecordingSubtitleSegment(id: "s2", startMS: 2_100, endMS: 4_800, text: "这里是第二句字幕")
            ],
            createdAt: Self.now,
            updatedAt: Self.now
        )

        let presentation = RecordingSubtitleEditorPresentation.make(draft: draft)

        XCTAssertEqual(presentation.title, L10n.localize("subtitle.editor.title_add", comment: ""))
        XCTAssertEqual(presentation.videoPath, "/tmp/recording.mp4")
        XCTAssertEqual(presentation.segmentListTitle, L10n.localize("subtitle.editor.segment_list_title", comment: ""))
        XCTAssertEqual(presentation.segmentCountText, String(format: L10n.localize("subtitle.editor.segment_count_format", comment: ""), 2))
        XCTAssertEqual(presentation.segments.map(\.timeRangeText), [
            "00:00.4 - 00:02.1",
            "00:02.1 - 00:04.8"
        ])
        XCTAssertEqual(presentation.segments.map(\.text), ["这里是第一句字幕", "这里是第二句字幕"])
        XCTAssertTrue(presentation.segments.allSatisfy(\.isTextEditable))
        XCTAssertTrue(presentation.segments.allSatisfy(\.canDelete))
        XCTAssertTrue(presentation.segments.allSatisfy { !$0.canEditTiming })
        XCTAssertEqual(presentation.styleSummary, L10n.localize("subtitle.style.summary", comment: ""))
        XCTAssertEqual(presentation.footerActions.map(\.kind), [.cancel, .saveDraft, .burn])
        XCTAssertEqual(presentation.footerActions.map(\.title), [
            L10n.localize("subtitle.editor.action_cancel", comment: ""),
            L10n.localize("subtitle.editor.action_save_draft", comment: ""),
            L10n.localize("subtitle.editor.action_burn", comment: ""),
        ])
    }

    func testEditorPresentationDoesNotExposeV1OutOfScopeControls() {
        let presentation = RecordingSubtitleEditorPresentation.make(
            draft: RecordingSubtitleDraft(
                mediaRecordID: "recording-1",
                sourceVideoPath: "/tmp/recording.mp4",
                segments: [],
                createdAt: Self.now,
                updatedAt: Self.now
            )
        )

        XCTAssertFalse(presentation.allowsTimelineDragging)
        XCTAssertFalse(presentation.allowsMergingSegments)
        XCTAssertFalse(presentation.allowsSplittingSegments)
        XCTAssertFalse(presentation.allowsStyleEditing)
    }

    private static let now = Date(timeIntervalSince1970: 1_750_000_000)
}
