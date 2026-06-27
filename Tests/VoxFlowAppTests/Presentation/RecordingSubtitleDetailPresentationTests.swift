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

        XCTAssertEqual(presentation.sectionTitle, "字幕")
        XCTAssertEqual(presentation.statusText, "未添加")
        XCTAssertNil(presentation.errorMessage)
        XCTAssertEqual(presentation.actions, [
            RecordingSubtitleDetailActionPresentation(
                kind: .addSubtitle,
                title: "添加字幕",
                help: "添加字幕"
            )
        ])
    }

    func testSilentRecordingShowsDisabledAddSubtitleAction() throws {
        let presentation = try XCTUnwrap(
            RecordingSubtitleDetailPresentation.make(
                for: Self.recording(audioMode: .none, subtitleStatus: .none)
            )
        )

        XCTAssertEqual(presentation.statusText, "无麦克风音频")
        XCTAssertEqual(presentation.actions.first?.kind, .addSubtitle)
        XCTAssertEqual(presentation.actions.first?.title, "添加字幕")
        XCTAssertEqual(presentation.actions.first?.help, "这段录屏没有麦克风音频，无法添加字幕")
        XCTAssertFalse(presentation.actions.first?.isEnabled ?? true)
    }

    func testSubtitleDetailActionsReflectEveryStatus() throws {
        XCTAssertEqual(try actions(for: .generating), [
            RecordingSubtitleDetailActionPresentation(
                kind: .progress,
                title: "生成中…",
                help: "字幕生成中…",
                isEnabled: false,
                showsProgress: true
            )
        ])

        XCTAssertEqual(try actions(for: .draftReady).map(\.kind), [.openEditor, .burn])
        XCTAssertEqual(try actions(for: .draftReady).map(\.title), ["查看/编辑字幕", "烧录字幕"])

        XCTAssertEqual(try actions(for: .burning), [
            RecordingSubtitleDetailActionPresentation(
                kind: .progress,
                title: "烧录中…",
                help: "字幕烧录中…",
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
            "打开带字幕视频",
            "查看原视频",
            "查看/编辑字幕"
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
        XCTAssertEqual(failed.statusText, "失败")
        XCTAssertEqual(failed.errorMessage, "语音识别失败")
        XCTAssertEqual(failed.actions.map(\.kind), [.retry])
        XCTAssertEqual(failed.actions.map(\.title), ["重试"])
    }

    func testBurnedRecordingUsesSubtitledVideoAsPrimaryPlaybackSource() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let detailSource = try String(
            contentsOf: root.appendingPathComponent("Sources/VoxFlowApp/Views/ScreenshotRecordDetailView.swift"),
            encoding: .utf8
        )
        let viewModelSource = try String(
            contentsOf: root.appendingPathComponent("Sources/VoxFlowApp/ViewModels/ScreenshotRecordViewModel.swift"),
            encoding: .utf8
        )
        let resultHUDSource = try String(
            contentsOf: root.appendingPathComponent("Sources/VoxFlowApp/Presentation/ScreenRecordingResultPanelController.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(
            detailSource.contains("record.primaryVideoPath"),
            "录屏详情页主预览必须优先展示带字幕视频，而不是继续播放原视频。"
        )
        XCTAssertTrue(
            viewModelSource.contains("record.primaryFilePath"),
            "详情页底部打开/复制/Finder 主动作必须优先指向带字幕视频。"
        )
        XCTAssertTrue(
            resultHUDSource.contains("record.primaryFilePath"),
            "录屏完成 HUD 的主文件动作必须优先指向带字幕视频。"
        )
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
