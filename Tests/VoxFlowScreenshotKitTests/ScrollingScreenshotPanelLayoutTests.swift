import AppKit
import CoreGraphics
import XCTest
@testable import VoxFlowScreenshotKit

@MainActor
final class ScrollingScreenshotPanelLayoutTests: XCTestCase {
    func testConfirmationPanelUsesBoundedScrollablePreviewAndCanBecomeKey() {
        let panel = ScrollingScreenshotConfirmationPanel(
            image: makeImage(width: 2_400, height: 12_000),
            request: makeRequest(displaySize: CGSize(width: 1_440, height: 900), selectionSize: CGSize(width: 1_100, height: 500)),
            imageSaver: CapturingImageSaver(),
            annotationEditor: CapturingAnnotationEditor(),
            onAction: { _ in }
        )

        XCTAssertLessThanOrEqual(panel.frame.width, 760)
        XCTAssertLessThanOrEqual(panel.frame.height, 620)
        XCTAssertFalse(panel.styleMask.contains(.nonactivatingPanel))
        XCTAssertTrue(panel.canBecomeKey)

        let scrollView = try! XCTUnwrap(panel.contentView?.descendant(ofType: NSScrollView.self))
        XCTAssertTrue(scrollView.hasVerticalScroller)
        XCTAssertTrue(scrollView.hasHorizontalScroller)
        XCTAssertGreaterThan(scrollView.documentView?.frame.height ?? 0, scrollView.contentView.bounds.height)
    }

    func testSidePreviewUsesScrollableImageInsteadOfShrinkingLongCaptureToTinyStrip() {
        let display = ScreenshotDisplay(
            id: 1,
            name: "Main",
            frame: CGRect(x: 0, y: 0, width: 1_200, height: 800),
            scale: 2,
            isPrimary: true
        )
        let panel = try! XCTUnwrap(
            ScrollingScreenshotPreviewPanel(
                captureRect: CGRect(x: 200, y: 100, width: 300, height: 300),
                display: display
            )
        )

        panel.updatePreview(image: makeImage(width: 600, height: 6_000), scale: 2)

        let scrollView = try! XCTUnwrap(panel.contentView?.descendant(ofType: NSScrollView.self))
        XCTAssertFalse(panel.ignoresMouseEvents)
        XCTAssertTrue(scrollView.hasVerticalScroller)
        XCTAssertFalse(scrollView.hasHorizontalScroller)
        XCTAssertLessThanOrEqual(scrollView.documentView?.frame.width ?? .greatestFiniteMagnitude, scrollView.contentView.bounds.width + 1)
        XCTAssertGreaterThan(scrollView.documentView?.frame.height ?? 0, scrollView.contentView.bounds.height)
    }

    func testSidePreviewScrollsToNewestRowsWhenCaptureGrowsDownward() {
        let display = ScreenshotDisplay(
            id: 1,
            name: "Main",
            frame: CGRect(x: 0, y: 0, width: 1_200, height: 800),
            scale: 2,
            isPrimary: true
        )
        let panel = try! XCTUnwrap(
            ScrollingScreenshotPreviewPanel(
                captureRect: CGRect(x: 200, y: 100, width: 300, height: 300),
                display: display
            )
        )

        panel.updatePreview(image: makeImage(width: 600, height: 1_200), scale: 2, scrollAnchor: .bottom)
        panel.updatePreview(image: makeImage(width: 600, height: 6_000), scale: 2, scrollAnchor: .bottom)

        let scrollView = try! XCTUnwrap(panel.contentView?.descendant(ofType: NSScrollView.self))
        XCTAssertGreaterThan(scrollView.contentView.bounds.origin.y, 0)
    }

    func testSidePreviewScrollsToNewestRowsWhenCaptureGrowsUpward() {
        let display = ScreenshotDisplay(
            id: 1,
            name: "Main",
            frame: CGRect(x: 0, y: 0, width: 1_200, height: 800),
            scale: 2,
            isPrimary: true
        )
        let panel = try! XCTUnwrap(
            ScrollingScreenshotPreviewPanel(
                captureRect: CGRect(x: 200, y: 100, width: 300, height: 300),
                display: display
            )
        )

        panel.updatePreview(image: makeImage(width: 600, height: 6_000), scale: 2, scrollAnchor: .top)

        let scrollView = try! XCTUnwrap(panel.contentView?.descendant(ofType: NSScrollView.self))
        XCTAssertEqual(scrollView.contentView.bounds.origin.y, 0, accuracy: 1)
    }

    func testScrollingHUDKeepsIconControlsVisibleAboveSelectionOverlay() {
        let panel = ScrollingScreenshotHUDPanel()

        panel.update(image: makeImage(width: 3_600, height: 12_000), scale: 2)

        let buttons = panel.hudView.subviews.compactMap { $0 as? NSButton }
        let labels = panel.hudView.subviews.compactMap { $0 as? NSTextField }
        XCTAssertEqual(buttons.count, 3)
        XCTAssertFalse(labels.isEmpty)
        XCTAssertGreaterThan(panel.level.rawValue, NSWindow.Level.screenSaver.rawValue)
        XCTAssertEqual(panel.contentView?.frame.size.width ?? 0, panel.hudView.frame.width, accuracy: 1)
        XCTAssertEqual(panel.contentView?.frame.size.height ?? 0, panel.hudView.frame.height, accuracy: 1)
        XCTAssertTrue(buttons.allSatisfy { panel.hudView.bounds.contains($0.frame) })
        XCTAssertGreaterThan(panel.hudView.frame.size.width, 76)
        XCTAssertEqual(panel.hudView.frame.size.height, 44, accuracy: 1)
        XCTAssertTrue(buttons.allSatisfy { $0.title.isEmpty })
    }

    func testHUDExpandsForStatusAndAutoScrollButton() {
        let panel = ScrollingScreenshotHUDPanel()
        let image = makeImage(width: 120, height: 240)

        panel.update(
            status: ScrollingScreenshotSessionStatus(
                stripCount: 3,
                pixelHeight: 720,
                health: .unstable(reason: .bandVoteDisagreed, consecutiveFailures: 2),
                isAutoScrolling: false
            ),
            image: image,
            scale: 2
        )

        let labels = panel.hudView.subviews.compactMap { $0 as? NSTextField }
        XCTAssertGreaterThan(panel.frame.width, 76)
        XCTAssertGreaterThanOrEqual(panel.frame.height, 44)
        XCTAssertTrue(labels.contains { $0.stringValue.contains("匹配不稳定") })
    }

    func testScrollingHUDPositionsUnderSelectionUsingOverlayCoordinateSystem() {
        let display = ScreenshotDisplay(
            id: 1,
            name: "Main",
            frame: CGRect(x: 0, y: 0, width: 1_200, height: 800),
            scale: 2,
            isPrimary: true
        )
        let panel = ScrollingScreenshotHUDPanel()
        let selectionRect = CGRect(x: 200, y: 240, width: 300, height: 300)

        panel.position(relativeTo: selectionRect, display: display)

        XCTAssertEqual(panel.frame.minY, selectionRect.maxY + 8, accuracy: 1)
        XCTAssertEqual(panel.frame.midX, selectionRect.midX, accuracy: 1)
    }

    private func makeRequest(displaySize: CGSize, selectionSize: CGSize) -> ScrollingScreenshotRequest {
        let display = ScreenshotDisplay(
            id: 1,
            name: "Main",
            frame: CGRect(origin: .zero, size: displaySize),
            scale: 2,
            isPrimary: true
        )
        return ScrollingScreenshotRequest(
            selection: SelectionState(
                displayFrame: display.frame,
                displayScale: display.scale,
                startPoint: CGPoint(x: 160, y: 140),
                currentPoint: CGPoint(x: 160 + selectionSize.width, y: 140 + selectionSize.height)
            ),
            display: display
        )
    }
}

@MainActor
private final class CapturingImageSaver: AnnotationImageSaving {
    func savePNG(
        image: CGImage,
        attachedTo hostWindow: NSWindow,
        completion: @escaping (Result<Bool, Error>) -> Void
    ) {
        completion(.success(true))
    }
}

@MainActor
private final class CapturingAnnotationEditor: AnnotationEditing {
    func edit(image: CGImage) async throws -> CGImage {
        image
    }
}

private extension NSView {
    func descendant<T: NSView>(ofType type: T.Type) -> T? {
        if let view = self as? T {
            return view
        }
        for subview in subviews {
            if let match = subview.descendant(ofType: type) {
                return match
            }
        }
        return nil
    }
}

private func makeImage(width: Int, height: Int) -> CGImage {
    let bytesPerPixel = 4
    let bytesPerRow = width * bytesPerPixel
    let data = Data(repeating: 255, count: height * bytesPerRow)
    let provider = CGDataProvider(data: data as CFData)!
    return CGImage(
        width: width,
        height: height,
        bitsPerComponent: 8,
        bitsPerPixel: 32,
        bytesPerRow: bytesPerRow,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
        provider: provider,
        decode: nil,
        shouldInterpolate: false,
        intent: .defaultIntent
    )!
}
