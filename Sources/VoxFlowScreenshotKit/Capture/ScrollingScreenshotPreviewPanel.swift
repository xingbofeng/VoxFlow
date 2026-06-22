import AppKit
import CoreGraphics

// GPLv3-scoped behavior attribution:
// Adapted from sw33tLie/macshot ScrollCapturePreviewPanel.
// Source: https://github.com/sw33tLie/macshot
// Upstream commit: 34c9999625cfe9e8999c00358b3c172dfc00380c
// License: GPLv3

enum ScrollingScreenshotPreviewScrollAnchor {
    case top
    case bottom
    case preserve
}

@MainActor
final class ScrollingScreenshotPreviewPanel: NSPanel {
    private let imageView = NSImageView()
    private let scrollView = NSScrollView()
    private let captureRect: CGRect
    private let display: ScreenshotDisplay
    private let side: Side
    private let previewWidth: CGFloat = 200
    private let margin: CGFloat = 12
    private let minHeight: CGFloat = 100
    private let maxHeight: CGFloat = 420

    private enum Side {
        case left
        case right
    }

    init?(captureRect: CGRect, display: ScreenshotDisplay) {
        self.captureRect = captureRect
        self.display = display

        let leftSpace = captureRect.minX - display.frame.minX
        let rightSpace = display.frame.maxX - captureRect.maxX
        if rightSpace >= previewWidth + margin * 2 {
            side = .right
        } else if leftSpace >= previewWidth + margin * 2 {
            side = .left
        } else {
            return nil
        }

        let x = side == .right
            ? captureRect.maxX + margin
            : captureRect.minX - margin - previewWidth
        let frame = CGRect(x: x, y: captureRect.minY, width: previewWidth, height: minHeight)
        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        ignoresMouseEvents = false

        let container = NSView(frame: CGRect(origin: .zero, size: frame.size))
        container.wantsLayer = true
        container.layer?.cornerRadius = 6
        container.layer?.masksToBounds = true
        container.autoresizingMask = [.width, .height]
        contentView = container

        scrollView.frame = container.bounds
        scrollView.autoresizingMask = [.width, .height]
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        container.addSubview(scrollView)
    }

    func updatePreview(
        image: CGImage,
        scale: CGFloat,
        scrollAnchor: ScrollingScreenshotPreviewScrollAnchor = .preserve
    ) {
        let imageSize = CGSize(
            width: CGFloat(image.width) / max(scale, 1),
            height: CGFloat(image.height) / max(scale, 1)
        )
        let imageAspect = imageSize.height / max(imageSize.width, 1)
        let documentWidth = previewWidth
        let documentHeight = max(minHeight, documentWidth * imageAspect)

        imageView.image = NSImage(
            cgImage: image,
            size: CGSize(width: documentWidth, height: documentHeight)
        )
        imageView.imageAlignment = .alignTopLeft
        imageView.imageScaling = .scaleProportionallyUpOrDown

        let x = side == .right
            ? captureRect.maxX + margin
            : captureRect.minX - margin - previewWidth
        let documentView = ScrollingScreenshotPreviewDocumentView(
            frame: CGRect(x: 0, y: 0, width: documentWidth, height: documentHeight)
        )
        imageView.frame = documentView.bounds
        documentView.addSubview(imageView)
        scrollView.documentView = documentView

        let desiredHeight = documentHeight
        let availableHeight = max(minHeight, display.frame.maxY - captureRect.minY - 20)
        let height = min(max(desiredHeight, minHeight), min(maxHeight, availableHeight))
        setFrame(
            CGRect(x: x, y: captureRect.minY, width: previewWidth, height: height),
            display: true,
            animate: false
        )
        scroll(to: scrollAnchor, documentHeight: documentHeight)
    }

    private func scroll(
        to anchor: ScrollingScreenshotPreviewScrollAnchor,
        documentHeight: CGFloat
    ) {
        let y: CGFloat
        switch anchor {
        case .top:
            y = 0
        case .bottom:
            y = max(0, documentHeight - scrollView.contentView.bounds.height)
        case .preserve:
            return
        }
        scrollView.contentView.scroll(to: CGPoint(x: 0, y: y))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }
}

private final class ScrollingScreenshotPreviewDocumentView: NSView {
    override var isFlipped: Bool { true }
}
