import XCTest

final class ScreenshotRecordPresentationTests: XCTestCase {
    func testDetailActionsUseCompactIconToolbarAndOfferImageCopy() throws {
        let source = try String(
            contentsOf: Self.repositoryRoot()
                .appendingPathComponent("Sources/VoxFlowApp/Views/ScreenshotRecordDetailView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("recordActionIcon("))
        XCTAssertTrue(source.contains("viewModel.copyImage(id: record.id)"))
        let actionIconHelper = try XCTUnwrap(
            source.range(
                of: #"private func recordActionIcon\([\s\S]*?\n    private func formatDuration"#,
                options: .regularExpression
            ).map { String(source[$0]) }
        )
        XCTAssertTrue(actionIconHelper.contains(".buttonStyle(.plain)"))
        XCTAssertFalse(actionIconHelper.contains(".buttonStyle(.bordered)"))
        XCTAssertFalse(source.contains("Label(\"复制文字\""))
    }

    func testRecordCardsContainImagesWithoutCroppingAndCanCopyImages() throws {
        let source = try String(
            contentsOf: Self.repositoryRoot()
                .appendingPathComponent("Sources/VoxFlowApp/Views/ScreenshotRecordView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains(".scaledToFit()"))
        XCTAssertFalse(source.contains(".scaledToFill()"))
        XCTAssertTrue(source.contains("viewModel.copyImage(id: record.id)"))
        XCTAssertTrue(source.contains("help: L10n.localize(\"screenshot.record.action.copy_image_help\""))
    }

    func testRecordImageViewportsStayFixedForWideAndTallScreenshots() throws {
        let listSource = try String(
            contentsOf: Self.repositoryRoot()
                .appendingPathComponent("Sources/VoxFlowApp/Views/ScreenshotRecordView.swift"),
            encoding: .utf8
        )
        let detailSource = try String(
            contentsOf: Self.repositoryRoot()
                .appendingPathComponent("Sources/VoxFlowApp/Views/ScreenshotRecordDetailView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(listSource.contains("private let thumbnailHeight: CGFloat = 150"))
        XCTAssertTrue(listSource.contains("private let contentHeight: CGFloat = 132"))
        XCTAssertTrue(listSource.contains(".frame(height: thumbnailHeight)"))
        XCTAssertTrue(listSource.contains(".frame(height: thumbnailHeight + contentHeight)"))
        XCTAssertTrue(listSource.contains(".frame(height: contentHeight, alignment: .top)"))
        XCTAssertTrue(listSource.contains(".clipped()"))

        XCTAssertTrue(detailSource.contains("GeometryReader"))
        XCTAssertTrue(detailSource.contains("ScrollView(.vertical)"))
        XCTAssertTrue(detailSource.contains(".frame(width: proxy.size.width, height: proxy.size.height)"))
        XCTAssertTrue(detailSource.contains(".clipped()"))
    }

    func testRecognizedTextScrollAreaUsesRemainingDetailHeight() throws {
        let source = try String(
            contentsOf: Self.repositoryRoot()
                .appendingPathComponent("Sources/VoxFlowApp/Views/ScreenshotRecordDetailView.swift"),
            encoding: .utf8
        )

        XCTAssertFalse(source.contains(".frame(maxHeight: 120)"))
        XCTAssertTrue(source.contains("ocrSection"))
        XCTAssertTrue(source.contains(".layoutPriority(1)"))
        XCTAssertTrue(source.contains(".frame(maxHeight: .infinity, alignment: .top)"))
    }

    func testScreenshotTabIsUserFacingMultimediaWithMediaFiltersAndStats() throws {
        let root = Self.repositoryRoot()
        let routeSource = try String(
            contentsOf: root.appendingPathComponent("Sources/VoxFlowApp/FeatureBridges/NavigationRoute.swift"),
            encoding: .utf8
        )
        let viewSource = try String(
            contentsOf: root.appendingPathComponent("Sources/VoxFlowApp/Views/ScreenshotRecordView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(routeSource.contains("case .screenshotRecord: return L10n.localize(\"navigation.route.screenshot_record\""))
        XCTAssertTrue(viewSource.contains("Label(L10n.localize(\"screenshot.record.header_title\""))
        XCTAssertTrue(viewSource.contains("title: L10n.localize(\"screenshot.record.stats.total_media\""))
        XCTAssertTrue(viewSource.contains("title: L10n.localize(\"screenshot.record.stats.today_media\""))
        XCTAssertTrue(viewSource.contains("title: L10n.localize(\"screenshot.record.stats.screenshot\""))
        XCTAssertTrue(viewSource.contains("title: L10n.localize(\"screenshot.record.stats.screen_recording\""))
        XCTAssertTrue(viewSource.contains("ForEach(MediaRecordFilter.allCases"))
        XCTAssertTrue(viewSource.contains("viewModel.selectedFilter"))
        XCTAssertFalse(viewSource.contains("Picker(\"\", selection: Binding("))
    }

    func testRecordingCardsShowVideoMetadataAndFileActions() throws {
        let root = Self.repositoryRoot()
        let viewSource = try String(
            contentsOf: root.appendingPathComponent("Sources/VoxFlowApp/Views/ScreenshotRecordView.swift"),
            encoding: .utf8
        )
        let viewModelSource = try String(
            contentsOf: root.appendingPathComponent("Sources/VoxFlowApp/ViewModels/ScreenshotRecordViewModel.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(viewSource.contains("record.mediaType == .screenRecording"))
        XCTAssertTrue(viewSource.contains("viewModel.loadVideoThumbnail(for: record)"))
        XCTAssertTrue(viewSource.contains("video.fill"))
        XCTAssertTrue(viewSource.contains("formatDuration(record.durationMs)"))
        XCTAssertTrue(viewSource.contains("formatResolution(record.width, record.height)"))
        XCTAssertTrue(viewSource.contains("formatFileSize(record.fileSizeBytes)"))
        XCTAssertTrue(viewSource.contains("audioModeTitle(record.audioMode)"))
        XCTAssertTrue(viewSource.contains("viewModel.openFile(id: record.id)"))
        XCTAssertTrue(viewSource.contains("viewModel.copyFile(id: record.id)"))
        XCTAssertTrue(viewSource.contains("viewModel.revealInFinder(id: record.id)"))
        XCTAssertTrue(viewModelSource.contains("func loadVideoThumbnail(for record: MediaRecord) -> NSImage?"))
        XCTAssertTrue(viewModelSource.contains("func openFile(id: String)"))
        XCTAssertTrue(viewModelSource.contains("func copyFile(id: String)"))
        XCTAssertTrue(viewModelSource.contains("func revealInFinder(id: String)"))
    }

    func testMediaVideoPlayerWrapsAVPlayerViewAndReleasesPlayerOnDisappear() throws {
        let source = try String(
            contentsOf: Self.repositoryRoot()
                .appendingPathComponent("Sources/VoxFlowApp/Views/MediaVideoPlayerView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("import AVKit"))
        XCTAssertTrue(source.contains("NSViewRepresentable"))
        XCTAssertTrue(source.contains("AVPlayerView"))
        XCTAssertTrue(source.contains("playerView.controlsStyle = .default"))
        XCTAssertTrue(source.contains("static func dismantleNSView"))
        XCTAssertTrue(source.contains("nsView.player?.pause()"))
        XCTAssertTrue(source.contains("nsView.player = nil"))
    }

    func testMultimediaDetailBranchesToNativeVideoPlaybackForRecordings() throws {
        let source = try String(
            contentsOf: Self.repositoryRoot()
                .appendingPathComponent("Sources/VoxFlowApp/Views/ScreenshotRecordDetailView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("record.mediaType == .screenRecording"))
        XCTAssertTrue(source.contains("MediaVideoPlayerView(url: URL(fileURLWithPath: videoPath))"))
        XCTAssertTrue(source.contains("screenshot.record.detail.header_screen_recording"))
        XCTAssertTrue(source.contains("screenshot.record.detail.meta_label_duration"))
        XCTAssertTrue(source.contains("screenshot.record.detail.meta_label_resolution"))
        XCTAssertTrue(source.contains("viewModel.openFile(id: record.id)"))
        XCTAssertTrue(source.contains("viewModel.copyFile(id: record.id)"))
        XCTAssertTrue(source.contains("viewModel.revealInFinder(id: record.id)"))
    }

    func testSavedRecordingResultHUDUsesCompactVideoPreviewAndFileActions() throws {
        let root = Self.repositoryRoot()
        let source = try String(
            contentsOf: root.appendingPathComponent("Sources/VoxFlowApp/Presentation/ScreenRecordingResultPanelController.swift"),
            encoding: .utf8
        )
        let appDelegate = try String(
            contentsOf: root.appendingPathComponent("Sources/VoxFlowApp/App/AppDelegate.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("final class ScreenRecordingResultPanelController"))
        XCTAssertTrue(source.contains("MediaVideoPlayerView(url: URL(fileURLWithPath: videoPath))"))
        XCTAssertFalse(source.contains("let didCopyFile = copyFile(record)"))
        XCTAssertTrue(source.contains("initialDidCopyFile: false"))
        XCTAssertTrue(source.contains("ScreenRecordingResultHUDPresentation.actions("))
        XCTAssertTrue(source.contains("kind: .open"))
        XCTAssertTrue(source.contains("systemImage: \"arrow.up.right.square\""))
        XCTAssertTrue(source.contains("didCopyFile ? L10n.localize(\"recording.hud.action_copy_done\""))
        XCTAssertTrue(source.contains("resultActionButton("))
        XCTAssertTrue(source.contains("didDownloadFile ? L10n.localize(\"recording.hud.action_download_done\""))
        XCTAssertTrue(source.contains("systemImage: didDownloadFile ? \"checkmark\" : \"square.and.arrow.down\""))
        XCTAssertTrue(source.contains("private func download(_ record: MediaRecord)"))
        XCTAssertTrue(source.contains("let panel = NSSavePanel()"))
        XCTAssertTrue(source.contains("panel.nameFieldStringValue = url.lastPathComponent"))
        XCTAssertTrue(source.contains("kind: .revealInFinder"))
        XCTAssertTrue(source.contains("systemImage: \"folder\""))
        XCTAssertTrue(source.contains("kind: .delete"))
        XCTAssertTrue(source.contains("systemImage: isDeleteConfirmationPending ? \"trash.fill\" : \"trash\""))
        XCTAssertTrue(source.contains("ForEach(actionPresentations)"))
        XCTAssertTrue(source.contains(".labelStyle(.iconOnly)"))
        XCTAssertTrue(source.contains("width: CGFloat = 42"))
        XCTAssertTrue(source.contains("height: CGFloat = 32"))
        XCTAssertFalse(source.contains(".labelStyle(.titleAndIcon)"))
        XCTAssertFalse(source.contains("Image(systemName: \"play.circle\")"))
        XCTAssertTrue(appDelegate.contains("screenRecordingResultPanelController.present(record: record)"))
    }

    func testDetailRecognizedTextScrollAreaCanUseRemainingInfoPanelHeight() throws {
        let source = try String(
            contentsOf: Self.repositoryRoot()
                .appendingPathComponent("Sources/VoxFlowApp/Views/ScreenshotRecordDetailView.swift"),
            encoding: .utf8
        )

        XCTAssertFalse(source.contains(".frame(maxHeight: 120)"))
        XCTAssertTrue(source.contains("ocrSection"))
        XCTAssertTrue(source.contains(".layoutPriority(1)"))
        XCTAssertTrue(source.contains(".frame(maxHeight: .infinity"))
    }

    private static func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
