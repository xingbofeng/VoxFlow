import AppKit
import CoreGraphics

public struct ScreenRecordingHUDStatus: Equatable, Sendable {
    public let elapsedSeconds: TimeInterval
    public let audioMode: ScreenRecordingAudioMode

    public init(elapsedSeconds: TimeInterval, audioMode: ScreenRecordingAudioMode) {
        self.elapsedSeconds = elapsedSeconds
        self.audioMode = audioMode
    }

    var elapsedText: String {
        let totalSeconds = max(0, Int(elapsedSeconds.rounded(.down)))
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    var microphoneText: String {
        switch audioMode {
        case .none:
            return ScreenshotL10n.ScreenshotKit.Recording.Audio.none
        case .microphone:
            return ScreenshotL10n.ScreenshotKit.Recording.Audio.microphoneOn
        }
    }
}

@MainActor
final class ScreenRecordingHUDView: NSView {
    private let statusDot = NSView()
    private let elapsedLabel = NSTextField(labelWithString: "00:00")
    private let microphoneLabel = NSTextField(labelWithString: ScreenshotL10n.ScreenshotKit.Recording.Audio.none)
    private let stopButton = NSButton()
    private let itemHeight: CGFloat = 28
    private let dotSize: CGFloat = 8
    private let stopButtonSize: CGFloat = 28
    private let contentPadding: CGFloat = 8
    private let itemSpacing: CGFloat = 8

    var onStop: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 9
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.94).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.systemRed.withAlphaComponent(0.36).cgColor

        statusDot.wantsLayer = true
        statusDot.layer?.cornerRadius = dotSize / 2
        statusDot.layer?.backgroundColor = NSColor.systemRed.cgColor
        statusDot.setAccessibilityLabel(ScreenshotL10n.ScreenshotKit.Recording.Hud.Accessibility.recording)
        addSubview(statusDot)

        configureLabel(elapsedLabel, font: .monospacedDigitSystemFont(ofSize: 13, weight: .semibold))
        configureLabel(microphoneLabel, font: .systemFont(ofSize: 12, weight: .medium))
        microphoneLabel.textColor = .secondaryLabelColor

        let image = NSImage(systemSymbolName: "stop.fill", accessibilityDescription: ScreenshotL10n.ScreenshotKit.Recording.Hud.stop)
        image?.isTemplate = true
        stopButton.title = ""
        stopButton.image = image
        stopButton.imagePosition = .imageOnly
        stopButton.bezelStyle = .regularSquare
        stopButton.isBordered = false
        stopButton.wantsLayer = true
        stopButton.layer?.cornerRadius = 6
        stopButton.layer?.backgroundColor = NSColor.systemRed.withAlphaComponent(0.12).cgColor
        stopButton.contentTintColor = .systemRed
        stopButton.target = self
        stopButton.action = #selector(stopClicked)
        stopButton.toolTip = ScreenshotL10n.ScreenshotKit.Recording.Hud.stop
        addSubview(stopButton)

        layoutControls()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(status: ScreenRecordingHUDStatus) {
        elapsedLabel.stringValue = status.elapsedText
        microphoneLabel.stringValue = status.microphoneText
        layoutControls()
    }

    private func configureLabel(_ label: NSTextField, font: NSFont) {
        label.font = font
        label.textColor = .labelColor
        label.alignment = .left
        label.lineBreakMode = .byClipping
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        addSubview(label)
    }

    private func layoutControls() {
        elapsedLabel.sizeToFit()
        microphoneLabel.sizeToFit()

        let textWidth = max(elapsedLabel.frame.width, microphoneLabel.frame.width)
        let width = contentPadding
            + dotSize
            + itemSpacing
            + textWidth
            + itemSpacing
            + stopButtonSize
            + contentPadding
        let height = itemHeight + contentPadding * 2
        frame.size = CGSize(width: width, height: height)

        statusDot.frame = CGRect(
            x: contentPadding,
            y: (height - dotSize) / 2,
            width: dotSize,
            height: dotSize
        )
        elapsedLabel.frame = CGRect(
            x: statusDot.frame.maxX + itemSpacing,
            y: contentPadding + 12,
            width: textWidth,
            height: 16
        )
        microphoneLabel.frame = CGRect(
            x: elapsedLabel.frame.minX,
            y: contentPadding - 1,
            width: textWidth,
            height: 14
        )
        stopButton.frame = CGRect(
            x: elapsedLabel.frame.maxX + itemSpacing,
            y: contentPadding,
            width: stopButtonSize,
            height: stopButtonSize
        )
    }

    @objc private func stopClicked() {
        onStop?()
    }
}

@MainActor
public final class ScreenRecordingHUDPanel: NSPanel {
    let hudView = ScreenRecordingHUDView(frame: CGRect(x: 0, y: 0, width: 140, height: 44))

    public init() {
        super.init(
            contentRect: CGRect(x: 0, y: 0, width: 140, height: 44),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        sharingType = .none
        level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 2)
        hidesOnDeactivate = false
        contentView = NSView(frame: contentRect(forFrameRect: frame))
        contentView?.addSubview(hudView)
        update(status: ScreenRecordingHUDStatus(elapsedSeconds: 0, audioMode: .none))
    }

    public override var canBecomeKey: Bool { false }

    public func update(status: ScreenRecordingHUDStatus) {
        hudView.update(status: status)
        contentView?.frame = CGRect(origin: .zero, size: hudView.frame.size)
        hudView.frame.origin = .zero
        setFrame(CGRect(origin: frame.origin, size: hudView.frame.size), display: true)
    }

    public func position(relativeTo selectionRect: CGRect, display: ScreenshotDisplay) {
        update(status: ScreenRecordingHUDStatus(elapsedSeconds: 0, audioMode: .none))
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
        setFrame(screenFrame, display: true)
    }

    public func setStopHandler(_ handler: @escaping @MainActor () -> Void) {
        hudView.onStop = handler
    }
}
