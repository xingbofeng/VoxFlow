import XCTest

final class AnnotationEditorViewSourceTests: XCTestCase {
    func testEditorToolbarUsesIconButtonsWithChineseHelpText() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/VoxFlowScreenshotKit/Annotations/AnnotationEditorView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        for helpText in ["选择", "画笔", "圈注", "矩形", "箭头", "标记点", "数字点", "文字", "马赛克", "颜色", "线宽", "下载", "撤销", "重做", "取消", "完成"] {
            XCTAssertTrue(source.contains("help: \"\(helpText)\""), "Missing Chinese help text: \(helpText)")
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

        XCTAssertTrue(source.contains("help: \"复制\"") && source.contains("viewModel.copySelectedElement"))
        XCTAssertTrue(source.contains("help: \"粘贴\"") && source.contains("viewModel.pasteCopiedElement()"))
        XCTAssertTrue(source.contains("help: \"复制一份\"") && source.contains("viewModel.duplicateSelectedElement()"))
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
