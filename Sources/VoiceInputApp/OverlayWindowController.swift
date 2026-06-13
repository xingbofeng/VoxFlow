import AppKit

/// Manages the floating capsule overlay window that displays real-time transcription
/// with an animated waveform during voice recording.
final class OverlayWindowController: NSWindowController {
    // MARK: - UI Components

    private let waveformView = WaveformView(frame: NSRect(x: 0, y: 0, width: 44, height: 32))
    private let textLabel = NSTextField(labelWithString: "")
    private let refiningSpinner = NSProgressIndicator()
    private let visualEffectView = NSVisualEffectView()

    // MARK: - Temporary Message

    private var temporaryMessageTask: Task<Void, Never>?

    // MARK: - Initialization

    init() {
        let window = OverlayPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init(window: window)
        setupWindow()
        setupContentView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Window Setup

    private func setupWindow() {
        guard let window = window as? OverlayPanel else { return }

        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        window.hasShadow = true
        window.isMovableByWindowBackground = false
        window.alphaValue = 0.0
        window.ignoresMouseEvents = true
    }

    // MARK: - Content View Setup

    private func setupContentView() {
        guard let window = window else { return }

        // Visual effect view (hudWindow material for dark, frosted look)
        visualEffectView.material = .hudWindow
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.state = .active
        visualEffectView.wantsLayer = true
        visualEffectView.layer?.cornerRadius = OverlayLayout.cornerRadius
        visualEffectView.layer?.masksToBounds = true
        visualEffectView.translatesAutoresizingMaskIntoConstraints = false

        window.contentView = visualEffectView

        // Waveform view
        waveformView.translatesAutoresizingMaskIntoConstraints = false
        visualEffectView.addSubview(waveformView)

        // Text label — multi-line with word wrapping for long transcription
        textLabel.translatesAutoresizingMaskIntoConstraints = false
        textLabel.isBezeled = false
        textLabel.isEditable = false
        textLabel.drawsBackground = false
        textLabel.textColor = NSColor.white.withAlphaComponent(0.92)
        textLabel.font = NSFont.systemFont(ofSize: 16, weight: .medium)
        textLabel.lineBreakMode = .byWordWrapping
        textLabel.maximumNumberOfLines = OverlayLayout.maxVisibleLines
        textLabel.alignment = .left
        textLabel.cell?.wraps = true
        textLabel.cell?.isScrollable = false
        textLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        visualEffectView.addSubview(textLabel)

        // Refining spinner (hidden by default)
        refiningSpinner.style = .spinning
        refiningSpinner.controlSize = .small
        refiningSpinner.translatesAutoresizingMaskIntoConstraints = false
        refiningSpinner.isHidden = true
        visualEffectView.addSubview(refiningSpinner)

        // Layout — vertical padding and variable-height text
        NSLayoutConstraint.activate([
            // Waveform: top of content area, left-aligned
            waveformView.leadingAnchor.constraint(
                equalTo: visualEffectView.leadingAnchor,
                constant: OverlayLayout.horizontalPadding
            ),
            waveformView.topAnchor.constraint(
                equalTo: visualEffectView.topAnchor,
                constant: OverlayLayout.verticalPadding
            ),
            waveformView.widthAnchor.constraint(equalToConstant: OverlayLayout.waveformWidth),
            waveformView.heightAnchor.constraint(equalToConstant: OverlayLayout.waveformHeight),

            // Text label: right of waveform, vertically fills available space
            textLabel.leadingAnchor.constraint(
                equalTo: waveformView.trailingAnchor,
                constant: OverlayLayout.interSpacing
            ),
            textLabel.topAnchor.constraint(
                equalTo: visualEffectView.topAnchor,
                constant: OverlayLayout.verticalPadding
            ),
            textLabel.trailingAnchor.constraint(
                equalTo: visualEffectView.trailingAnchor,
                constant: -OverlayLayout.horizontalPadding
            ),
            textLabel.bottomAnchor.constraint(
                lessThanOrEqualTo: visualEffectView.bottomAnchor,
                constant: -OverlayLayout.verticalPadding
            ),

            // Refining spinner occupies the waveform slot.
            refiningSpinner.centerXAnchor.constraint(equalTo: waveformView.centerXAnchor),
            refiningSpinner.centerYAnchor.constraint(equalTo: waveformView.centerYAnchor),
        ])
    }

    // MARK: - Sizing

    private func updateWindowSize(textWidth: CGFloat, textHeight: CGFloat = 0) {
        guard let window = window else { return }

        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame

        let windowWidth = ceil(OverlayLayout.windowWidth(textWidth: textWidth))
        let windowHeight = OverlayLayout.windowHeight(textHeight: textHeight)
        let x = screenFrame.midX - windowWidth / 2
        // Position from bottom; move up slightly if window is taller
        let y = screenFrame.minY + max(24, 40 - (windowHeight - OverlayLayout.minimumCapsuleHeight) / 2)

        let frame = NSRect(x: x, y: y, width: windowWidth, height: windowHeight)
        window.setFrame(frame, display: true, animate: false)
    }

    // MARK: - Public API

    func show() {
        guard let window = window else { return }
        temporaryMessageTask?.cancel()
        temporaryMessageTask = nil

        // Calculate initial size for empty text
        updateWindowSize(textWidth: OverlayLayout.minimumTextWidth)

        waveformView.isHidden = false
        waveformView.reset()
        waveformView.startAnimation()
        refiningSpinner.isHidden = true
        refiningSpinner.stopAnimation(nil)

        present(window)
    }

    private func present(_ window: NSWindow) {
        window.orderFront(nil)

        if let layer = visualEffectView.layer {
            let spring = CASpringAnimation(keyPath: "transform.scale")
            spring.fromValue = 0.82
            spring.toValue = 1.0
            spring.mass = 1
            spring.stiffness = 320
            spring.damping = 24
            spring.initialVelocity = 0
            spring.duration = 0.35
            layer.add(spring, forKey: "voiceinput.entrance")
        }

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1.0
        }
    }

    func updateTranscription(_ text: String, isRefining: Bool) {
        let displayText: String
        if isRefining {
            displayText = text.isEmpty ? "Refining..." : text
            textLabel.textColor = NSColor.white.withAlphaComponent(0.5)
            waveformView.stopAnimation()
            waveformView.isHidden = true
            refiningSpinner.isHidden = false
            refiningSpinner.startAnimation(nil)
        } else {
            displayText = text.isEmpty ? "正在聆听..." : text
            textLabel.textColor = NSColor.white.withAlphaComponent(0.92)
            waveformView.isHidden = false
            waveformView.startAnimation()
            refiningSpinner.isHidden = true
            refiningSpinner.stopAnimation(nil)
        }
        textLabel.stringValue = displayText

        let textSize = (displayText as NSString).boundingRect(
            with: NSSize(
                width: OverlayLayout.maximumTextWidth,
                height: CGFloat.greatestFiniteMagnitude
            ),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: textLabel.font as Any]
        )
        let newTextWidth = textSize.width + 8
        let newTextHeight = textSize.height + 8

        guard let window = window else { return }
        let totalWidth = OverlayLayout.windowWidth(textWidth: newTextWidth)
        let totalHeight = OverlayLayout.windowHeight(textHeight: newTextHeight)

        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame

        let newFrame = NSRect(
            x: screenFrame.midX - totalWidth / 2,
            y: screenFrame.minY + max(24, 40 - (totalHeight - OverlayLayout.minimumCapsuleHeight) / 2),
            width: totalWidth,
            height: totalHeight
        )

        // Smooth width transition (0.25s)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(newFrame, display: true)
        }
    }

    func updateRMS(_ rms: Float) {
        waveformView.updateRMS(rms)
    }

    /// Displays a temporary error/info message in the overlay that auto-dismisses
    /// after `duration` seconds. Used for non-blocking error feedback.
    func showTemporaryMessage(_ text: String, duration: TimeInterval = 3.0) {
        temporaryMessageTask?.cancel()

        waveformView.stopAnimation()
        waveformView.isHidden = true
        refiningSpinner.isHidden = true
        refiningSpinner.stopAnimation(nil)

        textLabel.stringValue = text
        textLabel.textColor = NSColor(red: 1.0, green: 0.78, blue: 0.38, alpha: 1.0)  // warm amber

        let textSize = (text as NSString).boundingRect(
            with: NSSize(
                width: OverlayLayout.maximumTextWidth,
                height: CGFloat.greatestFiniteMagnitude
            ),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: textLabel.font as Any]
        )
        updateWindowSize(textWidth: textSize.width + 8, textHeight: textSize.height + 8)
        guard let window else { return }
        present(window)

        temporaryMessageTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            self.dismiss()
        }
    }

    func dismiss() {
        guard let window = window else { return }

        waveformView.stopAnimation()
        if let layer = visualEffectView.layer {
            let scale = CABasicAnimation(keyPath: "transform.scale")
            scale.fromValue = 1.0
            scale.toValue = 0.86
            scale.duration = 0.22
            scale.timingFunction = CAMediaTimingFunction(name: .easeIn)
            layer.add(scale, forKey: "voiceinput.exit")
        }

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().alphaValue = 0.0
        } completionHandler: {
            MainActor.assumeIsolated {
                window.orderOut(nil)
                self.visualEffectView.layer?.removeAnimation(forKey: "voiceinput.exit")
            }
        }
    }

    /// Returns the current transcription text shown in the overlay.
    var currentText: String {
        textLabel.stringValue
    }
}

// MARK: - Overlay NSPanel

/// A borderless, non-activating NSPanel that floats above other windows.
private final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}
