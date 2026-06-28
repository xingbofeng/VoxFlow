import XCTest

final class AnnotationEditorViewSourceTests: XCTestCase {
    func testEditorToolbarUsesLocalizedIconButtonHelp() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/VoxFlowScreenshotKit/Annotations/AnnotationEditorView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let simplifiedChineseStringsURL = sourceURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/zh-Hans.lproj/ScreenshotKit.strings")
        let simplifiedChineseStrings = try String(contentsOf: simplifiedChineseStringsURL, encoding: .utf8)

        for localizedHelp in [
            ("ScreenshotL10n.ScreenshotKit.Toolbar.select", "\"toolbar.select\" = \"选择\""),
            ("ScreenshotL10n.ScreenshotKit.Toolbar.pen", "\"toolbar.pen\" = \"画笔\""),
            ("ScreenshotL10n.ScreenshotKit.Toolbar.circle", "\"toolbar.circle\" = \"圈注\""),
            ("ScreenshotL10n.ScreenshotKit.Toolbar.rectangle", "\"toolbar.rectangle\" = \"矩形\""),
            ("ScreenshotL10n.ScreenshotKit.Toolbar.arrow", "\"toolbar.arrow\" = \"箭头\""),
            ("ScreenshotL10n.ScreenshotKit.Toolbar.pointMarker", "\"toolbar.point_marker\" = \"标记点\""),
            ("ScreenshotL10n.ScreenshotKit.Toolbar.numberedMarker", "\"toolbar.numbered_marker\" = \"数字点\""),
            ("ScreenshotL10n.ScreenshotKit.Toolbar.text", "\"toolbar.text\" = \"文字\""),
            ("ScreenshotL10n.ScreenshotKit.Toolbar.mosaic", "\"toolbar.mosaic\" = \"马赛克\""),
            ("ScreenshotL10n.ScreenshotKit.Toolbar.color", "\"toolbar.color\" = \"颜色\""),
            ("ScreenshotL10n.ScreenshotKit.Toolbar.lineWidth", "\"toolbar.line_width\" = \"线宽\""),
            ("ScreenshotL10n.ScreenshotKit.Toolbar.download", "\"toolbar.download\" = \"下载\""),
            ("ScreenshotL10n.ScreenshotKit.Toolbar.undo", "\"toolbar.undo\" = \"撤销\""),
            ("ScreenshotL10n.ScreenshotKit.Toolbar.redo", "\"toolbar.redo\" = \"重做\""),
            ("ScreenshotL10n.ScreenshotKit.Toolbar.cancel", "\"toolbar.cancel\" = \"取消\""),
            ("ScreenshotL10n.ScreenshotKit.Toolbar.complete", "\"toolbar.complete\" = \"完成\""),
        ] {
            XCTAssertTrue(source.contains("help: \(localizedHelp.0)"), "Missing localized help key: \(localizedHelp.0)")
            XCTAssertTrue(
                simplifiedChineseStrings.contains(localizedHelp.1),
                "Missing Simplified Chinese resource: \(localizedHelp.1)"
            )
        }
        XCTAssertTrue(source.contains(".help(help)"))
        XCTAssertTrue(source.contains("square.and.arrow.down"))
        XCTAssertTrue(source.contains("xmark"))
        XCTAssertTrue(source.contains("checkmark"))
        XCTAssertTrue(source.contains("doc.on.doc"))
        XCTAssertTrue(source.contains("ZStack(alignment: .bottom)"))
        XCTAssertTrue(source.contains("frame(width: Self.toolbarItemSize, height: Self.toolbarItemSize)"))
        XCTAssertTrue(source.contains(".frame(minWidth: 640, minHeight: 320)"))
    }

    func testEditorWiresCopyPasteDuplicateKeyboardShortcuts() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/VoxFlowScreenshotKit/Annotations/AnnotationEditorView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("copySelectedElement"))
        XCTAssertTrue(source.contains("pasteCopiedElement"))
        XCTAssertTrue(source.contains("duplicateSelectedElement"))
        XCTAssertTrue(source.contains("key.characters.lowercased()"))
        XCTAssertTrue(source.contains("modifiers.contains(.command)"))
        XCTAssertTrue(source.contains("case \"c\""))
        XCTAssertTrue(source.contains("case \"v\""))
        XCTAssertTrue(source.contains("case \"d\""))
    }

    func testEditorToolbarExposesSeparateCopyPasteAndDuplicateCommands() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/VoxFlowScreenshotKit/Annotations/AnnotationEditorView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("help: ScreenshotL10n.ScreenshotKit.Toolbar.copy") && source.contains("viewModel.copySelectedElement"))
        XCTAssertTrue(source.contains("help: ScreenshotL10n.ScreenshotKit.Toolbar.paste") && source.contains("viewModel.pasteCopiedElement()"))
        XCTAssertTrue(source.contains("help: ScreenshotL10n.ScreenshotKit.Toolbar.duplicate") && source.contains("viewModel.duplicateSelectedElement()"))
    }

    func testEditorWiresShiftClickMultiSelectAndMultiSelectionRendering() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/VoxFlowScreenshotKit/Annotations/AnnotationEditorView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("NSEvent.modifierFlags.contains(.shift)"))
        XCTAssertTrue(source.contains("toggleElementSelection(id: hitID)"))
        XCTAssertTrue(source.contains("document.selectedElementIDs.contains(hitID)"))
        XCTAssertTrue(source.contains("document.selectedElementIDs.contains(element.id)"))
    }

    func testEditorWiresMarqueeSelectionDragPreview() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/VoxFlowScreenshotKit/Annotations/AnnotationEditorView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("@State private var marqueeSelectionRect"))
        XCTAssertTrue(source.contains("dragMode = .marqueeSelecting"))
        XCTAssertTrue(source.contains("marqueeSelectionRect = normalizedRect"))
        XCTAssertTrue(source.contains("viewModel.selectElements(in: marqueeRect, extendingSelection: isShiftSelecting)"))
        XCTAssertTrue(source.contains("AnnotationMarqueeSelectionOverlay"))
        XCTAssertTrue(source.contains("StrokeStyle(lineWidth: 1.5, dash: [6, 4])"))
    }

    func testBrushMosaicDoesNotRenderRectangularSelectionChrome() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/VoxFlowScreenshotKit/Annotations/AnnotationEditorView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("guard element.kind != .mosaic else { return }"))
        XCTAssertTrue(source.contains("case .pen, .mosaic:"))
    }

    func testMosaicToolRendersBrushPreviewFromPointerHover() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/VoxFlowScreenshotKit/Annotations/AnnotationEditorView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("@State private var mosaicBrushPreviewPoint"))
        XCTAssertTrue(source.contains(".onContinuousHover"))
        XCTAssertTrue(source.contains("MosaicBrushPreviewOverlay"))
    }

    func testTextEditingUsesShotShotStyleIMEAwareNSTextViewBridge() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/VoxFlowScreenshotKit/Annotations/AnnotationEditorView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("IMEAwareTextEditor"))
        XCTAssertTrue(source.contains("NSViewRepresentable"))
        XCTAssertTrue(source.contains("NSTextView"))
        XCTAssertTrue(source.contains("textDidChange"))
        XCTAssertTrue(source.contains("textDidEndEditing"))
        XCTAssertTrue(source.contains("displayText"))
        XCTAssertTrue(source.contains("tokuhirom/ShotShot"))
        XCTAssertTrue(source.contains("c600d978c3ba1cce72c26e8af19e3bca155d0e15"))
    }
}
