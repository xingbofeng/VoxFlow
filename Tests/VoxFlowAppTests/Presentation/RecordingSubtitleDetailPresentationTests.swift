import XCTest
@testable import VoxFlowApp

final class RecordingSubtitleDetailPresentationTests: XCTestCase {
    func testScreenshotDoesNotShowRecordingSubtitleSection() {
        let screenshot = MediaRecord(
            id: "shot",
            mediaType: .screenshot,
            ocrText: "text",
            imagePath: "/tmp/shot.png",
            createdAt: Self.now,
            updatedAt: Self.now
        )

        XCTAssertNil(RecordingSubtitleDetailPresentation.make(for: screenshot))
    }

    func testMicrophoneRecordingShowsAddSubtitleActionWhenNone() throws {
        let presentation = try XCTUnwrap(
            RecordingSubtitleDetailPresentation.make(
                for: Self.recording(audioMode: .microphone, subtitleStatus: .none)
            )
        )

        XCTAssertEqual(presentation.sectionTitle, L10n.localize("screenshot.record.detail.subtitle_section_title", comment: ""))
        XCTAssertEqual(presentation.statusText, L10n.localize("subtitle.status.none", comment: ""))
        XCTAssertNil(presentation.errorMessage)
        XCTAssertEqual(presentation.actions, [
            RecordingSubtitleDetailActionPresentation(
                kind: .addSubtitle,
                title: L10n.localize("screenshot.record.detail.subtitle_action_add", comment: ""),
                help: L10n.localize("screenshot.record.detail.subtitle_action_add_help", comment: "")
            )
        ])
    }

    func testSilentRecordingShowsDisabledAddSubtitleAction() throws {
        let presentation = try XCTUnwrap(
            RecordingSubtitleDetailPresentation.make(
                for: Self.recording(audioMode: .none, subtitleStatus: .none)
            )
        )

        XCTAssertEqual(presentation.statusText, L10n.localize("screenshot.record.detail.subtitle_status_no_microphone", comment: ""))
        XCTAssertEqual(presentation.actions.first?.kind, .addSubtitle)
        XCTAssertEqual(presentation.actions.first?.title, L10n.localize("screenshot.record.detail.subtitle_action_add", comment: ""))
        XCTAssertEqual(presentation.actions.first?.help, L10n.localize("screenshot.record.detail.subtitle_action_add_no_audio_help", comment: ""))
        XCTAssertFalse(presentation.actions.first?.isEnabled ?? true)
    }

    func testSubtitleDetailActionsReflectEveryStatus() throws {
        XCTAssertEqual(try actions(for: .generating), [
            RecordingSubtitleDetailActionPresentation(
                kind: .progress,
                title: L10n.localize("screenshot.record.detail.subtitle_action_generating", comment: ""),
                help: L10n.localize("screenshot.record.detail.subtitle_action_generating_help", comment: ""),
                isEnabled: false,
                showsProgress: true
            )
        ])

        XCTAssertEqual(try actions(for: .draftReady).map(\.kind), [.openEditor, .burn])
        XCTAssertEqual(try actions(for: .draftReady).map(\.title), [
            L10n.localize("screenshot.record.detail.subtitle_action_view_edit", comment: ""),
            L10n.localize("screenshot.record.detail.subtitle_action_burn", comment: ""),
        ])

        XCTAssertEqual(try actions(for: .burning), [
            RecordingSubtitleDetailActionPresentation(
                kind: .progress,
                title: L10n.localize("screenshot.record.detail.subtitle_action_burning", comment: ""),
                help: L10n.localize("screenshot.record.detail.subtitle_action_burning_help", comment: ""),
                isEnabled: false,
                showsProgress: true
            )
        ])

        XCTAssertEqual(try actions(for: .burned).map(\.kind), [
            .openSubtitledVideo,
            .openOriginalVideo,
            .openEditor
        ])
        XCTAssertEqual(try actions(for: .burned).map(\.title), [
            L10n.localize("screenshot.record.detail.subtitle_action_open_subtitled_video", comment: ""),
            L10n.localize("screenshot.record.detail.subtitle_action_open_original_video", comment: ""),
            L10n.localize("screenshot.record.detail.subtitle_action_view_edit", comment: ""),
        ])

        let failed = try XCTUnwrap(
            RecordingSubtitleDetailPresentation.make(
                for: Self.recording(
                    audioMode: .microphone,
                    subtitleStatus: .failed,
                    subtitleErrorMessage: "语音识别失败"
                )
            )
        )
        XCTAssertEqual(failed.statusText, L10n.localize("subtitle.status.failed", comment: ""))
        XCTAssertEqual(failed.errorMessage, "语音识别失败")
        XCTAssertEqual(failed.actions.map(\.kind), [.retry])
        XCTAssertEqual(failed.actions.map(\.title), [L10n.localize("screenshot.record.detail.subtitle_action_retry", comment: "")])
    }

    func testMediaRecordPrimaryVideoPathPrefersBurnedSubtitleVideoOnlyAfterBurnSuccess() {
        let burned = Self.recording(
            audioMode: .microphone,
            subtitleStatus: .burned,
            subtitledVideoPath: "/tmp/subtitled.mp4"
        )
        let draftReady = Self.recording(
            audioMode: .microphone,
            subtitleStatus: .draftReady,
            subtitledVideoPath: "/tmp/subtitled.mp4"
        )

        XCTAssertEqual(burned.primaryVideoPath, "/tmp/subtitled.mp4")
        XCTAssertEqual(burned.primaryFilePath, "/tmp/subtitled.mp4")
        XCTAssertEqual(draftReady.primaryVideoPath, "/tmp/recording.mp4")
        XCTAssertEqual(draftReady.primaryFilePath, "/tmp/recording.mp4")
    }

    private func actions(for status: RecordingSubtitleStatus) throws -> [RecordingSubtitleDetailActionPresentation] {
        try XCTUnwrap(
            RecordingSubtitleDetailPresentation.make(
                for: Self.recording(audioMode: .microphone, subtitleStatus: status)
            )
        )
        .actions
    }

    private static func recording(
        audioMode: MediaAudioMode,
        subtitleStatus: RecordingSubtitleStatus,
        subtitleErrorMessage: String? = nil,
        subtitledVideoPath: String? = nil
    ) -> MediaRecord {
        MediaRecord(
            id: UUID().uuidString,
            mediaType: .screenRecording,
            videoPath: "/tmp/recording.mp4",
            durationMs: 5_000,
            width: 752,
            height: 704,
            fileSizeBytes: 595_000,
            audioMode: audioMode,
            subtitleStatus: subtitleStatus,
            subtitledVideoPath: subtitledVideoPath,
            subtitleErrorMessage: subtitleErrorMessage,
            createdAt: now,
            updatedAt: now
        )
    }

    private static let now = Date(timeIntervalSince1970: 1_750_000_000)
}
