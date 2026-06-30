import AppKit
import CoreGraphics
import XCTest
@testable import VoxFlowScreenshotKit

@MainActor
final class ScrollingScreenshotPanelLayoutTests: XCTestCase {
    func testSidePreviewUsesMaximumWidthAndGrowsUpwardForLongCaptures() {
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

        let tallFrame = localFrame(of: panel, display: display)
        XCTAssertTrue(panel.ignoresMouseEvents)
        XCTAssertNil(panel.contentView?.descendant(ofType: NSScrollView.self))
        XCTAssertEqual(tallFrame.minY, 20, accuracy: 1)
        XCTAssertEqual(tallFrame.maxY, 401, accuracy: 1)
        XCTAssertEqual(tallFrame.width, 280, accuracy: 1)
        XCTAssertEqual(tallFrame.height, 381, accuracy: 1)
        XCTAssertEqual(panel.contentView?.bounds.size ?? .zero, tallFrame.size)

        panel.updatePreview(image: makeImage(width: 6_000, height: 600), scale: 2)

        let wideFrame = localFrame(of: panel, display: display)
        XCTAssertEqual(wideFrame.origin.x, tallFrame.origin.x, accuracy: 1)
        XCTAssertEqual(wideFrame.origin.y, 301, accuracy: 1)
        XCTAssertEqual(wideFrame.maxY, tallFrame.maxY, accuracy: 1)
        XCTAssertEqual(wideFrame.size.width, tallFrame.size.width, accuracy: 1)
        XCTAssertEqual(wideFrame.size.height, 100, accuracy: 1)
        XCTAssertEqual(panel.contentView?.bounds.size ?? .zero, wideFrame.size)
    }

    func testSidePreviewUsesTallViewportForRealStitchedAspectFromLogs() {
        let display = ScreenshotDisplay(
            id: 1,
            name: "Main",
            frame: CGRect(x: 0, y: 0, width: 1_512, height: 982),
            scale: 2,
            isPrimary: true
        )
        let captureRect = CGRect(x: 679.1, y: 162.5, width: 320.5, height: 273.3)
        let panel = try! XCTUnwrap(
            ScrollingScreenshotPreviewPanel(
                captureRect: captureRect,
                display: display
            )
        )

        panel.updatePreview(image: makeImage(width: 640, height: 1_511), scale: 2)

        let frame = localFrame(of: panel, display: display)
        XCTAssertEqual(frame.width, 280, accuracy: 1)
        XCTAssertEqual(frame.minY, 20, accuracy: 1)
        XCTAssertEqual(frame.maxY, captureRect.maxY + 1.25, accuracy: 1)
        XCTAssertEqual(frame.height, 417, accuracy: 1)
    }

    func testSidePreviewUsesWiderViewportForWideStitchedCaptureFromLogs() {
        let display = ScreenshotDisplay(
            id: 1,
            name: "Main",
            frame: CGRect(x: 0, y: 0, width: 1_512, height: 982),
            scale: 2,
            isPrimary: true
        )
        let captureRect = CGRect(x: 497.1, y: 227.5, width: 861.5, height: 339.5)
        let panel = try! XCTUnwrap(
            ScrollingScreenshotPreviewPanel(
                captureRect: captureRect,
                display: display
            )
        )

        panel.updatePreview(image: makeImage(width: 1_723, height: 1_972), scale: 2)

        let frame = localFrame(of: panel, display: display)
        XCTAssertEqual(frame.width, 280, accuracy: 1)
        XCTAssertGreaterThan(frame.height, 310)
        XCTAssertEqual(frame.maxY, captureRect.maxY + 1.25, accuracy: 1)
    }

    func testSidePreviewStaysInsideVisibleBoundsNearBottomRight() {
        let display = ScreenshotDisplay(
            id: 1,
            name: "Main",
            frame: CGRect(x: 0, y: 0, width: 1_200, height: 800),
            scale: 2,
            isPrimary: true
        )
        let panel = try! XCTUnwrap(
            ScrollingScreenshotPreviewPanel(
                captureRect: CGRect(x: 800, y: 700, width: 200, height: 60),
                display: display
            )
        )

        panel.updatePreview(image: makeImage(width: 600, height: 6_000), scale: 2)

        let frame = localFrame(of: panel, display: display)
        XCTAssertGreaterThanOrEqual(frame.minY, 20)
        XCTAssertLessThanOrEqual(frame.maxY, display.overlayFrame.height)
        XCTAssertGreaterThanOrEqual(frame.minX, 6)
        XCTAssertLessThanOrEqual(frame.maxX, display.overlayFrame.width - 6)
        XCTAssertEqual(frame.width, 280, accuracy: 1)
        XCTAssertEqual(frame.maxY, 761, accuracy: 1)
        XCTAssertEqual(frame.height, 741, accuracy: 1)
    }

    func testSidePreviewDrawRectFillsWidthAndAnchorsTallImages() {
        let bottomAnchoredRect = ScrollingScreenshotPreviewLayout.drawRect(
            imageSize: CGSize(width: 300, height: 3_000),
            bounds: CGRect(x: 0, y: 0, width: 280, height: 788),
            scrollAnchor: .bottom
        )
        XCTAssertEqual(bottomAnchoredRect.width, 280, accuracy: 1)
        XCTAssertGreaterThan(bottomAnchoredRect.height, 788)
        XCTAssertEqual(bottomAnchoredRect.minY, 0, accuracy: 1)

        let topAnchoredRect = ScrollingScreenshotPreviewLayout.drawRect(
            imageSize: CGSize(width: 300, height: 3_000),
            bounds: CGRect(x: 0, y: 0, width: 280, height: 788),
            scrollAnchor: .top
        )
        XCTAssertEqual(topAnchoredRect.width, 280, accuracy: 1)
        XCTAssertGreaterThan(topAnchoredRect.height, 788)
        XCTAssertEqual(topAnchoredRect.maxY, 788, accuracy: 1)
    }

    func testSidePreviewDrawRectKeepsWideImagesInsideViewport() {
        let wideRect = ScrollingScreenshotPreviewLayout.drawRect(
            imageSize: CGSize(width: 3_000, height: 300),
            bounds: CGRect(x: 0, y: 0, width: 280, height: 100),
            scrollAnchor: .bottom
        )
        XCTAssertEqual(wideRect.width, 280, accuracy: 1)
        XCTAssertEqual(wideRect.midY, 50, accuracy: 1)
        XCTAssertGreaterThanOrEqual(wideRect.minY, 0)
        XCTAssertLessThanOrEqual(wideRect.maxY, 100)
    }

    func testSidePreviewKeepsGrownDownwardCaptureVisible() {
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

        let frame = localFrame(of: panel, display: display)
        XCTAssertEqual(frame.minY, 20, accuracy: 1)
        XCTAssertEqual(frame.maxY, 401, accuracy: 1)
        XCTAssertEqual(frame.height, 381, accuracy: 1)
        XCTAssertNil(panel.contentView?.descendant(ofType: NSScrollView.self))
    }

    func testSidePreviewKeepsGrownUpwardCaptureVisible() {
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

        let frame = localFrame(of: panel, display: display)
        XCTAssertEqual(frame.minY, 20, accuracy: 1)
        XCTAssertEqual(frame.maxY, 401, accuracy: 1)
        XCTAssertEqual(frame.height, 381, accuracy: 1)
        XCTAssertNil(panel.contentView?.descendant(ofType: NSScrollView.self))
    }

    func testScrollingHUDKeepsIconControlsVisibleAboveSelectionOverlay() {
        let panel = ScrollingScreenshotHUDPanel()

        panel.update(image: makeImage(width: 3_600, height: 12_000), scale: 2)

        let buttons = panel.hudView.subviews.compactMap { $0 as? NSButton }
        let labels = panel.hudView.subviews.compactMap { $0 as? NSTextField }
        XCTAssertEqual(buttons.count, 3)
        XCTAssertTrue(labels.isEmpty)
        XCTAssertGreaterThan(panel.level.rawValue, NSWindow.Level.screenSaver.rawValue)
        XCTAssertEqual(panel.contentView?.frame.size.width ?? 0, panel.hudView.frame.width, accuracy: 1)
        XCTAssertEqual(panel.contentView?.frame.size.height ?? 0, panel.hudView.frame.height, accuracy: 1)
        XCTAssertTrue(buttons.allSatisfy { panel.hudView.bounds.contains($0.frame) })
        XCTAssertGreaterThan(panel.hudView.frame.size.width, 76)
        XCTAssertEqual(panel.hudView.frame.size.height, 44, accuracy: 1)
        XCTAssertTrue(buttons.allSatisfy { $0.title.isEmpty })
    }

    func testHUDKeepsStatusTextHiddenWhileAutoScrollButtonUpdates() {
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
        XCTAssertTrue(labels.isEmpty)
    }

    func testHUDSurfacesUnstableStateWithoutChangingThreeIconLayout() {
        let panel = ScrollingScreenshotHUDPanel()
        let image = makeImage(width: 120, height: 240)
        panel.update(
            status: ScrollingScreenshotSessionStatus(
                stripCount: 1,
                pixelHeight: 240,
                health: .good,
                isAutoScrolling: false
            ),
            image: image,
            scale: 2
        )
        let stableSize = panel.hudView.frame.size

        panel.update(
            status: ScrollingScreenshotSessionStatus(
                stripCount: 3,
                pixelHeight: 720,
                health: .unstable(reason: .bandVoteDisagreed, consecutiveFailures: 3),
                isAutoScrolling: false
            ),
            image: image,
            scale: 2
        )

        let buttons = panel.hudView.subviews.compactMap { $0 as? NSButton }
        let labels = panel.hudView.subviews.compactMap { $0 as? NSTextField }
        XCTAssertEqual(buttons.count, 3)
        XCTAssertTrue(labels.isEmpty)
        XCTAssertEqual(panel.hudView.frame.size.width, stableSize.width, accuracy: 1)
        XCTAssertEqual(panel.hudView.frame.size.height, stableSize.height, accuracy: 1)
    }

    func testHUDPlayButtonInvokesAutoScrollCallback() {
        let view = ScrollingScreenshotHUDView(frame: CGRect(x: 0, y: 0, width: 120, height: 44))
        var toggleCount = 0
        view.onToggleAutoScroll = {
            toggleCount += 1
        }

        let autoScrollButton = try! XCTUnwrap(view.subviews.compactMap { $0 as? NSButton }.first)
        autoScrollButton.performClick(nil)

        XCTAssertEqual(toggleCount, 1)
    }

    func testHUDShowsAccessibilityPermissionFailureWithoutAddingStatusText() {
        let panel = ScrollingScreenshotHUDPanel()
        let image = makeImage(width: 120, height: 240)

        panel.update(
            status: ScrollingScreenshotSessionStatus(
                stripCount: 1,
                pixelHeight: 240,
                health: .paused(reason: .captureUnavailable, consecutiveFailures: 0),
                isAutoScrolling: false
            ),
            image: image,
            scale: 2
        )

        let buttons = panel.hudView.subviews.compactMap { $0 as? NSButton }
        let labels = panel.hudView.subviews.compactMap { $0 as? NSTextField }
        let autoScrollButton = try! XCTUnwrap(buttons.first)
        XCTAssertEqual(buttons.count, 3)
        XCTAssertTrue(labels.isEmpty)
        XCTAssertNotNil(autoScrollButton.image)
    }

    func testScrollingHUDPositionsBelowSelectionWhenThereIsRoom() {
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

        let localFrame = localFrame(of: panel, display: display)
        XCTAssertEqual(localFrame.minY, selectionRect.maxY + 8, accuracy: 1)
        XCTAssertEqual(localFrame.midX, selectionRect.midX, accuracy: 1)
    }

    func testScrollingHUDFallsBackAboveSelectionWhenThereIsNoRoomBelow() {
        let display = ScreenshotDisplay(
            id: 1,
            name: "Main",
            frame: CGRect(x: 0, y: 0, width: 1_200, height: 800),
            scale: 2,
            isPrimary: true
        )
        let panel = ScrollingScreenshotHUDPanel()
        let selectionRect = CGRect(x: 200, y: 740, width: 300, height: 50)

        panel.position(relativeTo: selectionRect, display: display)

        let localFrame = localFrame(of: panel, display: display)
        XCTAssertEqual(localFrame.maxY, selectionRect.minY - 8, accuracy: 1)
        XCTAssertEqual(localFrame.midX, selectionRect.midX, accuracy: 1)
    }

    func testScrollingHUDUsesOverlayFrameWhenScreenCaptureAndAppKitOriginsDiffer() {
        let display = ScreenshotDisplay(
            id: 1,
            name: "Main",
            frame: CGRect(x: 0, y: 0, width: 1_200, height: 800),
            overlayFrame: CGRect(x: 80, y: 120, width: 1_200, height: 800),
            scale: 2,
            isPrimary: true
        )
        let panel = ScrollingScreenshotHUDPanel()
        let selectionRect = CGRect(x: 200, y: 240, width: 300, height: 300)

        panel.position(relativeTo: selectionRect, display: display)

        let localFrame = localFrame(of: panel, display: display)
        XCTAssertEqual(localFrame.minY, selectionRect.maxY + 8, accuracy: 1)
        XCTAssertEqual(localFrame.midX, selectionRect.midX, accuracy: 1)
        XCTAssertGreaterThanOrEqual(panel.frame.minX, display.overlayFrame.minX)
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
private func localFrame(of panel: NSPanel, display: ScreenshotDisplay) -> CGRect {
    CGRect(
        x: panel.frame.minX - display.overlayFrame.minX,
        y: display.overlayFrame.maxY - panel.frame.maxY,
        width: panel.frame.width,
        height: panel.frame.height
    )
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
