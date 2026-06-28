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

    func testEditorBurnRequiresConfirmationAndPreservesOriginalCopy() throws {
        let source = try String(
            contentsOf: Self.repositoryRoot()
                .appendingPathComponent("Sources/VoxFlowApp/Views/RecordingSubtitleEditorView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains(".alert(L10n.localize(\"subtitle.editor.alert_generate_title\""))
        XCTAssertTrue(source.contains("Button(L10n.localize(\"subtitle.editor.alert_cancel\""))
        XCTAssertTrue(source.contains("Button(L10n.localize(\"subtitle.editor.alert_generate_confirm\""))
        XCTAssertTrue(source.contains("Text(L10n.localize(\"subtitle.editor.alert_generate_message\""))
        XCTAssertTrue(source.contains("private func confirmBurn()"))
        XCTAssertTrue(source.contains("saveDraft(showFeedback: false)"))
        XCTAssertTrue(source.contains("coordinator.startBurn(recordID: recordID)"))
        XCTAssertTrue(source.contains("Button(action.title)"))
        XCTAssertFalse(source.contains("Button(\"合并\""))
        XCTAssertFalse(source.contains("Button(\"拆分\""))
        XCTAssertFalse(source.contains("Button(\"拖拽\""))
        XCTAssertFalse(source.contains("Button(\"修改样式\""))
    }

    func testEditorWindowIsCenteredOnPresentingScreenInsteadOfDefaultMainScreen() throws {
        let source = try String(
            contentsOf: Self.repositoryRoot()
                .appendingPathComponent("Sources/VoxFlowApp/Presentation/RecordingSubtitleEditorWindowController.swift"),
            encoding: .utf8
        )
        let appDelegate = try String(
            contentsOf: Self.repositoryRoot()
                .appendingPathComponent("Sources/VoxFlowApp/App/AppDelegate.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("func present(recordID: String, preferredScreen: NSScreen?"))
        XCTAssertTrue(source.contains("private static func centerFrame"))
        XCTAssertTrue(source.contains("screen.visibleFrame"))
        XCTAssertFalse(source.contains("panel.center()"))
        XCTAssertTrue(appDelegate.contains("subtitleEditorWindowController.present("))
        XCTAssertTrue(appDelegate.contains("recordID: recordID,"))
        XCTAssertTrue(appDelegate.contains("preferredScreen: screenRecordingResultPanelController.presentationScreen ?? NSApp.keyWindow?.screen"))
    }

    func testEditorShowsFeedbackAfterSavingDraft() throws {
        let source = try String(
            contentsOf: Self.repositoryRoot()
                .appendingPathComponent("Sources/VoxFlowApp/Views/RecordingSubtitleEditorView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("@State private var saveDraftFeedbackMessage: String?"))
        XCTAssertTrue(source.contains("saveDraftFeedbackMessage = L10n.localize(\"subtitle.editor.feedback_draft_saved\""))
        XCTAssertTrue(source.contains("Text(saveDraftFeedbackMessage)"))
    }

    func testBurnSuccessOpensGeneratedSubtitledVideo() throws {
        let coordinator = try String(
            contentsOf: Self.repositoryRoot()
                .appendingPathComponent("Sources/VoxFlowApp/FeatureBridges/RecordingSubtitleCoordinator.swift"),
            encoding: .utf8
        )
        let appDelegate = try String(
            contentsOf: Self.repositoryRoot()
                .appendingPathComponent("Sources/VoxFlowApp/App/AppDelegate.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(coordinator.contains("onBurnedVideoReady: @escaping (URL) -> Void"))
        XCTAssertTrue(coordinator.contains("onBurnedVideoReady(result.outputURL)"))
        XCTAssertTrue(appDelegate.contains("onBurnedVideoReady: { url in"))
        XCTAssertTrue(appDelegate.contains("NSWorkspace.shared.open(url)"))
    }

    private static func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private static let now = Date(timeIntervalSince1970: 1_750_000_000)
}
