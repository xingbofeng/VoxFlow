import AppKit
import CoreGraphics
import XCTest
@testable import VoxFlowScreenshotKit

@MainActor
final class AnnotationEditorViewModelTests: XCTestCase {
    func testCompleteWithoutAnnotationsReturnsOriginalImage() throws {
        let image = makeImage(width: 20, height: 10)
        let viewModel = AnnotationEditorViewModel(image: image)

        let result = try viewModel.complete()

        XCTAssertEqual(result.width, 20)
        XCTAssertEqual(result.height, 10)
        XCTAssertEqual(viewModel.isFinished, true)
    }

    func testCompleteRendersAnnotationsBeforeReturningImage() throws {
        let image = makeImage(width: 20, height: 10)
        let renderer = CapturingAnnotationRenderer()
        let viewModel = AnnotationEditorViewModel(image: image, renderer: renderer)
        viewModel.add(.rectangle(RectangleAnnotationElement(rect: CGRect(x: 1, y: 1, width: 4, height: 4))))

        let result = try viewModel.complete()

        XCTAssertEqual(renderer.renderCallCount, 1)
        XCTAssertEqual(result.width, 20)
        XCTAssertEqual(result.height, 10)
    }

    func testDownloadAttachesSavePanelToScreenshotHostWithoutFinishingEditor() throws {
        let image = makeImage(width: 20, height: 10)
        let saver = CapturingAnnotationImageSaver()
        let hostWindow = NSWindow()
        let viewModel = AnnotationEditorViewModel(
            image: image,
            imageSaver: saver,
            savePanelHostWindowProvider: { hostWindow }
        )

        try viewModel.download()

        XCTAssertEqual(saver.savedImageWidths, [20])
        XCTAssertTrue(saver.hostWindows.first === hostWindow)
        XCTAssertFalse(viewModel.isFinished)
        XCTAssertFalse(viewModel.isCancelled)
    }

    func testDownloadCancellationRestoresScreenshotEditingState() throws {
        let image = makeImage(width: 20, height: 10)
        let saver = CapturingAnnotationImageSaver(result: false)
        let viewModel = AnnotationEditorViewModel(
            image: image,
            imageSaver: saver,
            savePanelHostWindowProvider: { NSWindow() }
        )

        try viewModel.download()

        XCTAssertFalse(viewModel.isFinished)
        XCTAssertFalse(viewModel.isCancelled)
    }

    func testDownloadWriteFailurePublishesErrorAndKeepsEditingState() throws {
        let image = makeImage(width: 20, height: 10)
        let saver = CapturingAnnotationImageSaver(error: AnnotationImageSaveError.pngEncodingFailed)
        let viewModel = AnnotationEditorViewModel(
            image: image,
            imageSaver: saver,
            savePanelHostWindowProvider: { NSWindow() }
        )

        try viewModel.download()

        XCTAssertEqual(viewModel.saveError as? AnnotationImageSaveError, .pngEncodingFailed)
        XCTAssertFalse(viewModel.isFinished)
        XCTAssertFalse(viewModel.isCancelled)
    }

    func testCancelMarksEditorCancelledWithoutRenderingOrSaving() {
        let image = makeImage(width: 20, height: 10)
        let renderer = CapturingAnnotationRenderer()
        let saver = CapturingAnnotationImageSaver()
        let viewModel = AnnotationEditorViewModel(image: image, renderer: renderer, imageSaver: saver)

        viewModel.cancel()

        XCTAssertTrue(viewModel.isCancelled)
        XCTAssertEqual(renderer.renderCallCount, 0)
        XCTAssertTrue(saver.savedImageWidths.isEmpty)
    }

    func testUndoRedoDelegatesToDocument() {
        let image = makeImage(width: 20, height: 10)
        let viewModel = AnnotationEditorViewModel(image: image)
        viewModel.add(.rectangle(RectangleAnnotationElement(rect: CGRect(x: 1, y: 1, width: 4, height: 4))))

        viewModel.undo()
        XCTAssertTrue(viewModel.document.elements.isEmpty)

        viewModel.redo()
        XCTAssertEqual(viewModel.document.elements.count, 1)
    }

    func testCommitTextEditingAddsChineseTextAnnotation() {
        let image = makeImage(width: 20, height: 10)
        let viewModel = AnnotationEditorViewModel(image: image)

        viewModel.beginTextEditing(at: CGPoint(x: 7, y: 9))
        viewModel.updateTextEditingDisplayText("中文标注")
        viewModel.commitTextEditing()

        guard case .text(let element) = viewModel.document.elements.first else {
            XCTFail("Expected text annotation")
            return
        }
        XCTAssertEqual(element.position, CGPoint(x: 7, y: 9))
        XCTAssertEqual(element.content, "中文标注")
        XCTAssertNil(viewModel.textEditingDraft)
    }

    func testCommitTextEditingUpdatesExistingTextAndEmptyCommitDeletesIt() {
        let image = makeImage(width: 20, height: 10)
        let viewModel = AnnotationEditorViewModel(image: image)
        let element = TextAnnotationElement(
            id: UUID(),
            position: CGPoint(x: 3, y: 4),
            content: "旧文字"
        )
        viewModel.add(.text(element))

        viewModel.beginTextEditing(elementID: element.id)
        viewModel.updateTextEditingDisplayText("新中文")
        viewModel.commitTextEditing()

        guard case .text(let updated) = viewModel.document.elements.first else {
            XCTFail("Expected updated text annotation")
            return
        }
        XCTAssertEqual(updated.id, element.id)
        XCTAssertEqual(updated.position, CGPoint(x: 3, y: 4))
        XCTAssertEqual(updated.content, "新中文")

        viewModel.beginTextEditing(elementID: element.id)
        viewModel.updateTextEditingDisplayText("   ")
        viewModel.commitTextEditing()

        XCTAssertTrue(viewModel.document.elements.isEmpty)
    }

    func testCancelTextEditingKeepsExistingAnnotationUnchanged() {
        let image = makeImage(width: 20, height: 10)
        let viewModel = AnnotationEditorViewModel(image: image)
        let element = TextAnnotationElement(
            id: UUID(),
            position: CGPoint(x: 3, y: 4),
            content: "原文"
        )
        viewModel.add(.text(element))

        viewModel.beginTextEditing(elementID: element.id)
        viewModel.updateTextEditingDisplayText("临时输入")
        viewModel.cancelTextEditing()

        XCTAssertNil(viewModel.textEditingDraft)
        XCTAssertEqual(viewModel.document.elements, [.text(element)])
    }

    func testSelectElementAtPointMoveAndResizeUseImageCoordinates() {
        let image = makeImage(width: 200, height: 120)
        let viewModel = AnnotationEditorViewModel(image: image)
        let element = AnnotationElement.rectangle(
            RectangleAnnotationElement(id: UUID(), rect: CGRect(x: 20, y: 30, width: 60, height: 40))
        )
        viewModel.add(element)

        viewModel.selectElement(at: CGPoint(x: 30, y: 35))
        XCTAssertEqual(viewModel.document.selectedElementID, element.id)

        viewModel.moveSelectedElement(by: CGSize(width: 10, height: -5))
        XCTAssertEqual(viewModel.document.elements.first?.bounds, CGRect(x: 30, y: 25, width: 60, height: 40))

        viewModel.resizeSelectedElement(handle: .endPoint, to: CGPoint(x: 120, y: 90))
        XCTAssertEqual(viewModel.document.elements.first?.bounds, CGRect(x: 30, y: 25, width: 90, height: 65))
    }

    func testToggleElementSelectionAtPointAllowsBatchMoveAndDelete() {
        let image = makeImage(width: 200, height: 120)
        let viewModel = AnnotationEditorViewModel(image: image)
        let first = AnnotationElement.rectangle(
            RectangleAnnotationElement(id: UUID(), rect: CGRect(x: 20, y: 30, width: 60, height: 40))
        )
        let second = AnnotationElement.ellipse(
            EllipseAnnotationElement(id: UUID(), rect: CGRect(x: 100, y: 40, width: 30, height: 30))
        )
        viewModel.add(first)
        viewModel.add(second)

        viewModel.selectElement(at: CGPoint(x: 30, y: 35))
        viewModel.toggleElementSelection(at: CGPoint(x: 110, y: 50))
        viewModel.moveSelectedElement(by: CGSize(width: 5, height: 6))

        XCTAssertEqual(viewModel.document.selectedElementIDs, [first.id, second.id])
        XCTAssertEqual(viewModel.document.elements[0].bounds, CGRect(x: 25, y: 36, width: 60, height: 40))
        XCTAssertEqual(viewModel.document.elements[1].bounds, CGRect(x: 105, y: 46, width: 30, height: 30))

        viewModel.deleteSelectedElement()
        XCTAssertTrue(viewModel.document.elements.isEmpty)
    }

    func testMarqueeSelectionSelectsIntersectingElementsAndCanExtendExistingSelection() {
        let image = makeImage(width: 240, height: 160)
        let viewModel = AnnotationEditorViewModel(image: image)
        let first = AnnotationElement.rectangle(
            RectangleAnnotationElement(id: UUID(), rect: CGRect(x: 20, y: 30, width: 60, height: 40))
        )
        let second = AnnotationElement.ellipse(
            EllipseAnnotationElement(id: UUID(), rect: CGRect(x: 100, y: 40, width: 30, height: 30))
        )
        let third = AnnotationElement.mosaic(
            MosaicAnnotationElement(
                id: UUID(),
                points: [CGPoint(x: 170, y: 80), CGPoint(x: 195, y: 105)],
                brushSize: 10
            )
        )
        viewModel.add(first)
        viewModel.add(second)
        viewModel.add(third)

        viewModel.selectElements(in: CGRect(x: 0, y: 0, width: 145, height: 90))

        XCTAssertEqual(viewModel.document.selectedElementIDs, [first.id, second.id])

        viewModel.selectElements(
            in: CGRect(x: 160, y: 70, width: 60, height: 60),
            extendingSelection: true
        )
        viewModel.moveSelectedElement(by: CGSize(width: 3, height: 4))

        XCTAssertEqual(viewModel.document.selectedElementIDs, [first.id, second.id, third.id])
        XCTAssertEqual(viewModel.document.elements.map(\.bounds), [
            CGRect(x: 23, y: 34, width: 60, height: 40),
            CGRect(x: 103, y: 44, width: 30, height: 30),
            CGRect(x: 168, y: 79, width: 35, height: 35),
        ])
    }

    func testColorAndLineWidthUpdatesCurrentStyleAndSelectedAnnotation() {
        let image = makeImage(width: 80, height: 60)
        let viewModel = AnnotationEditorViewModel(image: image)
        let element = AnnotationElement.arrow(
            ArrowAnnotationElement(id: UUID(), startPoint: CGPoint(x: 10, y: 10), endPoint: CGPoint(x: 50, y: 40))
        )
        viewModel.add(element)
        viewModel.selectElement(id: element.id)

        viewModel.setAnnotationColor(.red)
        viewModel.setLineWidth(6)

        XCTAssertEqual(viewModel.currentStyle, ScreenshotAnnotationStyle(color: .red, lineWidth: 6))
        guard case .arrow(let updated) = viewModel.document.elements.first else {
            XCTFail("Expected arrow annotation")
            return
        }
        XCTAssertEqual(updated.style, ScreenshotAnnotationStyle(color: .red, lineWidth: 6))
    }

    func testChangingSelectedTextFontSizePreservesExistingTextColor() {
        let image = makeImage(width: 80, height: 60)
        let viewModel = AnnotationEditorViewModel(image: image)
        let element = TextAnnotationElement(
            id: UUID(),
            position: CGPoint(x: 10, y: 10),
            content: "文字",
            style: ScreenshotAnnotationTextStyle(color: .red, fontSize: 18)
        )
        viewModel.add(.text(element))
        viewModel.selectElement(id: element.id)

        viewModel.setFontSize(32)

        guard case .text(let updated) = viewModel.document.elements.first else {
            XCTFail("Expected text annotation")
            return
        }
        XCTAssertEqual(updated.style.color, .red)
        XCTAssertEqual(updated.style.fontSize, 32)
    }

    func testCopyAndPasteSelectedAnnotationCreatesOffsetCopyWithNewID() {
        let image = makeImage(width: 120, height: 80)
        let viewModel = AnnotationEditorViewModel(image: image)
        let element = AnnotationElement.rectangle(
            RectangleAnnotationElement(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000201")!,
                rect: CGRect(x: 10, y: 20, width: 30, height: 40)
            )
        )
        viewModel.add(element)
        viewModel.selectElement(id: element.id)

        viewModel.copySelectedElement()
        viewModel.pasteCopiedElement()

        XCTAssertEqual(viewModel.document.elements.count, 2)
        XCTAssertEqual(viewModel.document.elements.first?.id, element.id)
        guard let pasted = viewModel.document.elements.last else {
            XCTFail("Expected pasted annotation")
            return
        }
        XCTAssertNotEqual(pasted.id, element.id)
        XCTAssertEqual(pasted.bounds, CGRect(x: 25, y: 35, width: 30, height: 40))
        XCTAssertEqual(viewModel.document.selectedElementID, pasted.id)

        viewModel.undo()
        XCTAssertEqual(viewModel.document.elements, [element])
    }

    func testCopyPasteAndDuplicateMultipleSelectedAnnotationsPreserveGroupSelection() {
        let image = makeImage(width: 180, height: 120)
        let viewModel = AnnotationEditorViewModel(image: image)
        let first = AnnotationElement.rectangle(
            RectangleAnnotationElement(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000202")!,
                rect: CGRect(x: 10, y: 20, width: 30, height: 40)
            )
        )
        let second = AnnotationElement.ellipse(
            EllipseAnnotationElement(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000203")!,
                rect: CGRect(x: 70, y: 30, width: 20, height: 25)
            )
        )
        viewModel.add(first)
        viewModel.add(second)
        viewModel.selectElement(id: first.id)
        viewModel.toggleElementSelection(id: second.id)

        viewModel.copySelectedElement()
        viewModel.pasteCopiedElement(offset: CGSize(width: 12, height: 8))

        XCTAssertEqual(viewModel.document.elements.count, 4)
        let pasted = Array(viewModel.document.elements.suffix(2))
        XCTAssertEqual(pasted.map(\.bounds), [
            CGRect(x: 22, y: 28, width: 30, height: 40),
            CGRect(x: 82, y: 38, width: 20, height: 25),
        ])
        XCTAssertEqual(viewModel.document.selectedElementIDs, pasted.map(\.id))

        viewModel.duplicateSelectedElement(offset: CGSize(width: 12, height: 8))

        XCTAssertEqual(viewModel.document.elements.count, 6)
        let duplicated = Array(viewModel.document.elements.suffix(2))
        XCTAssertEqual(duplicated.map(\.bounds), [
            CGRect(x: 34, y: 36, width: 30, height: 40),
            CGRect(x: 94, y: 46, width: 20, height: 25),
        ])
        XCTAssertEqual(viewModel.document.selectedElementIDs, duplicated.map(\.id))
    }

    func testPasteWithoutCopiedAnnotationDoesNothing() {
        let image = makeImage(width: 120, height: 80)
        let viewModel = AnnotationEditorViewModel(image: image)

        viewModel.pasteCopiedElement()

        XCTAssertTrue(viewModel.document.elements.isEmpty)
    }

    private func makeImage(width: Int, height: Int) -> CGImage {
        let bytesPerPixel = 4
        let data = Data(repeating: 255, count: width * height * bytesPerPixel)
        let provider = CGDataProvider(data: data as CFData)!
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * bytesPerPixel,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )!
    }
}

private final class CapturingAnnotationRenderer: AnnotationRendering {
    private(set) var renderCallCount = 0

    func render(image: CGImage, document: AnnotationDocument) throws -> CGImage {
        renderCallCount += 1
        return image
    }
}

private final class CapturingAnnotationImageSaver: AnnotationImageSaving {
    private(set) var savedImageWidths: [Int] = []
    private(set) var hostWindows: [NSWindow] = []
    private let result: Bool
    private let error: Error?

    init(result: Bool = true, error: Error? = nil) {
        self.result = result
        self.error = error
    }

    func savePNG(
        image: CGImage,
        attachedTo hostWindow: NSWindow,
        completion: @escaping (Result<Bool, Error>) -> Void
    ) {
        savedImageWidths.append(image.width)
        hostWindows.append(hostWindow)
        if let error {
            completion(.failure(error))
        } else {
            completion(.success(result))
        }
    }
}
