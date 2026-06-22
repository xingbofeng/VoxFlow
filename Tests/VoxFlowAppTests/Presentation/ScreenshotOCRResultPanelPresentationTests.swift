import XCTest

final class ScreenshotOCRResultPanelPresentationTests: XCTestCase {
    func testPanelUsesNativeWindowDraggingInsteadOfIncrementalSwiftUIDragGesture() throws {
        let source = try String(
            contentsOf: Self.repositoryRoot()
                .appendingPathComponent("Sources/VoxFlowApp/Presentation/ScreenshotOCRResultPanelController.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("window?.performDrag(with: event)"))
        XCTAssertFalse(source.contains("DragGesture()"))
        XCTAssertFalse(source.contains("lastDragTranslation"))
    }

    func testPanelHasOneShotAutoDismissThatCancelsOnInteraction() throws {
        let source = try String(
            contentsOf: Self.repositoryRoot()
                .appendingPathComponent("Sources/VoxFlowApp/Presentation/ScreenshotOCRResultPanelController.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("autoDismissScheduler.schedule(after: 5"))
        XCTAssertTrue(source.contains("cancelAutoDismissForInteraction()"))
        XCTAssertTrue(source.contains("override func sendEvent"))
        XCTAssertTrue(source.contains("service.stopSpeaking()"))
        XCTAssertTrue(source.contains("ContextBoostSuppression.setSuppressed(false"))
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
        XCTAssertTrue(source.contains("initialTab: opensFromTextRecognitionCommand ? .ocr : .originalImage"))
        XCTAssertTrue(source.contains("autoDismiss: !opensFromTextRecognitionCommand"))
    }

    func testScrollingScreenshotUsesScreenshotCompletionCopy() throws {
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

        XCTAssertTrue(appDelegateSource.contains("result.captureCompletionKind == .scrollingScreenshot"))
        XCTAssertTrue(appDelegateSource.contains("\"截图完成\""))
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

        XCTAssertTrue(source.contains("styleMask: [.borderless, .nonactivatingPanel]"))
        XCTAssertTrue(source.contains("window.orderFrontRegardless()"))
        XCTAssertTrue(source.contains("window.makeKey()"))
        XCTAssertFalse(source.contains("window.makeKeyAndOrderFront(nil)"))
        XCTAssertFalse(source.contains("NSApp.activate(ignoringOtherApps: true)"))
    }

    func testPanelUsesProjectAccentInsteadOfSystemBlueOrGreen() throws {
        let source = try String(
            contentsOf: Self.repositoryRoot()
                .appendingPathComponent("Sources/VoxFlowApp/Presentation/ScreenshotOCRResultPanelController.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("AppTheme.ColorToken.accent"))
        XCTAssertTrue(source.contains("AppTheme.ColorToken.accentSoft"))
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
