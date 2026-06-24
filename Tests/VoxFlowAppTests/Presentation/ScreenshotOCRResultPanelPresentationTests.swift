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

    func testAppDelegateOnlyTextRecognitionCommandOpensOCRTabWithoutAutoDismiss() throws {
        let source = try String(
            contentsOf: Self.repositoryRoot()
                .appendingPathComponent("Sources/VoxFlowApp/App/AppDelegate.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("opensFromTextRecognitionCommand"))
        XCTAssertTrue(source.contains("result.captureCompletionKind == .textRecognition"))
        XCTAssertTrue(source.contains("initialTab: .ocr"))
        XCTAssertTrue(source.contains("screenshotOCRResultPanelController.presentThumbnail("))
        XCTAssertFalse(source.contains("autoDismiss: !opensFromTextRecognitionCommand"))
    }

    func testScrollingScreenshotUsesThumbnailAndKeepsExpandedCompletionCopy() throws {
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
