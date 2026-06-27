import XCTest

final class ScreenshotOCRResultPanelPresentationTests: XCTestCase {
    func testPanelUsesNativeWindowDraggingInsteadOfIncrementalSwiftUIDragGesture() throws {
        let root = Self.repositoryRoot()
        let source = try String(
            contentsOf: root.appendingPathComponent("Sources/VoxFlowApp/Presentation/ScreenshotOCRResultPanelController.swift"),
            encoding: .utf8
        )
        let sharedSource = try String(
            contentsOf: root.appendingPathComponent("Sources/VoxFlowApp/Presentation/TextResultPanelView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(sharedSource.contains("window?.performDrag(with: event)"))
        XCTAssertFalse(source.contains("DragGesture()"))
        XCTAssertFalse(source.contains("lastDragTranslation"))
    }

    func testPanelKeepsAutoDismissSupportOnlyForExplicitExpandedPresentation() throws {
        let root = Self.repositoryRoot()
        let source = try String(
            contentsOf: root
                .appendingPathComponent("Sources/VoxFlowApp/Presentation/ScreenshotOCRResultPanelController.swift"),
            encoding: .utf8
        )
        let sharedControllerSource = try String(
            contentsOf: root
                .appendingPathComponent("Sources/VoxFlowApp/Presentation/TextResultPanelController.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("autoDismissScheduler.schedule(after: 5"))
        XCTAssertTrue(source.contains("cancelAutoDismissForInteraction()"))
        XCTAssertTrue(sharedControllerSource.contains("override func sendEvent"))
        XCTAssertTrue(source.contains("service.stopSpeaking()"))
        XCTAssertTrue(source.contains("ContextBoostSuppression.setSuppressed(false"))
    }

    func testScreenshotAndSelectionPanelsShareWindowController() throws {
        let root = Self.repositoryRoot()
        let selectionSource = try String(
            contentsOf: root
                .appendingPathComponent("Sources/VoxFlowApp/Presentation/SelectionResultPanelController.swift"),
            encoding: .utf8
        )
        let screenshotSource = try String(
            contentsOf: Self.repositoryRoot()
                .appendingPathComponent("Sources/VoxFlowApp/Presentation/ScreenshotOCRResultPanelController.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(selectionSource.contains("TextResultPanelController(title: \"文本结果\")"))
        XCTAssertTrue(screenshotSource.contains("TextResultPanelController(title: \"屏幕识别\")"))
        XCTAssertFalse(selectionSource.contains("NSPanel"))
        XCTAssertFalse(screenshotSource.contains("NSPanel"))
    }

    func testScreenshotResultCanPresentBottomTrailingThumbnailWithoutAutoDismiss() throws {
        let source = try String(
            contentsOf: Self.repositoryRoot()
                .appendingPathComponent("Sources/VoxFlowApp/Presentation/ScreenshotOCRResultPanelController.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("func presentThumbnail("))
        XCTAssertTrue(source.contains("ScreenshotOCRResultThumbnailView"))
        XCTAssertTrue(source.contains("contentSize: NSSize(width: 260, height: 150)"))
        XCTAssertTrue(source.contains("bottomMargin: 28"))
        XCTAssertTrue(source.contains("autoDismissScheduler.schedule(after: 3"))
        XCTAssertTrue(source.contains("autoDismiss: false"))
        XCTAssertFalse(source.contains("Image(systemName: \"xmark\")"))
    }

    func testExpandedScreenshotSelectionAndAIChatPanelsUseSharedRightSidePlacementWhileThumbnailIsBottomTrailing() throws {
        let screenshotSource = try String(
            contentsOf: Self.repositoryRoot()
                .appendingPathComponent("Sources/VoxFlowApp/Presentation/ScreenshotOCRResultPanelController.swift"),
            encoding: .utf8
        )
        let selectionSource = try String(
            contentsOf: Self.repositoryRoot()
                .appendingPathComponent("Sources/VoxFlowApp/Presentation/SelectionResultPanelController.swift"),
            encoding: .utf8
        )
        let sharedControllerSource = try String(
            contentsOf: Self.repositoryRoot()
                .appendingPathComponent("Sources/VoxFlowApp/Presentation/TextResultPanelController.swift"),
            encoding: .utf8
        )
        let aiChatSource = try String(
            contentsOf: Self.repositoryRoot()
                .appendingPathComponent("Sources/VoxFlowApp/Presentation/AIChatPanelController.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(screenshotSource.contains("contentSize: NSSize(width: 440, height: 560)"))
        XCTAssertTrue(screenshotSource.contains("contentSize: NSSize(width: 260, height: 150)"))
        XCTAssertTrue(screenshotSource.contains("placement: .bottomTrailing("))
        XCTAssertTrue(screenshotSource.contains("bottomMargin: 28"))
        XCTAssertTrue(screenshotSource.contains("visualOutset: 24"))
        XCTAssertTrue(selectionSource.contains("panelController.present(\n            rootView: rootView,"))
        XCTAssertTrue(aiChatSource.contains("TextResultPanelController(title: \"问 AI\")"))

        XCTAssertTrue(sharedControllerSource.contains("placement: TextResultPanelPlacement = .rightSideCentered"))
        XCTAssertTrue(sharedControllerSource.contains("position(window, placement: placement)"))
        XCTAssertTrue(sharedControllerSource.contains("WindowPlacementPolicy.rightSideCenteredFrame("))
        XCTAssertTrue(sharedControllerSource.contains("WindowPlacementPolicy.clampedFrame("))
        XCTAssertTrue(sharedControllerSource.contains("panel.isMovableByWindowBackground = true"))
        XCTAssertFalse(sharedControllerSource.contains("interactionReferenceFrame"))
        XCTAssertFalse(sharedControllerSource.contains("layoutSubtreeIfNeeded"))
        XCTAssertFalse(sharedControllerSource.contains("masksToBounds"))
        XCTAssertFalse(screenshotSource.contains("placementReference"))
        XCTAssertFalse(screenshotSource.contains("WindowPlacementReference"))
        XCTAssertFalse(selectionSource.contains("placement:"))
        XCTAssertFalse(aiChatSource.contains("placement:"))
    }

    func testWindowPlacementPolicyKeepsOnlyGenericRightSidePlacementWithoutScreenshotReferenceState() throws {
        let source = try String(
            contentsOf: Self.repositoryRoot()
                .appendingPathComponent("Sources/VoxFlowApp/Presentation/WindowPlacementPolicy.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("rightSideCenteredFrame"))
        XCTAssertFalse(source.contains("WindowPlacementReference"))
        XCTAssertFalse(source.contains("interactionReferenceFrame"))
        XCTAssertFalse(source.contains("focusedWindowFrameInAppKitCoordinates"))
    }

    func testPanelCanPresentOCRTabWithoutAutoDismiss() throws {
        let source = try String(
            contentsOf: Self.repositoryRoot()
                .appendingPathComponent("Sources/VoxFlowApp/Presentation/ScreenshotOCRResultPanelController.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("initialTab: ScreenshotOCRResultTab = .originalImage"))
        XCTAssertTrue(source.contains("autoDismiss: Bool = true"))
        XCTAssertTrue(source.contains("initialTab: initialTab"))
        XCTAssertTrue(source.contains("if autoDismiss"))
        XCTAssertTrue(source.contains("cancelAutoDismissForInteraction()"))
    }

    func testTemporaryScreenshotResultPlacementDiagnosticsAreRemoved() throws {
        let root = Self.repositoryRoot()
        let appDelegateSource = try String(
            contentsOf: root.appendingPathComponent("Sources/VoxFlowApp/App/AppDelegate.swift"),
            encoding: .utf8
        )
        let screenshotSource = try String(
            contentsOf: root.appendingPathComponent("Sources/VoxFlowApp/Presentation/ScreenshotOCRResultPanelController.swift"),
            encoding: .utf8
        )
        let sharedControllerSource = try String(
            contentsOf: root.appendingPathComponent("Sources/VoxFlowApp/Presentation/TextResultPanelController.swift"),
            encoding: .utf8
        )

        [
            appDelegateSource,
            screenshotSource,
            sharedControllerSource
        ].forEach { source in
            XCTAssertFalse(source.contains("screenshot_ocr_route_decision"))
            XCTAssertFalse(source.contains("screenshot_ocr_present_expanded"))
            XCTAssertFalse(source.contains("screenshot_ocr_present_thumbnail"))
            XCTAssertFalse(source.contains("screenshot_ocr_thumbnail_open_requested"))
            XCTAssertFalse(source.contains("text_result_panel_present_start"))
            XCTAssertFalse(source.contains("text_result_panel_position_apply"))
            XCTAssertFalse(source.contains("text_result_panel_keep_visible"))
            XCTAssertFalse(source.contains("text_result_panel_active_screen"))
        }
    }

    func testAppDelegateUsesPresentationPolicyForScreenshotOCRResults() throws {
        let source = try String(
            contentsOf: Self.repositoryRoot()
                .appendingPathComponent("Sources/VoxFlowApp/App/AppDelegate.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("ScreenshotOCRResultPresentationPolicy.route(for: result)"))
        XCTAssertTrue(source.contains("case let .expanded(initialTab, autoDismiss):"))
        XCTAssertTrue(source.contains("case let .thumbnail(initialTab):"))
        XCTAssertTrue(source.contains("screenshotOCRResultPanelController.presentThumbnail("))
        XCTAssertFalse(source.contains("opensFromTextRecognitionCommand"))
        XCTAssertFalse(source.contains("result.captureCompletionKind == .textRecognition"))
    }

    func testCompleteAndScrollingScreenshotUseThumbnailAndKeepExpandedCompletionCopy() throws {
        let appDelegateSource = try String(
            contentsOf: Self.repositoryRoot()
                .appendingPathComponent("Sources/VoxFlowApp/App/AppDelegate.swift"),
            encoding: .utf8
        )
        let panelSource = try String(
            contentsOf: Self.repositoryRoot()
                .appendingPathComponent("Sources/VoxFlowApp/Presentation/ScreenshotOCRResultPanelController.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(appDelegateSource.contains("ScreenshotOCRResultPresentationPolicy.route(for: result)"))
        XCTAssertTrue(appDelegateSource.contains("screenshotOCRResultPanelController.presentThumbnail("))
        XCTAssertFalse(appDelegateSource.contains("let completionMessage = result.captureCompletionKind == .scrollingScreenshot"))
        XCTAssertTrue(panelSource.contains("viewModel.result.captureCompletionKind == .scrollingScreenshot ? \"截图完成\" : \"识别完成\""))
    }

    func testImagePreviewUsesFixedViewportAndOffersImageCopyActions() throws {
        let source = try String(
            contentsOf: Self.repositoryRoot()
                .appendingPathComponent("Sources/VoxFlowApp/Presentation/ScreenshotOCRResultPanelController.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("screenshotImagePreview"))
        XCTAssertTrue(source.contains("ScrollView(.vertical)"))
        XCTAssertTrue(source.contains(".contextMenu"))
        XCTAssertTrue(source.contains("viewModel.copySelectedImage()"))
        XCTAssertTrue(source.contains("Label(\"复制图片\""))
    }

    func testPanelPresentsWithoutActivatingVoxFlowApp() throws {
        let source = try String(
            contentsOf: Self.repositoryRoot()
                .appendingPathComponent("Sources/VoxFlowApp/Presentation/ScreenshotOCRResultPanelController.swift"),
            encoding: .utf8
        )
        let sharedControllerSource = try String(
            contentsOf: Self.repositoryRoot()
                .appendingPathComponent("Sources/VoxFlowApp/Presentation/TextResultPanelController.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(sharedControllerSource.contains("styleMask: [.borderless, .nonactivatingPanel]"))
        XCTAssertTrue(sharedControllerSource.contains("window.orderFrontRegardless()"))
        XCTAssertTrue(sharedControllerSource.contains("window.makeKey()"))
        XCTAssertFalse(source.contains("window.makeKeyAndOrderFront(nil)"))
        XCTAssertFalse(source.contains("NSApp.activate(ignoringOtherApps: true)"))
        XCTAssertFalse(sharedControllerSource.contains("NSApp.activate(ignoringOtherApps: true)"))
    }

    func testPanelUsesProjectAccentInsteadOfSystemBlueOrGreen() throws {
        let root = Self.repositoryRoot()
        let source = try String(
            contentsOf: root.appendingPathComponent("Sources/VoxFlowApp/Presentation/ScreenshotOCRResultPanelController.swift"),
            encoding: .utf8
        )
        let sharedSource = try String(
            contentsOf: root.appendingPathComponent("Sources/VoxFlowApp/Presentation/TextResultPanelView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(sharedSource.contains("AppTheme.ColorToken.accent"))
        XCTAssertTrue(sharedSource.contains("AppTheme.ColorToken.accentSoft"))
        XCTAssertFalse(source.contains(".foregroundStyle(.blue)"))
        XCTAssertFalse(source.contains(".foregroundStyle(.green)"))
        XCTAssertFalse(source.contains("Color.green"))
    }

    private static func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
