import AppKit
import CoreGraphics
import XCTest
@testable import VoxFlowScreenshotKit

@MainActor
final class VoxFlowInteractiveScreenshotProviderTests: XCTestCase {
    func testCaptureFailsWhenSharedLeaseIsAlreadyHeld() async throws {
        let image = makeImage(width: 20, height: 20)
        let display = ScreenshotDisplay(
            id: 1,
            name: "Display",
            frame: CGRect(x: 0, y: 0, width: 20, height: 20),
            scale: 1,
            isPrimary: true
        )
        let frameProvider = ScreenCaptureFrameProvider(
            displayLoader: { [display] },
            displayCapture: { _, _ in image }
        )
        let lease = InteractiveScreenshotCaptureLease()
        XCTAssertTrue(lease.tryAcquire())
        let provider = VoxFlowInteractiveScreenshotProvider(
            frameProvider: frameProvider,
            selectionProvider: { _ in .cancelled },
            captureLease: lease
        )

        do {
            _ = try await provider.capture()
            XCTFail("Expected capture lease failure")
        } catch let error as InteractiveScreenshotError {
            guard case .captureFailed = error else {
                return XCTFail("Expected capture lease failure")
            }
        }
    }

    func testCaptureReleasesLeaseAfterCompletion() async throws {
        let image = makeImage(width: 20, height: 20)
        let display = ScreenshotDisplay(
            id: 1,
            name: "Display",
            frame: CGRect(x: 0, y: 0, width: 20, height: 20),
            scale: 1,
            isPrimary: true
        )
        let frameProvider = ScreenCaptureFrameProvider(
            displayLoader: { [display] },
            displayCapture: { _, _ in image }
        )
        let lease = InteractiveScreenshotCaptureLease()
        let provider = VoxFlowInteractiveScreenshotProvider(
            frameProvider: frameProvider,
            selectionProvider: { _ in
                .accepted(
                    SelectionState(
                        displayFrame: display.frame,
                        displayScale: display.scale,
                        startPoint: CGPoint(x: 2, y: 3),
                        currentPoint: CGPoint(x: 6, y: 8)
                    )
                )
            },
            captureLease: lease
        )

        _ = try await provider.capture()

        XCTAssertTrue(lease.tryAcquire())
    }

    func testCancellingCaptureClosesOverlayAndResumesContinuationOnlyOnce() async throws {
        let image = makeImage(width: 20, height: 20)
        let display = ScreenshotDisplay(
            id: 1,
            name: "Display",
            frame: CGRect(x: 0, y: 0, width: 20, height: 20),
            scale: 1,
            isPrimary: true
        )
        let frameProvider = ScreenCaptureFrameProvider(
            displayLoader: { [display] },
            displayCapture: { _, _ in image }
        )
        let windowFactory = CancellationTrackingOverlayWindowFactory()
        let provider = VoxFlowInteractiveScreenshotProvider(
            frameProvider: frameProvider,
            overlayControllerFactory: { onResult in
                let controller = SelectionOverlayController(
                    windowFactory: windowFactory,
                    onResult: onResult
                )
                return controller
            }
        )
        let task = Task { try await provider.captureImage() }
        while windowFactory.windows.isEmpty {
            await Task.yield()
        }

        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch let error as InteractiveScreenshotError {
            XCTAssertEqual(error, .cancelled)
        }
        XCTAssertEqual(windowFactory.windows.first?.closeCallCount, 1)

        windowFactory.windows.first?.emit(.cancelRequested)
        XCTAssertEqual(windowFactory.windows.first?.closeCallCount, 1)
    }

    func testCropSelectionPreservesFourCornerPixelOrientation() throws {
        let image = makeImage(rows: [
            [.red, .green],
            [.blue, .yellow],
        ])
        let display = ScreenshotDisplay(
            id: 1,
            name: "Display",
            frame: CGRect(x: 0, y: 0, width: 2, height: 2),
            scale: 1,
            isPrimary: true
        )
        let state = SelectionState(
            displayFrame: display.frame,
            displayScale: 1,
            startPoint: .zero,
            currentPoint: CGPoint(x: 2, y: 2)
        )

        let result = try XCTUnwrap(ScreenshotSelectionImageComposer.cropSelection(
            state,
            from: [ScreenshotDisplayFrame(display: display, image: image)]
        ))

        XCTAssertEqual(pixel(atX: 0, y: 0, in: result), .red)
        XCTAssertEqual(pixel(atX: 1, y: 0, in: result), .green)
        XCTAssertEqual(pixel(atX: 0, y: 1, in: result), .blue)
        XCTAssertEqual(pixel(atX: 1, y: 1, in: result), .yellow)
    }

    func testCropSelectionAcrossDisplaysPreservesPlacementAndOrientation() throws {
        let leftImage = makeImage(rows: [
            [.red, .green],
            [.blue, .yellow],
        ])
        let rightImage = makeImage(rows: [
            [.cyan, .magenta],
            [.black, .white],
        ])
        let leftDisplay = ScreenshotDisplay(
            id: 1,
            name: "Left",
            frame: CGRect(x: 0, y: 0, width: 2, height: 2),
            scale: 1,
            isPrimary: true
        )
        let rightDisplay = ScreenshotDisplay(
            id: 2,
            name: "Right",
            frame: CGRect(x: 2, y: 0, width: 2, height: 2),
            scale: 1,
            isPrimary: false
        )
        let state = SelectionState(
            displayFrame: CGRect(x: 0, y: 0, width: 4, height: 2),
            displayScale: 1,
            startPoint: .zero,
            currentPoint: CGPoint(x: 4, y: 2)
        )

        let result = try XCTUnwrap(ScreenshotSelectionImageComposer.cropSelection(
            state,
            from: [
                ScreenshotDisplayFrame(display: leftDisplay, image: leftImage),
                ScreenshotDisplayFrame(display: rightDisplay, image: rightImage),
            ]
        ))

        XCTAssertEqual((0..<4).map { pixel(atX: $0, y: 0, in: result) }, [.red, .green, .cyan, .magenta])
        XCTAssertEqual((0..<4).map { pixel(atX: $0, y: 1, in: result) }, [.blue, .yellow, .black, .white])
    }

    func testDefaultCaptureReturnsCroppedSelectionWithoutOpeningAnnotationEditor() async throws {
        let sourceImage = makeImage(width: 20, height: 20)
        let editor = FakeAnnotationEditor()
        let display = ScreenshotDisplay(
            id: 1,
            name: "Display",
            frame: CGRect(x: 0, y: 0, width: 20, height: 20),
            scale: 1,
            isPrimary: true
        )
        let frameProvider = ScreenCaptureFrameProvider(
            displayLoader: { [display] },
            displayCapture: { _, _ in sourceImage }
        )
        let provider = VoxFlowInteractiveScreenshotProvider(
            frameProvider: frameProvider,
            annotationEditor: editor,
            selectionProvider: { _ in
                .accepted(
                    SelectionState(
                        displayFrame: display.frame,
                        displayScale: display.scale,
                        startPoint: CGPoint(x: 2, y: 3),
                        currentPoint: CGPoint(x: 6, y: 8)
                    )
                )
            }
        )

        let result = try await provider.captureImage()

        XCTAssertEqual(editor.receivedImageSizes, [])
        XCTAssertEqual(result.width, 4)
        XCTAssertEqual(result.height, 5)
    }

    func testTextRecognitionSelectionReturnsCroppedImageWithTextRecognitionSource() async throws {
        let sourceImage = makeImage(width: 20, height: 20)
        let display = ScreenshotDisplay(
            id: 1,
            name: "Display",
            frame: CGRect(x: 0, y: 0, width: 20, height: 20),
            scale: 1,
            isPrimary: true
        )
        let frameProvider = ScreenCaptureFrameProvider(
            displayLoader: { [display] },
            displayCapture: { _, _ in sourceImage }
        )
        let provider = VoxFlowInteractiveScreenshotProvider(
            frameProvider: frameProvider,
            selectionProvider: { _ in
                .acceptedTextRecognition(
                    SelectionState(
                        displayFrame: display.frame,
                        displayScale: display.scale,
                        startPoint: CGPoint(x: 2, y: 3),
                        currentPoint: CGPoint(x: 6, y: 8)
                    )
                )
            }
        )

        let result = try await provider.capture()

        XCTAssertEqual(result.image.width, 4)
        XCTAssertEqual(result.image.height, 5)
        XCTAssertEqual(result.completionKind, .textRecognition)
    }

    func testCaptureCanCropSelectionSpanningMultipleDisplays() async throws {
        let leftImage = makeImage(width: 10, height: 10)
        let rightImage = makeImage(width: 10, height: 10)
        let displays = [
            ScreenshotDisplay(
                id: 1,
                name: "Left",
                frame: CGRect(x: 0, y: 0, width: 10, height: 10),
                scale: 1,
                isPrimary: true
            ),
            ScreenshotDisplay(
                id: 2,
                name: "Right",
                frame: CGRect(x: 10, y: 0, width: 10, height: 10),
                scale: 1,
                isPrimary: false
            ),
        ]
        let frameProvider = ScreenCaptureFrameProvider(
            displayLoader: { displays },
            displayCapture: { display, _ in
                display.id == 1 ? leftImage : rightImage
            }
        )
        let provider = VoxFlowInteractiveScreenshotProvider(
            frameProvider: frameProvider,
            selectionProvider: { _ in
                .accepted(
                    SelectionState(
                        displayFrame: CGRect(x: 0, y: 0, width: 20, height: 10),
                        displayScale: 1,
                        startPoint: CGPoint(x: 8, y: 2),
                        currentPoint: CGPoint(x: 12, y: 7)
                    )
                )
            }
        )

        let result = try await provider.capture()

        XCTAssertEqual(result.image.width, 4)
        XCTAssertEqual(result.image.height, 5)
        XCTAssertEqual(result.completionKind, .complete)
    }

    func testScrollingCaptureResultReturnsStitchedImageWithoutCropping() async throws {
        let sourceImage = makeImage(width: 20, height: 20)
        let stitchedImage = makeImage(width: 12, height: 80)
        let display = ScreenshotDisplay(
            id: 1,
            name: "Display",
            frame: CGRect(x: 0, y: 0, width: 20, height: 20),
            scale: 1,
            isPrimary: true
        )
        let frameProvider = ScreenCaptureFrameProvider(
            displayLoader: { [display] },
            displayCapture: { _, _ in sourceImage }
        )
        let provider = VoxFlowInteractiveScreenshotProvider(
            frameProvider: frameProvider,
            selectionProvider: { _ in
                .acceptedScrolling(ScrollingScreenshotCaptureResult(image: stitchedImage))
            }
        )

        let result = try await provider.capture()

        XCTAssertEqual(result.image.width, 12)
        XCTAssertEqual(result.image.height, 80)
        XCTAssertEqual(result.completionKind, .scrollingScreenshot)
    }

    func testInlineAnnotatedSelectionRendersAnnotationsWithoutOpeningAnnotationEditor() async throws {
        let sourceImage = makeImage(width: 20, height: 20)
        let editor = FakeAnnotationEditor()
        let renderedImage = makeImage(width: 7, height: 9)
        let renderer = CapturingAnnotationRenderer(renderedImage: renderedImage)
        var document = AnnotationDocument()
        document.add(.rectangle(RectangleAnnotationElement(rect: CGRect(x: 1, y: 2, width: 3, height: 4))))
        let display = ScreenshotDisplay(
            id: 1,
            name: "Display",
            frame: CGRect(x: 0, y: 0, width: 20, height: 20),
            scale: 1,
            isPrimary: true
        )
        let frameProvider = ScreenCaptureFrameProvider(
            displayLoader: { [display] },
            displayCapture: { _, _ in sourceImage }
        )
        let provider = VoxFlowInteractiveScreenshotProvider(
            frameProvider: frameProvider,
            annotationEditor: editor,
            annotationRenderer: renderer,
            selectionProvider: { _ in
                .acceptedAnnotated(
                    SelectionState(
                        displayFrame: display.frame,
                        displayScale: display.scale,
                        startPoint: CGPoint(x: 2, y: 3),
                        currentPoint: CGPoint(x: 6, y: 8)
                    ),
                    document
                )
            }
        )

        let result = try await provider.captureImage()

        XCTAssertEqual(editor.receivedImageSizes, [])
        XCTAssertEqual(renderer.receivedImageSizes, [CGSize(width: 4, height: 5)])
        XCTAssertEqual(renderer.receivedDocuments, [document])
        XCTAssertEqual(result.width, 7)
        XCTAssertEqual(result.height, 9)
    }

    func testCaptureUsesFrozenDisplayFrameWithoutSecondPostOverlayCapture() async throws {
        let sourceImage = makeImage(width: 20, height: 20)
        let editor = FakeAnnotationEditor()
        let display = ScreenshotDisplay(
            id: 1,
            name: "Display",
            frame: CGRect(x: 0, y: 0, width: 20, height: 20),
            scale: 1,
            isPrimary: true
        )
        var displayCaptureCallCount = 0
        let frameProvider = ScreenCaptureFrameProvider(
            displayLoader: { [display] },
            displayCapture: { _, _ in
                displayCaptureCallCount += 1
                return sourceImage
            }
        )
        let provider = VoxFlowInteractiveScreenshotProvider(
            frameProvider: frameProvider,
            annotationEditor: editor,
            shouldOpenAnnotationEditor: false,
            selectionProvider: { _ in
                .accepted(
                    SelectionState(
                        displayFrame: display.frame,
                        displayScale: display.scale,
                        startPoint: CGPoint(x: 2, y: 3),
                        currentPoint: CGPoint(x: 6, y: 8)
                    )
                )
            }
        )

        let result = try await provider.captureImage()

        XCTAssertEqual(displayCaptureCallCount, 1)
        XCTAssertEqual(editor.receivedImageSizes, [])
        XCTAssertEqual(result.width, 4)
        XCTAssertEqual(result.height, 5)
    }

    func testOptInAnnotationEditorCancellationCancelsCapture() async throws {
        let sourceImage = makeImage(width: 20, height: 20)
        let editor = FakeAnnotationEditor(errorToThrow: InteractiveScreenshotError.cancelled)
        let display = ScreenshotDisplay(
            id: 1,
            name: "Display",
            frame: CGRect(x: 0, y: 0, width: 20, height: 20),
            scale: 1,
            isPrimary: true
        )
        let frameProvider = ScreenCaptureFrameProvider(
            displayLoader: { [display] },
            displayCapture: { _, _ in sourceImage }
        )
        let provider = VoxFlowInteractiveScreenshotProvider(
            frameProvider: frameProvider,
            annotationEditor: editor,
            shouldOpenAnnotationEditor: true,
            selectionProvider: { _ in
                .accepted(
                    SelectionState(
                        displayFrame: display.frame,
                        displayScale: display.scale,
                        startPoint: CGPoint(x: 2, y: 3),
                        currentPoint: CGPoint(x: 6, y: 8)
                    )
                )
            }
        )

        do {
            _ = try await provider.captureImage()
            XCTFail("Expected cancellation")
        } catch let error as InteractiveScreenshotError {
            XCTAssertEqual(error, .cancelled)
        }
    }

    private func makeImage(width: Int, height: Int) -> CGImage {
        let bytesPerPixel = 4
        let data = Data(repeating: 0, count: width * height * bytesPerPixel)
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

    private func makeImage(rows: [[RGBA]]) -> CGImage {
        let width = rows[0].count
        let height = rows.count
        let data = Data(rows.flatMap { $0.flatMap(\.bytes) })
        let provider = CGDataProvider(data: data as CFData)!
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )!
    }

    private func pixel(atX x: Int, y: Int, in image: CGImage) -> RGBA {
        let data = image.dataProvider!.data! as Data
        let offset = y * image.bytesPerRow + x * 4
        return RGBA(
            red: data[offset],
            green: data[offset + 1],
            blue: data[offset + 2],
            alpha: data[offset + 3]
        )
    }
}

private struct RGBA: Equatable {
    let red: UInt8
    let green: UInt8
    let blue: UInt8
    let alpha: UInt8

    var bytes: [UInt8] { [red, green, blue, alpha] }

    static let red = RGBA(red: 255, green: 0, blue: 0, alpha: 255)
    static let green = RGBA(red: 0, green: 255, blue: 0, alpha: 255)
    static let blue = RGBA(red: 0, green: 0, blue: 255, alpha: 255)
    static let yellow = RGBA(red: 255, green: 255, blue: 0, alpha: 255)
    static let cyan = RGBA(red: 0, green: 255, blue: 255, alpha: 255)
    static let magenta = RGBA(red: 255, green: 0, blue: 255, alpha: 255)
    static let black = RGBA(red: 0, green: 0, blue: 0, alpha: 255)
    static let white = RGBA(red: 255, green: 255, blue: 255, alpha: 255)
}

@MainActor
private final class FakeAnnotationEditor: AnnotationEditing {
    private(set) var receivedImageSizes: [CGSize] = []
    private let result: CGImage?
    private let errorToThrow: Error?

    init(result: CGImage? = nil, errorToThrow: Error? = nil) {
        self.result = result
        self.errorToThrow = errorToThrow
    }

    func edit(image: CGImage) async throws -> CGImage {
        receivedImageSizes.append(CGSize(width: image.width, height: image.height))
        if let errorToThrow {
            throw errorToThrow
        }
        return result ?? image
    }
}

private final class CapturingAnnotationRenderer: AnnotationRendering {
    private(set) var receivedImageSizes: [CGSize] = []
    private(set) var receivedDocuments: [AnnotationDocument] = []
    private let renderedImage: CGImage

    init(renderedImage: CGImage) {
        self.renderedImage = renderedImage
    }

    func render(image: CGImage, document: AnnotationDocument) throws -> CGImage {
        receivedImageSizes.append(CGSize(width: image.width, height: image.height))
        receivedDocuments.append(document)
        return renderedImage
    }
}

@MainActor
private final class CancellationTrackingOverlayWindowFactory: SelectionOverlayWindowMaking {
    private(set) var windows: [CancellationTrackingOverlayWindow] = []

    func makeWindow(
        configuration: SelectionOverlayWindowConfiguration,
        eventHandler: @escaping @MainActor (SelectionOverlayWindowEvent) -> Void
    ) -> any SelectionOverlayWindowControlling {
        let window = CancellationTrackingOverlayWindow(eventHandler: eventHandler)
        windows.append(window)
        return window
    }
}

@MainActor
private final class CancellationTrackingOverlayWindow: SelectionOverlayWindowControlling {
    let savePanelHostWindow = NSWindow()
    private let eventHandler: @MainActor (SelectionOverlayWindowEvent) -> Void
    private(set) var closeCallCount = 0

    init(eventHandler: @escaping @MainActor (SelectionOverlayWindowEvent) -> Void) {
        self.eventHandler = eventHandler
    }

    func orderFront() {}
    func setVisibleForModalPresentation(_ isVisible: Bool) {}
    func updateSelection(_ state: SelectionState?) {}
    func updateAnnotationState(_ state: SelectionAnnotationOverlayState) {}
    func commitInlineTextEditing() {}
    func setWindowTargetingEnabled(_ isEnabled: Bool) {}
    func setAllowsTargetedSelectionReplacement(_ isEnabled: Bool) {}
    func setScrollCaptureActive(_ isActive: Bool, selection: SelectionState?) {}
    func close() { closeCallCount += 1 }
    func emit(_ event: SelectionOverlayWindowEvent) { eventHandler(event) }
}
