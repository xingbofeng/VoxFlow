import AppKit
import CoreGraphics

// GPLv3-scoped behavior attribution:
// Adapted from sw33tLie/macshot ScrollCapturePreviewPanel.
// Source: https://github.com/sw33tLie/macshot
// Upstream commit: b8ebcb454f957fda011821fbf9c104580592d135
// License: GPLv3

enum ScrollingScreenshotPreviewScrollAnchor {
    case top
    case bottom
    case preserve
}

@MainActor
final class ScrollingScreenshotPreviewPanel: NSPanel {
    private let imageView = ScrollingScreenshotPreviewImageView()
    private let captureRect: CGRect
    private let display: ScreenshotDisplay
    private let side: Side
    private let previewWidth: CGFloat
    private static let margin: CGFloat = 12

    private enum Side {
        case left
        case right
    }

    init?(captureRect: CGRect, display: ScreenshotDisplay) {
        self.display = display
        let localCaptureRect = ScrollingScreenshotPanelGeometry.localRect(
            for: captureRect,
            display: display
        )
        self.captureRect = localCaptureRect
        let visibleBounds = CGRect(origin: .zero, size: display.overlayFrame.size)

        let leftSpace = localCaptureRect.minX - visibleBounds.minX
        let rightSpace = visibleBounds.maxX - localCaptureRect.maxX
        if let width = ScrollingScreenshotPreviewLayout.previewWidth(
            availableSideSpace: rightSpace,
            margin: Self.margin
        ) {
            side = .right
            previewWidth = width
        } else if let width = ScrollingScreenshotPreviewLayout.previewWidth(
            availableSideSpace: leftSpace,
            margin: Self.margin
        ) {
            side = .left
            previewWidth = width
        } else {
            return nil
        }

        let previewSize = CGSize(
            width: previewWidth,
            height: ScrollingScreenshotPreviewLayout.minHeight
        )
        let x = side == .right
            ? localCaptureRect.maxX + Self.margin
            : localCaptureRect.minX - Self.margin - previewSize.width
        let y = ScrollingScreenshotPreviewLayout.bottomAnchoredY(
            height: previewSize.height,
            anchorBottomY: ScrollingScreenshotPreviewLayout.anchorBottomY(for: localCaptureRect),
            visibleBounds: visibleBounds
        )
        let localFrame = CGRect(x: x, y: y, width: previewSize.width, height: previewSize.height)
        let frame = ScrollingScreenshotPanelGeometry.screenRect(forLocalRect: localFrame, display: display)
        ScrollingScreenshotDiagnostics.logger.info(
            "scrolling_preview_init capture=\(ScrollingScreenshotDiagnostics.rect(captureRect), privacy: .public) localCapture=\(ScrollingScreenshotDiagnostics.rect(localCaptureRect), privacy: .public) localFrame=\(ScrollingScreenshotDiagnostics.rect(localFrame), privacy: .public) screenFrame=\(ScrollingScreenshotDiagnostics.rect(frame), privacy: .public) side=\(String(describing: self.side), privacy: .public)"
        )
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
        ignoresMouseEvents = true

        let container = NSView(frame: CGRect(origin: .zero, size: frame.size))
        container.wantsLayer = true
        container.layer?.cornerRadius = 6
        container.layer?.masksToBounds = true
        container.autoresizingMask = [.width, .height]
        contentView = container

        imageView.frame = container.bounds
        imageView.autoresizingMask = [.width, .height]
        container.addSubview(imageView)
    }

    func updatePreview(
        image: CGImage,
        scale: CGFloat,
        scrollAnchor: ScrollingScreenshotPreviewScrollAnchor = .preserve
    ) {
        let visibleBounds = CGRect(origin: .zero, size: display.overlayFrame.size)
        let imageSize = CGSize(
            width: CGFloat(image.width) / max(scale, 1),
            height: CGFloat(image.height) / max(scale, 1)
        )
        let previewSize = ScrollingScreenshotPreviewLayout.viewportSize(
            imageSize: imageSize,
            width: previewWidth,
            anchorBottomY: ScrollingScreenshotPreviewLayout.anchorBottomY(for: captureRect),
            visibleBounds: visibleBounds
        )
        let x = side == .right
            ? captureRect.maxX + Self.margin
            : captureRect.minX - Self.margin - previewSize.width
        let y = ScrollingScreenshotPreviewLayout.bottomAnchoredY(
            height: previewSize.height,
            anchorBottomY: ScrollingScreenshotPreviewLayout.anchorBottomY(for: captureRect),
            visibleBounds: visibleBounds
        )
        imageView.update(image: image, scale: scale, scrollAnchor: scrollAnchor)

        let localFrame = CGRect(x: x, y: y, width: previewSize.width, height: previewSize.height)
        let screenFrame = ScrollingScreenshotPanelGeometry.screenRect(
            forLocalRect: localFrame,
            display: display
        )
        ScrollingScreenshotDiagnostics.logger.info(
            "scrolling_preview_update image=\(ScrollingScreenshotDiagnostics.size(image), privacy: .public) localFrame=\(ScrollingScreenshotDiagnostics.rect(localFrame), privacy: .public) screenFrame=\(ScrollingScreenshotDiagnostics.rect(screenFrame), privacy: .public) anchor=\(String(describing: scrollAnchor), privacy: .public)"
        )
        setFrame(
            screenFrame,
            display: true,
            animate: false
        )
        imageView.frame = contentView?.bounds ?? CGRect(origin: .zero, size: previewSize)
    }
}

enum ScrollingScreenshotPreviewLayout {
    static let minWidth: CGFloat = 200
    static let maxWidth: CGFloat = 280
    static let minHeight: CGFloat = 100
    static let edgeInset: CGFloat = 6
    static let topInset: CGFloat = 20
    static let contentInset: CGFloat = 8
    static let selectionBorderOutset: CGFloat = 1.25

    static func previewWidth(availableSideSpace: CGFloat, margin: CGFloat) -> CGFloat? {
        let usableWidth = availableSideSpace - margin * 2
        guard usableWidth >= minWidth else { return nil }
        return min(maxWidth, usableWidth)
    }

    static func viewportSize(
        imageSize: CGSize,
        width: CGFloat = maxWidth,
        anchorBottomY: CGFloat,
        visibleBounds: CGRect
    ) -> CGSize {
        let aspect = imageSize.height / max(imageSize.width, 1)
        let contentWidth = max(width - contentInset, 1)
        let desiredHeight = max(minHeight, contentWidth * max(aspect, 0.01) + contentInset)
        let availableHeight = max(
            minHeight,
            anchorBottomY - (visibleBounds.minY + topInset)
        )
        return CGSize(width: width, height: min(desiredHeight, availableHeight))
    }

    static func anchorBottomY(for captureRect: CGRect) -> CGFloat {
        captureRect.maxY + selectionBorderOutset
    }

    static func bottomAnchoredY(
        height: CGFloat,
        anchorBottomY: CGFloat,
        visibleBounds: CGRect
    ) -> CGFloat {
        let preferredY = anchorBottomY - height
        let lowerBound = visibleBounds.minY + topInset
        let upperBound = visibleBounds.maxY - height - edgeInset
        guard upperBound >= lowerBound else {
            return lowerBound
        }
        return min(max(preferredY, lowerBound), upperBound)
    }

    static func drawRect(
        imageSize: CGSize,
        bounds: CGRect,
        scrollAnchor: ScrollingScreenshotPreviewScrollAnchor = .preserve
    ) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0, bounds.width > 0, bounds.height > 0 else {
            return .zero
        }

        let scale = bounds.width / imageSize.width
        let drawSize = CGSize(
            width: imageSize.width * scale,
            height: imageSize.height * scale
        )
        let y: CGFloat
        if drawSize.height <= bounds.height {
            y = bounds.midY - drawSize.height / 2
        } else {
            y = switch scrollAnchor {
            case .top:
                bounds.maxY - drawSize.height
            case .bottom:
                bounds.minY
            case .preserve:
                bounds.midY - drawSize.height / 2
            }
        }
        return CGRect(
            x: bounds.midX - drawSize.width / 2,
            y: y,
            width: drawSize.width,
            height: drawSize.height
        )
    }

}

@MainActor
private final class ScrollingScreenshotPreviewImageView: NSView {
    private var image: CGImage?
    private var imageScale: CGFloat = 1
    private var scrollAnchor: ScrollingScreenshotPreviewScrollAnchor = .preserve

    func update(
        image: CGImage,
        scale: CGFloat,
        scrollAnchor: ScrollingScreenshotPreviewScrollAnchor
    ) {
        self.image = image
        self.imageScale = max(scale, 1)
        self.scrollAnchor = scrollAnchor
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.white.setFill()
        bounds.fill()

        guard let image, bounds.width > 0, bounds.height > 0 else { return }

        let imageSize = CGSize(
            width: CGFloat(image.width) / imageScale,
            height: CGFloat(image.height) / imageScale
        )
        guard imageSize.width > 0, imageSize.height > 0 else { return }

        let nsImage = NSImage(cgImage: image, size: imageSize)
        nsImage.draw(
            in: ScrollingScreenshotPreviewLayout.drawRect(
                imageSize: imageSize,
                bounds: bounds,
                scrollAnchor: scrollAnchor
            ),
            from: .zero,
            operation: .sourceOver,
            fraction: 1
        )
    }
}
