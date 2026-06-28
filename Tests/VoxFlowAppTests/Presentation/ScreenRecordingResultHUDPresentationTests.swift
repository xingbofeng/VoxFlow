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

    func testHUDPreviewUsesPrimaryVideoPathAfterSubtitleBurnSucceeds() throws {
        let source = try String(
            contentsOf: Self.repositoryRoot()
                .appendingPathComponent("Sources/VoxFlowApp/Presentation/ScreenRecordingResultPanelController.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(
            source.contains("if let videoPath = displayRecord.primaryVideoPath"),
            "录屏完成 HUD 预览在 burned 状态必须优先播放带字幕视频。"
        )
        XCTAssertFalse(
            source.contains("if let videoPath = record.videoPath"),
            "HUD 预览不能继续固定读取原始 videoPath，否则烧录成功后看起来像没反应。"
        )
    }

    func testHUDActionsReloadLatestRecordBeforeResolvingFilePath() throws {
        let source = try String(
            contentsOf: Self.repositoryRoot()
                .appendingPathComponent("Sources/VoxFlowApp/Presentation/ScreenRecordingResultPanelController.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("private func currentRecord(fallback record: MediaRecord) -> MediaRecord"))
        XCTAssertTrue(source.contains("currentRecord(fallback: record)"))
        XCTAssertTrue(source.contains("let displayRecord = hudState.record ?? record"))
        XCTAssertTrue(source.contains("hudState.update(record: latestRecord, state:"))
    }

    func testHUDDoesNotAutoCopyFileWhenPresented() throws {
        let source = try String(
            contentsOf: Self.repositoryRoot()
                .appendingPathComponent("Sources/VoxFlowApp/Presentation/ScreenRecordingResultPanelController.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("initialDidCopyFile: false"))
        XCTAssertFalse(
            source.contains("let didCopyFile = copyFile(record)"),
            "录屏完成 HUD 初始状态应该显示复制按钮，不应该因为自动复制而显示勾勾。"
        )
    }

    func testHUDUsesNativeWindowDragHandleLikeScreenshotPanel() throws {
        let source = try String(
            contentsOf: Self.repositoryRoot()
                .appendingPathComponent("Sources/VoxFlowApp/Presentation/ScreenRecordingResultPanelController.swift"),
            encoding: .utf8
        )
        let sharedSource = try String(
            contentsOf: Self.repositoryRoot()
                .appendingPathComponent("Sources/VoxFlowApp/Presentation/TextResultPanelView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(sharedSource.contains("window?.performDrag(with: event)"))
        XCTAssertTrue(source.contains(".overlay(TextResultPanelDragHandle())"))
        XCTAssertTrue(source.contains("panel.isMovableByWindowBackground = true"))
        XCTAssertFalse(source.contains("DragGesture()"))
    }

    func testHUDActionsShowNativeTooltipsAndVisibleFeedback() throws {
        let source = try String(
            contentsOf: Self.repositoryRoot()
                .appendingPathComponent("Sources/VoxFlowApp/Presentation/ScreenRecordingResultPanelController.swift"),
            encoding: .utf8
        )

        XCTAssertFalse(source.contains("NativeTooltipView"))
        XCTAssertFalse(source.contains("NSViewRepresentable"))
        XCTAssertFalse(source.contains("Button(role:"))
        XCTAssertTrue(source.contains("Button(action: action)"))
        XCTAssertTrue(source.contains("private var feedbackText: String?"))
        XCTAssertTrue(source.contains("showFeedback("))
        XCTAssertTrue(source.contains("recording.feedback.revealed_in_finder"))
        XCTAssertTrue(source.contains("recording.feedback.file_not_found"))
        XCTAssertFalse(source.contains("NSAlert"))
    }

    func testDownloadUsesSavePanelInsteadOfDefaultDownloads() throws {
        let source = try String(
            contentsOf: Self.repositoryRoot()
                .appendingPathComponent("Sources/VoxFlowApp/Presentation/ScreenRecordingResultPanelController.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("let panel = NSSavePanel()"))
        XCTAssertTrue(source.contains("panel.nameFieldStringValue = url.lastPathComponent"))
        XCTAssertTrue(source.contains("guard panel.runModal() == .OK, let destination = panel.url else"))
        XCTAssertFalse(
            source.contains("FileManager.default.urls(for: .downloadsDirectory"),
            "下载按钮必须让用户选择保存位置，不能静默写入默认 Downloads。"
        )
    }

    func testRevealInFinderChecksCurrentFileBeforeOpeningFinder() throws {
        let source = try String(
            contentsOf: Self.repositoryRoot()
                .appendingPathComponent("Sources/VoxFlowApp/Presentation/ScreenRecordingResultPanelController.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("private func revealInFinder(_ record: MediaRecord)"))
        XCTAssertTrue(source.contains("private func existingFileURL(for record: MediaRecord) -> URL?"))
        XCTAssertTrue(source.contains("record.primaryFilePath"))
        XCTAssertTrue(source.contains("record.videoPath"))
        XCTAssertTrue(source.contains("NSWorkspace.shared.activateFileViewerSelecting([url])"))
    }

    func testRevealInFinderBringsFinderToForeground() throws {
        let source = try String(
            contentsOf: Self.repositoryRoot()
                .appendingPathComponent("Sources/VoxFlowApp/Presentation/ScreenRecordingResultPanelController.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("activateFinder()"))
        XCTAssertTrue(source.contains("bundleIdentifier == \"com.apple.finder\""))
        XCTAssertTrue(source.contains("NSAppleScript"))
        XCTAssertTrue(source.contains(".activateAllWindows"))
        XCTAssertFalse(source.contains(".activateIgnoringOtherApps"))
    }

    func testDeleteUsesInlineConfirmationBeforeDeletingFromNonActivatingHUD() throws {
        let source = try String(
            contentsOf: Self.repositoryRoot()
                .appendingPathComponent("Sources/VoxFlowApp/Presentation/ScreenRecordingResultPanelController.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("@State private var isDeleteConfirmationPending = false"))
        XCTAssertTrue(source.contains("showFeedback(L10n.localize(\"recording.feedback.delete_confirmation\""))
        XCTAssertTrue(source.contains("isDeleteConfirmationPending = true"))
        XCTAssertFalse(source.contains("runModal() == .alertFirstButtonReturn"))
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

    func testDeleteRemovesOriginalAndSubtitleFilesForBurnedRecordings() throws {
        let source = try String(
            contentsOf: Self.repositoryRoot()
                .appendingPathComponent("Sources/VoxFlowApp/Presentation/ScreenRecordingResultPanelController.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("private func filePathsToDelete(for record: MediaRecord) -> [String]"))
        XCTAssertTrue(source.contains("record.videoPath"))
        XCTAssertTrue(source.contains("record.subtitledVideoPath"))
        XCTAssertTrue(source.contains("record.subtitleDraftPath"))
        XCTAssertTrue(source.contains("record.subtitleSrtPath"))
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

    private static func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
