import XCTest
@testable import VoxFlowApp

final class ScreenRecordingResultHUDPresentationTests: XCTestCase {
    func testBottomActionsAreFixedSizeIconOnlyAndExposeHelp() {
        let actions = ScreenRecordingResultHUDPresentation.actions(
            for: Self.makeRecording(audioMode: .microphone),
            subtitleState: .none,
            didCopyFile: false,
            didDownloadFile: false
        )

        XCTAssertEqual(actions.map(\.kind), [
            .open,
            .copyFile,
            .download,
            .revealInFinder,
            .delete,
            .subtitle
        ])
        XCTAssertTrue(actions.allSatisfy(\.isIconOnly))
        XCTAssertTrue(actions.allSatisfy { $0.width == 42 })
        XCTAssertTrue(actions.allSatisfy { $0.height == 32 })
        XCTAssertTrue(actions.allSatisfy { !$0.help.isEmpty })
        XCTAssertFalse(actions.contains { $0.allowsVisibleTitle })
    }

    func testSubtitleActionIsEnabledOnlyForMicrophoneRecordings() {
        let microphoneAction = subtitleAction(for: Self.makeRecording(audioMode: .microphone), state: .none)

        XCTAssertEqual(microphoneAction.accessibilityTitle, "添加字幕")
        XCTAssertEqual(microphoneAction.systemImage, "captions.bubble")
        XCTAssertEqual(microphoneAction.help, "添加字幕")
        XCTAssertTrue(microphoneAction.isEnabled)
        XCTAssertFalse(microphoneAction.showsSpinner)

        let silentAction = subtitleAction(for: Self.makeRecording(audioMode: .none), state: .none)

        XCTAssertEqual(silentAction.accessibilityTitle, "添加字幕")
        XCTAssertEqual(silentAction.systemImage, "captions.bubble")
        XCTAssertEqual(silentAction.help, "这段录屏没有麦克风音频，无法添加字幕")
        XCTAssertFalse(silentAction.isEnabled)
        XCTAssertFalse(silentAction.showsSpinner)
    }

    func testSubtitleActionReflectsEverySubtitleState() {
        XCTAssertEqual(subtitleAction(state: .generating).help, "字幕生成中…")
        XCTAssertFalse(subtitleAction(state: .generating).isEnabled)
        XCTAssertTrue(subtitleAction(state: .generating).showsSpinner)

        XCTAssertEqual(subtitleAction(state: .draftReady).help, "查看/编辑字幕")
        XCTAssertTrue(subtitleAction(state: .draftReady).isEnabled)

        XCTAssertEqual(subtitleAction(state: .burning).help, "字幕烧录中…")
        XCTAssertFalse(subtitleAction(state: .burning).isEnabled)
        XCTAssertTrue(subtitleAction(state: .burning).showsSpinner)

        XCTAssertEqual(subtitleAction(state: .burned).help, "打开带字幕视频")
        XCTAssertEqual(subtitleAction(state: .burned).systemImage, "captions.bubble.fill")
        XCTAssertTrue(subtitleAction(state: .burned).isEnabled)

        XCTAssertEqual(subtitleAction(state: .failed).help, "重新生成字幕")
        XCTAssertEqual(subtitleAction(state: .failed).systemImage, "arrow.clockwise")
        XCTAssertTrue(subtitleAction(state: .failed).isEnabled)
    }

    func testDeleteActionShowsPendingConfirmationStateOnFirstClick() {
        let actions = ScreenRecordingResultHUDPresentation.actions(
            for: Self.makeRecording(audioMode: .microphone),
            subtitleState: .none,
            didCopyFile: false,
            didDownloadFile: false,
            isDeleteConfirmationPending: true
        )
        let deleteAction = actions.first { $0.kind == .delete }

        XCTAssertEqual(deleteAction?.accessibilityTitle, L10n.localize("recording.hud.action_delete_confirm", comment: ""))
        XCTAssertEqual(deleteAction?.systemImage, "trash.fill")
        XCTAssertEqual(deleteAction?.help, L10n.localize("recording.hud.action_delete_confirm_help", comment: ""))
        XCTAssertTrue(deleteAction?.isDestructive == true)
    }

    private func subtitleAction(
        state: RecordingSubtitleStatus
    ) -> ScreenRecordingResultHUDActionPresentation {
        subtitleAction(for: Self.makeRecording(audioMode: .microphone), state: state)
    }

    private func subtitleAction(
        for record: MediaRecord,
        state: RecordingSubtitleStatus
    ) -> ScreenRecordingResultHUDActionPresentation {
        ScreenRecordingResultHUDPresentation.actions(
            for: record,
            subtitleState: RecordingSubtitleState(
                status: state,
                draftPath: nil,
                srtPath: nil,
                subtitledVideoPath: nil,
                errorMessage: nil,
                updatedAt: nil
            ),
            didCopyFile: false,
            didDownloadFile: false
        )
        .first { $0.kind == .subtitle }!
    }

    private static func makeRecording(audioMode: MediaAudioMode) -> MediaRecord {
        MediaRecord(
            id: UUID().uuidString,
            mediaType: .screenRecording,
            videoPath: "/tmp/recording.mp4",
            durationMs: 5_000,
            width: 752,
            height: 704,
            fileSizeBytes: 595_000,
            audioMode: audioMode,
            createdAt: Date(timeIntervalSince1970: 1_750_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_750_000_000)
        )
    }

}
