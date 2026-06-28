import AppKit
import CoreGraphics

// GPLv3-scoped behavior attribution:
// Adapted from sw33tLie/macshot ScrollCaptureHUDView.
// Source: https://github.com/sw33tLie/macshot
// Upstream commit: b8ebcb454f957fda011821fbf9c104580592d135
// License: GPLv3

@MainActor
final class ScrollingScreenshotHUDView: NSView {
    private let autoScrollButton = NSButton()
    private let cancelButton = NSButton()
    private let stopButton = NSButton()
    private let itemSize: CGFloat = 28
    private let itemSpacing: CGFloat = 4
    private let contentPadding: CGFloat = 8

    var onToggleAutoScroll: (() -> Void)?
    var onCancel: (() -> Void)?
    var onStop: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 9
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.94).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.systemGreen.withAlphaComponent(0.32).cgColor

        configureIconButton(
            autoScrollButton,
            symbolName: "play.fill",
            action: #selector(autoScrollClicked),
            help: ScreenshotL10n.ScreenshotKit.Scrolling.Help.autoScroll
        )
        configureIconButton(
            cancelButton,
            symbolName: "xmark",
            action: #selector(cancelClicked),
            help: ScreenshotL10n.ScreenshotKit.Toolbar.cancel
        )
        configureIconButton(
            stopButton,
            symbolName: "checkmark",
            action: #selector(stopClicked),
            help: ScreenshotL10n.ScreenshotKit.Toolbar.complete
        )
    }

    private func configureIconButton(
        _ button: NSButton,
        symbolName: String,
        action: Selector,
        help: String
    ) {
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: help)
        image?.isTemplate = true
        button.title = ""
        button.image = image
        button.imagePosition = .imageOnly
        button.bezelStyle = .regularSquare
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.cornerRadius = 6
        button.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.04).cgColor
        button.contentTintColor = .labelColor
        button.target = self
        button.action = action
        button.toolTip = help
        addSubview(button)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(status: ScrollingScreenshotSessionStatus, image: CGImage?, scale: CGFloat) {
        let isPermissionBlocked: Bool = {
            guard case .paused(reason: .captureUnavailable, consecutiveFailures: _) = status.health else {
                return false
            }
            return !status.isAutoScrolling
        }()
        let symbolName = if isPermissionBlocked {
            "exclamationmark.triangle.fill"
        } else {
            status.isAutoScrolling ? "pause.fill" : "play.fill"
        }
        let help = helpText(for: status, isPermissionBlocked: isPermissionBlocked)
        autoScrollButton.image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: help
        )
        autoScrollButton.image?.isTemplate = true
        autoScrollButton.contentTintColor = tintColor(for: status, isPermissionBlocked: isPermissionBlocked)
        autoScrollButton.toolTip = help
        layer?.borderColor = borderColor(for: status, isPermissionBlocked: isPermissionBlocked).cgColor
        layoutControls()
    }

    private func helpText(
        for status: ScrollingScreenshotSessionStatus,
        isPermissionBlocked: Bool
    ) -> String {
        if isPermissionBlocked {
            return ScreenshotL10n.ScreenshotKit.Scrolling.Help.accessibilityRequired
        }
        switch status.health {
        case .good:
            return status.isAutoScrolling ? ScreenshotL10n.ScreenshotKit.Scrolling.Help.pauseAutoScroll : ScreenshotL10n.ScreenshotKit.Scrolling.Help.autoScroll
        case .unstable:
            return ScreenshotL10n.ScreenshotKit.Scrolling.Help.unstable
        case .paused:
            return ScreenshotL10n.ScreenshotKit.Scrolling.Help.pausedUnstable
        case .reachedEnd:
            return ScreenshotL10n.ScreenshotKit.Scrolling.Help.reachedEnd
        case .reachedHeightLimit:
            return ScreenshotL10n.ScreenshotKit.Scrolling.Help.heightLimit
        }
    }

    private func tintColor(
        for status: ScrollingScreenshotSessionStatus,
        isPermissionBlocked: Bool
    ) -> NSColor {
        if isPermissionBlocked {
            return .systemOrange
        }
        switch status.health {
        case .good:
            return .labelColor
        case .unstable, .paused, .reachedEnd, .reachedHeightLimit:
            return .systemOrange
        }
    }

    private func borderColor(
        for status: ScrollingScreenshotSessionStatus,
        isPermissionBlocked: Bool
    ) -> NSColor {
        if isPermissionBlocked {
            return .systemOrange.withAlphaComponent(0.42)
        }
        switch status.health {
        case .good:
            return .systemGreen.withAlphaComponent(0.32)
        case .unstable, .paused:
            return .systemOrange.withAlphaComponent(0.42)
        case .reachedEnd, .reachedHeightLimit:
            return .systemBlue.withAlphaComponent(0.36)
        }
    }

    private func layoutControls() {
        let height = itemSize + contentPadding * 2
        let width = itemSize * 3 + itemSpacing * 2 + contentPadding * 2
        frame.size = CGSize(width: width, height: height)
        autoScrollButton.frame = CGRect(
            x: contentPadding,
            y: contentPadding,
            width: itemSize,
            height: itemSize
        )
        cancelButton.frame = CGRect(
            x: contentPadding + itemSize + itemSpacing,
            y: contentPadding,
            width: itemSize,
            height: itemSize
        )
        stopButton.frame = CGRect(
            x: contentPadding + (itemSize + itemSpacing) * 2,
            y: contentPadding,
            width: itemSize,
            height: itemSize
        )
    }

    @objc private func autoScrollClicked() {
        ScrollingScreenshotDiagnostics.logger.info("scrolling_hud_autoscroll_clicked")
        onToggleAutoScroll?()
    }

    @objc private func cancelClicked() {
        onCancel?()
    }

    @objc private func stopClicked() {
        onStop?()
    }
}

@MainActor
final class ScrollingScreenshotHUDPanel: NSPanel {
    let hudView = ScrollingScreenshotHUDView(frame: CGRect(x: 0, y: 0, width: 76, height: 44))

    init() {
        super.init(
            contentRect: CGRect(x: 0, y: 0, width: 76, height: 44),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 2)
        hidesOnDeactivate = false
        contentView = NSView(frame: contentRect(forFrameRect: frame))
        contentView?.addSubview(hudView)
    }

    override var canBecomeKey: Bool { false }

    func update(image: CGImage, scale: CGFloat) {
        update(
            status: ScrollingScreenshotSessionStatus(
                stripCount: 1,
                pixelHeight: image.height,
                health: .good,
                isAutoScrolling: false
            ),
            image: image,
            scale: scale
        )
    }

    func update(status: ScrollingScreenshotSessionStatus, image: CGImage?, scale: CGFloat) {
        hudView.update(status: status, image: image, scale: scale)
        contentView?.frame = CGRect(origin: .zero, size: hudView.frame.size)
        hudView.frame.origin = .zero
        setFrame(CGRect(origin: frame.origin, size: hudView.frame.size), display: true)
    }

    func position(relativeTo selectionRect: CGRect, display: ScreenshotDisplay) {
        let image = emptyImage()
        update(image: image, scale: display.scale)
        let size = hudView.frame.size
        let localSelectionRect = ScrollingScreenshotPanelGeometry.localRect(
            for: selectionRect,
            display: display
        )
        let visibleBounds = CGRect(origin: .zero, size: display.overlayFrame.size)
        var x = localSelectionRect.midX - size.width / 2
        var y = localSelectionRect.maxY + 8
        if y + size.height > visibleBounds.maxY - 6 {
            y = localSelectionRect.minY - size.height - 8
        }
        x = min(max(x, visibleBounds.minX + 6), visibleBounds.maxX - size.width - 6)
        y = min(max(y, visibleBounds.minY + 6), visibleBounds.maxY - size.height - 6)
        contentView?.frame = CGRect(origin: .zero, size: size)
        hudView.frame.origin = .zero
        let screenFrame = ScrollingScreenshotPanelGeometry.screenRect(
            forLocalRect: CGRect(x: x, y: y, width: size.width, height: size.height),
            display: display
        )
        ScrollingScreenshotDiagnostics.logger.info(
            "scrolling_hud_position selection=\(ScrollingScreenshotDiagnostics.rect(selectionRect), privacy: .public) localSelection=\(ScrollingScreenshotDiagnostics.rect(localSelectionRect), privacy: .public) localFrame=\(ScrollingScreenshotDiagnostics.rect(CGRect(x: x, y: y, width: size.width, height: size.height)), privacy: .public) screenFrame=\(ScrollingScreenshotDiagnostics.rect(screenFrame), privacy: .public) displayFrame=\(ScrollingScreenshotDiagnostics.rect(display.frame), privacy: .public) overlayFrame=\(ScrollingScreenshotDiagnostics.rect(display.overlayFrame), privacy: .public)"
        )
        setFrame(screenFrame, display: true)
    }

    private func emptyImage() -> CGImage {
        let data = Data(repeating: 0, count: 4)
        let provider = CGDataProvider(data: data as CFData)!
        return CGImage(
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )!
    }
}
