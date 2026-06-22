import AppKit
import CoreGraphics

// GPLv3-scoped behavior attribution:
// Adapted from sw33tLie/macshot ScrollCaptureHUDView.
// Source: https://github.com/sw33tLie/macshot
// Upstream commit: 34c9999625cfe9e8999c00358b3c172dfc00380c
// License: GPLv3

@MainActor
final class ScrollingScreenshotHUDView: NSView {
    private let cancelButton = NSButton()
    private let autoScrollButton = NSButton()
    private let stopButton = NSButton()
    private let statusLabel = NSTextField(labelWithString: "")
    private let itemSize: CGFloat = 28
    private let itemSpacing: CGFloat = 4
    private let contentPadding: CGFloat = 8
    private let labelWidth: CGFloat = 138

    var onCancel: (() -> Void)?
    var onToggleAutoScroll: (() -> Void)?
    var onStop: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 9
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.94).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.systemGreen.withAlphaComponent(0.32).cgColor

        configureIconButton(
            cancelButton,
            symbolName: "xmark",
            action: #selector(cancelClicked),
            help: "取消"
        )
        configureIconButton(
            autoScrollButton,
            symbolName: "play.fill",
            action: #selector(autoScrollClicked),
            help: "自动滚动"
        )
        configureIconButton(
            stopButton,
            symbolName: "checkmark",
            action: #selector(stopClicked),
            help: "完成"
        )

        statusLabel.font = .systemFont(ofSize: 11, weight: .medium)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.alignment = .left
        addSubview(statusLabel)
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
        statusLabel.stringValue = Self.statusText(for: status)
        autoScrollButton.image = NSImage(
            systemSymbolName: status.isAutoScrolling ? "pause.fill" : "play.fill",
            accessibilityDescription: status.isAutoScrolling ? "暂停自动滚动" : "自动滚动"
        )
        autoScrollButton.image?.isTemplate = true
        autoScrollButton.toolTip = status.isAutoScrolling ? "暂停自动滚动" : "自动滚动"
        layoutControls()
    }

    private func layoutControls() {
        let height = itemSize + contentPadding * 2
        let width = itemSize * 3 + itemSpacing * 3 + contentPadding * 2 + labelWidth
        frame.size = CGSize(width: width, height: height)
        cancelButton.frame = CGRect(
            x: contentPadding,
            y: contentPadding,
            width: itemSize,
            height: itemSize
        )
        autoScrollButton.frame = CGRect(
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
        statusLabel.frame = CGRect(
            x: contentPadding + (itemSize + itemSpacing) * 3,
            y: contentPadding,
            width: labelWidth,
            height: itemSize
        )
    }

    private static func statusText(for status: ScrollingScreenshotSessionStatus) -> String {
        switch status.health {
        case .good:
            return "已拼 \(status.stripCount) 帧 · \(status.pixelHeight) px"
        case .unstable:
            return "匹配不稳定 · 已拼 \(status.stripCount) 帧"
        case .paused:
            return "已暂停 · 匹配不稳定"
        case .reachedEnd:
            return "已到末尾 · \(status.pixelHeight) px"
        case .reachedHeightLimit:
            return "已达高度上限 · \(status.pixelHeight) px"
        }
    }

    @objc private func cancelClicked() {
        onCancel?()
    }

    @objc private func autoScrollClicked() {
        onToggleAutoScroll?()
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
        var x = selectionRect.midX - size.width / 2
        var y = selectionRect.maxY + 8
        if y + size.height > display.frame.maxY - 6 {
            y = selectionRect.minY - size.height - 8
        }
        x = min(max(x, display.frame.minX + 6), display.frame.maxX - size.width - 6)
        y = min(max(y, display.frame.minY + 6), display.frame.maxY - size.height - 6)
        contentView?.frame = CGRect(origin: .zero, size: size)
        hudView.frame.origin = .zero
        setFrame(CGRect(x: x, y: y, width: size.width, height: size.height), display: true)
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
