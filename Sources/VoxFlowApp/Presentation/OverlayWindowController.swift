import AppKit

enum OverlayAppearance {
    static let backgroundColor = NSColor(
        red: 1,
        green: 1,
        blue: 1,
        alpha: 0.98
    )
}

final class VerticallyCenteredTextFieldCell: NSTextFieldCell {
    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        var drawingRect = super.drawingRect(forBounds: rect)
        let textHeight = cellSize(forBounds: rect).height
        let availableHeight = rect.height

        if textHeight < availableHeight {
            drawingRect.origin.y = rect.midY - textHeight / 2
            drawingRect.size.height = textHeight
        }
        return drawingRect
    }
}

private final class AgentCandidateButton: NSView {
    var agentID = ""
    var onSelect: ((String) -> Void)?

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard bounds.contains(point) else { return }
        onSelect?(agentID)
    }
}

private enum AgentDispatchConfirmationUtteranceFormatter {
    static let maximumDisplayedCharacters = 72

    static func displayText(
        _ text: String,
        maxCharacters: Int = maximumDisplayedCharacters
    ) -> String {
        let normalized = text
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        guard normalized.count > maxCharacters else { return normalized }

        let suffixLength = max(1, maxCharacters - 1)
        return "…" + String(normalized.suffix(suffixLength))
    }
}

/// Manages the compact floating overlay window that displays real-time transcription
/// with an animated waveform during voice recording.
final class OverlayWindowController: NSWindowController {
    // MARK: - UI Components

    private let waveformView = WaveformView(
        frame: NSRect(
            x: 0,
            y: 0,
            width: OverlayLayout.waveformWidth,
            height: OverlayLayout.waveformHeight
        )
    )
    private let indicatorBackgroundView = NSView()
    private let textLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "")
    private let refiningSpinner = NSProgressIndicator()
    private let visualEffectView = NSView()
    private let confirmationContainer = NSView()
    private let confirmationStatusLabel = NSTextField(labelWithString: "")
    private let confirmationUtteranceRow = NSView()
    private let confirmationUtteranceIconLabel = NSTextField(labelWithString: "")
    private let confirmationUtteranceLabel = NSTextField(labelWithString: "")
    private let confirmationRowsStack = NSStackView()
    private let confirmationFooterLabel = NSTextField(labelWithString: "")
    private var confirmationLayoutConstraints: [NSLayoutConstraint] = []

    // MARK: - Temporary Message

    private var temporaryMessageTask: Task<Void, Never>?
    private var temporaryMessageAction: (() -> Void)?
    private var isShowingTemporaryMessage = false
    private var presentationGeneration: UInt = 0
    private var agentConfirmationCandidates: [AgentSessionCard] = []
    private var agentConfirmationUtterance = ""
    private var agentCandidateButtons: [AgentCandidateButton] = []

    var onAgentCandidateSelected: ((String, String) -> Void)?

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

        visualEffectView.wantsLayer = true
        visualEffectView.layer?.cornerRadius = OverlayLayout.cornerRadius
        visualEffectView.layer?.masksToBounds = true
        visualEffectView.layer?.backgroundColor = OverlayAppearance.backgroundColor.cgColor
        visualEffectView.layer?.borderWidth = 1
        visualEffectView.layer?.borderColor = NSColor(
            red: 0.790,
            green: 0.835,
            blue: 0.815,
            alpha: 0.55
        ).cgColor
        visualEffectView.translatesAutoresizingMaskIntoConstraints = false

        window.contentView = visualEffectView
        visualEffectView.addGestureRecognizer(
            NSClickGestureRecognizer(
                target: self,
                action: #selector(handleOverlayClick(_:))
            )
        )

        indicatorBackgroundView.translatesAutoresizingMaskIntoConstraints = false
        indicatorBackgroundView.wantsLayer = true
        indicatorBackgroundView.layer?.cornerRadius = 9
        indicatorBackgroundView.layer?.backgroundColor = NSColor(
            red: 0.055,
            green: 0.420,
            blue: 0.345,
            alpha: 0.11
        ).cgColor
        visualEffectView.addSubview(indicatorBackgroundView)

        // Waveform view
        waveformView.translatesAutoresizingMaskIntoConstraints = false
        indicatorBackgroundView.addSubview(waveformView)

        // Text label — multi-line with word wrapping for long transcription
        textLabel.translatesAutoresizingMaskIntoConstraints = false
        textLabel.isBezeled = false
        textLabel.isEditable = false
        textLabel.drawsBackground = false
        textLabel.textColor = NSColor(red: 0.114, green: 0.169, blue: 0.149, alpha: 1.0)
        textLabel.font = NSFont.systemFont(ofSize: 15, weight: .semibold)
        textLabel.lineBreakMode = OverlayLayout.textLineBreakMode
        textLabel.maximumNumberOfLines = OverlayLayout.maxVisibleLines
        textLabel.alignment = .left
        textLabel.cell?.wraps = true
        textLabel.cell?.isScrollable = false
        textLabel.cell?.truncatesLastVisibleLine = OverlayLayout.truncatesLastVisibleLine
        textLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        visualEffectView.addSubview(textLabel)

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.cell = VerticallyCenteredTextFieldCell(textCell: "")
        statusLabel.isBezeled = false
        statusLabel.isEditable = false
        statusLabel.drawsBackground = false
        statusLabel.alignment = .center
        statusLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        statusLabel.textColor = NSColor(red: 0.055, green: 0.420, blue: 0.345, alpha: 1.0)
        statusLabel.stringValue = "听写中"
        statusLabel.wantsLayer = true
        statusLabel.layer?.cornerRadius = 10
        statusLabel.layer?.backgroundColor = NSColor(
            red: 0.055,
            green: 0.420,
            blue: 0.345,
            alpha: 0.10
        ).cgColor
        visualEffectView.addSubview(statusLabel)

        // Refining spinner (hidden by default)
        refiningSpinner.style = .spinning
        refiningSpinner.controlSize = .small
        refiningSpinner.translatesAutoresizingMaskIntoConstraints = false
        refiningSpinner.isHidden = true
        indicatorBackgroundView.addSubview(refiningSpinner)

        setupConfirmationContainer()

        // Layout — vertical padding and variable-height text
        NSLayoutConstraint.activate([
            indicatorBackgroundView.leadingAnchor.constraint(
                equalTo: visualEffectView.leadingAnchor,
                constant: OverlayLayout.horizontalPadding
            ),
            indicatorBackgroundView.centerYAnchor.constraint(equalTo: visualEffectView.centerYAnchor),
            indicatorBackgroundView.widthAnchor.constraint(equalToConstant: OverlayLayout.indicatorSize),
            indicatorBackgroundView.heightAnchor.constraint(equalToConstant: OverlayLayout.indicatorSize),

            waveformView.centerXAnchor.constraint(equalTo: indicatorBackgroundView.centerXAnchor),
            waveformView.centerYAnchor.constraint(equalTo: indicatorBackgroundView.centerYAnchor),
            waveformView.widthAnchor.constraint(equalToConstant: OverlayLayout.waveformWidth),
            waveformView.heightAnchor.constraint(equalToConstant: OverlayLayout.waveformHeight),

            textLabel.leadingAnchor.constraint(
                equalTo: indicatorBackgroundView.trailingAnchor,
                constant: OverlayLayout.interSpacing
            ),
            textLabel.topAnchor.constraint(
                equalTo: visualEffectView.topAnchor,
                constant: OverlayLayout.verticalPadding
            ),
            textLabel.trailingAnchor.constraint(
                equalTo: statusLabel.leadingAnchor,
                constant: -OverlayLayout.interSpacing
            ),
            textLabel.bottomAnchor.constraint(
                lessThanOrEqualTo: visualEffectView.bottomAnchor,
                constant: -OverlayLayout.verticalPadding
            ),

            statusLabel.trailingAnchor.constraint(
                equalTo: visualEffectView.trailingAnchor,
                constant: -OverlayLayout.horizontalPadding
            ),
            statusLabel.centerYAnchor.constraint(equalTo: visualEffectView.centerYAnchor),
            statusLabel.widthAnchor.constraint(equalToConstant: OverlayLayout.statusChipWidth),
            statusLabel.heightAnchor.constraint(equalToConstant: 26),

            refiningSpinner.centerXAnchor.constraint(equalTo: indicatorBackgroundView.centerXAnchor),
            refiningSpinner.centerYAnchor.constraint(equalTo: indicatorBackgroundView.centerYAnchor),
        ])
    }

    private func setupConfirmationContainer() {
        confirmationContainer.translatesAutoresizingMaskIntoConstraints = false
        confirmationContainer.isHidden = true
        visualEffectView.addSubview(confirmationContainer)

        confirmationStatusLabel.translatesAutoresizingMaskIntoConstraints = false
        confirmationStatusLabel.cell = VerticallyCenteredTextFieldCell(textCell: "")
        confirmationStatusLabel.isBezeled = false
        confirmationStatusLabel.isEditable = false
        confirmationStatusLabel.drawsBackground = false
        confirmationStatusLabel.alignment = .center
        confirmationStatusLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        confirmationStatusLabel.textColor = NSColor(red: 0.690, green: 0.370, blue: 0.090, alpha: 1.0)
        confirmationStatusLabel.stringValue = "需要确认"
        confirmationStatusLabel.wantsLayer = true
        confirmationStatusLabel.layer?.cornerRadius = 10
        confirmationStatusLabel.layer?.backgroundColor = NSColor(
            red: 1.0,
            green: 0.530,
            blue: 0.200,
            alpha: 0.12
        ).cgColor
        confirmationContainer.addSubview(confirmationStatusLabel)

        confirmationUtteranceRow.translatesAutoresizingMaskIntoConstraints = false
        confirmationUtteranceRow.wantsLayer = true
        confirmationUtteranceRow.layer?.cornerRadius = 12
        confirmationUtteranceRow.layer?.borderWidth = 1
        confirmationUtteranceRow.layer?.borderColor = NSColor(
            red: 0.880,
            green: 0.905,
            blue: 0.890,
            alpha: 0.90
        ).cgColor
        confirmationUtteranceRow.layer?.backgroundColor = NSColor(
            red: 0.996,
            green: 0.996,
            blue: 0.990,
            alpha: 0.90
        ).cgColor
        confirmationContainer.addSubview(confirmationUtteranceRow)

        confirmationUtteranceIconLabel.translatesAutoresizingMaskIntoConstraints = false
        confirmationUtteranceIconLabel.cell = VerticallyCenteredTextFieldCell(textCell: "")
        confirmationUtteranceIconLabel.isBezeled = false
        confirmationUtteranceIconLabel.isEditable = false
        confirmationUtteranceIconLabel.drawsBackground = false
        confirmationUtteranceIconLabel.alignment = .center
        confirmationUtteranceIconLabel.font = NSFont.systemFont(ofSize: 20, weight: .bold)
        confirmationUtteranceIconLabel.textColor = NSColor(red: 0.890, green: 0.480, blue: 0.140, alpha: 1.0)
        confirmationUtteranceIconLabel.stringValue = "“"
        confirmationUtteranceIconLabel.wantsLayer = true
        confirmationUtteranceIconLabel.layer?.cornerRadius = 9
        confirmationUtteranceIconLabel.layer?.backgroundColor = NSColor(
            red: 1.0,
            green: 0.540,
            blue: 0.180,
            alpha: 0.12
        ).cgColor
        confirmationUtteranceRow.addSubview(confirmationUtteranceIconLabel)

        confirmationUtteranceLabel.translatesAutoresizingMaskIntoConstraints = false
        confirmationUtteranceLabel.isBezeled = false
        confirmationUtteranceLabel.isEditable = false
        confirmationUtteranceLabel.drawsBackground = false
        confirmationUtteranceLabel.font = NSFont.systemFont(ofSize: 15, weight: .medium)
        confirmationUtteranceLabel.textColor = NSColor(red: 0.114, green: 0.169, blue: 0.149, alpha: 1.0)
        confirmationUtteranceLabel.lineBreakMode = .byTruncatingTail
        confirmationUtteranceLabel.maximumNumberOfLines = 1
        confirmationUtteranceLabel.cell?.wraps = false
        confirmationUtteranceLabel.cell?.usesSingleLineMode = true
        confirmationUtteranceLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        confirmationUtteranceLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        confirmationUtteranceRow.addSubview(confirmationUtteranceLabel)

        confirmationRowsStack.translatesAutoresizingMaskIntoConstraints = false
        confirmationRowsStack.orientation = .vertical
        confirmationRowsStack.spacing = 8
        confirmationRowsStack.alignment = .leading
        confirmationRowsStack.distribution = .fill
        confirmationContainer.addSubview(confirmationRowsStack)

        confirmationFooterLabel.translatesAutoresizingMaskIntoConstraints = false
        confirmationFooterLabel.isBezeled = false
        confirmationFooterLabel.isEditable = false
        confirmationFooterLabel.drawsBackground = false
        confirmationFooterLabel.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        confirmationFooterLabel.textColor = NSColor(red: 0.360, green: 0.420, blue: 0.390, alpha: 0.85)
        confirmationFooterLabel.stringValue = "未准确命中队员名时，需要你确认目标"
        confirmationContainer.addSubview(confirmationFooterLabel)

        confirmationLayoutConstraints = [
            confirmationContainer.leadingAnchor.constraint(equalTo: visualEffectView.leadingAnchor, constant: 22),
            confirmationContainer.trailingAnchor.constraint(equalTo: visualEffectView.trailingAnchor, constant: -22),
            confirmationContainer.topAnchor.constraint(equalTo: visualEffectView.topAnchor, constant: 18),
            confirmationContainer.bottomAnchor.constraint(equalTo: visualEffectView.bottomAnchor, constant: -16),

            confirmationStatusLabel.leadingAnchor.constraint(equalTo: confirmationContainer.leadingAnchor),
            confirmationStatusLabel.topAnchor.constraint(equalTo: confirmationContainer.topAnchor),
            confirmationStatusLabel.widthAnchor.constraint(equalToConstant: 78),
            confirmationStatusLabel.heightAnchor.constraint(equalToConstant: 28),

            confirmationUtteranceRow.leadingAnchor.constraint(equalTo: confirmationContainer.leadingAnchor),
            confirmationUtteranceRow.trailingAnchor.constraint(equalTo: confirmationContainer.trailingAnchor),
            confirmationUtteranceRow.topAnchor.constraint(equalTo: confirmationStatusLabel.bottomAnchor, constant: 14),
            confirmationUtteranceRow.heightAnchor.constraint(equalToConstant: 50),

            confirmationUtteranceIconLabel.leadingAnchor.constraint(equalTo: confirmationUtteranceRow.leadingAnchor, constant: 12),
            confirmationUtteranceIconLabel.centerYAnchor.constraint(equalTo: confirmationUtteranceRow.centerYAnchor),
            confirmationUtteranceIconLabel.widthAnchor.constraint(equalToConstant: 32),
            confirmationUtteranceIconLabel.heightAnchor.constraint(equalToConstant: 32),

            confirmationUtteranceLabel.leadingAnchor.constraint(
                equalTo: confirmationUtteranceIconLabel.trailingAnchor,
                constant: 14
            ),
            confirmationUtteranceLabel.trailingAnchor.constraint(
                equalTo: confirmationUtteranceRow.trailingAnchor,
                constant: -14
            ),
            confirmationUtteranceLabel.centerYAnchor.constraint(equalTo: confirmationUtteranceRow.centerYAnchor),

            confirmationRowsStack.leadingAnchor.constraint(equalTo: confirmationContainer.leadingAnchor),
            confirmationRowsStack.trailingAnchor.constraint(equalTo: confirmationContainer.trailingAnchor),
            confirmationRowsStack.topAnchor.constraint(equalTo: confirmationUtteranceRow.bottomAnchor, constant: 10),

            confirmationFooterLabel.leadingAnchor.constraint(equalTo: confirmationContainer.leadingAnchor),
            confirmationFooterLabel.trailingAnchor.constraint(equalTo: confirmationContainer.trailingAnchor),
            confirmationFooterLabel.topAnchor.constraint(equalTo: confirmationRowsStack.bottomAnchor, constant: 10),
            confirmationFooterLabel.bottomAnchor.constraint(equalTo: confirmationContainer.bottomAnchor),
        ]
    }

    // MARK: - Sizing

    private func updateWindowSize(textWidth: CGFloat, textHeight: CGFloat = 0) {
        guard let window = window else { return }

        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame

        window.minSize = .zero
        window.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        let windowWidth = ceil(OverlayLayout.windowWidth(textWidth: textWidth))
        let windowHeight = OverlayLayout.windowHeight(textHeight: textHeight)
        let x = screenFrame.midX - windowWidth / 2
        let y = screenFrame.minY + OverlayLayout.bottomOffset

        let frame = NSRect(x: x, y: y, width: windowWidth, height: windowHeight)
        window.setFrame(frame, display: true, animate: false)
    }

    private func updateWindowFrame(width: CGFloat, height: CGFloat) {
        guard let window, let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let size = NSSize(width: width, height: height)
        window.minSize = size
        window.maxSize = size
        let frame = NSRect(
            x: screenFrame.midX - width / 2,
            y: screenFrame.minY + OverlayLayout.bottomOffset,
            width: width,
            height: height
        )
        window.setFrame(frame, display: true, animate: false)
    }

    private func measuredOverlayTextSize(for text: String) -> CGSize {
        let textSize = (text as NSString).boundingRect(
            with: NSSize(
                width: OverlayLayout.maximumTextWidth,
                height: CGFloat.greatestFiniteMagnitude
            ),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: textLabel.font as Any]
        )
        return CGSize(width: textSize.width + 8, height: textSize.height + 8)
    }

    private func hideAgentConfirmationPresentation() {
        NSLayoutConstraint.deactivate(confirmationLayoutConstraints)
        confirmationContainer.isHidden = true
        agentCandidateButtons.removeAll()
        for row in confirmationRowsStack.arrangedSubviews {
            confirmationRowsStack.removeArrangedSubview(row)
            row.removeFromSuperview()
        }
        indicatorBackgroundView.isHidden = false
        textLabel.isHidden = false
        statusLabel.isHidden = false
    }

    private func showAgentConfirmationPresentation(
        utterance: String,
        candidates: [AgentSessionCard]
    ) {
        temporaryMessageTask?.cancel()
        temporaryMessageTask = nil
        temporaryMessageAction = nil
        isShowingTemporaryMessage = false
        presentationGeneration &+= 1
        indicatorBackgroundView.isHidden = true
        waveformView.stopAnimation()
        refiningSpinner.stopAnimation(nil)
        textLabel.isHidden = true
        textLabel.stringValue = ""
        statusLabel.isHidden = true
        statusLabel.stringValue = ""
        confirmationContainer.isHidden = false
        NSLayoutConstraint.activate(confirmationLayoutConstraints)
        confirmationUtteranceLabel.stringValue = AgentDispatchConfirmationUtteranceFormatter.displayText(utterance)
        confirmationUtteranceLabel.toolTip = utterance
        rebuildAgentCandidateRows(candidates)
        let confirmationWidth: CGFloat = 600
        let confirmationHeight = CGFloat(264 + min(max(candidates.count, 1), 4) * 36)
        updateWindowFrame(width: confirmationWidth, height: confirmationHeight)
        guard let window else { return }
        window.ignoresMouseEvents = false
        present(window)
        updateWindowFrame(width: confirmationWidth, height: confirmationHeight)
    }

    private func rebuildAgentCandidateRows(_ candidates: [AgentSessionCard]) {
        agentCandidateButtons.removeAll()
        for row in confirmationRowsStack.arrangedSubviews {
            confirmationRowsStack.removeArrangedSubview(row)
            row.removeFromSuperview()
        }

        for (index, candidate) in candidates.prefix(4).enumerated() {
            let button = AgentCandidateButton()
            button.translatesAutoresizingMaskIntoConstraints = false
            button.agentID = candidate.agentID
            button.identifier = NSUserInterfaceItemIdentifier("agentCandidateRow")
            button.onSelect = { [weak self] agentID in
                self?.selectAgentCandidate(agentID: agentID)
            }
            button.wantsLayer = true
            button.layer?.cornerRadius = 11
            button.layer?.borderWidth = 1
            button.layer?.borderColor = NSColor(
                red: 0.875,
                green: 0.900,
                blue: 0.885,
                alpha: 0.95
            ).cgColor
            button.layer?.backgroundColor = NSColor(
                red: 0.998,
                green: 0.998,
                blue: 0.994,
                alpha: 0.92
            ).cgColor
            configureAgentCandidateButton(
                button,
                number: index + 1,
                name: candidate.displayName,
                confidenceBar: confidenceBar(for: index)
            )
            confirmationRowsStack.addArrangedSubview(button)
            NSLayoutConstraint.activate([
                button.widthAnchor.constraint(equalTo: confirmationRowsStack.widthAnchor),
                button.heightAnchor.constraint(equalToConstant: 44),
            ])
            agentCandidateButtons.append(button)
        }
    }

    private func configureAgentCandidateButton(
        _ button: AgentCandidateButton,
        number: Int,
        name: String,
        confidenceBar: String
    ) {
        let numberLabel = confirmationRowText("\(number)", size: 14, weight: .semibold)
        numberLabel.alignment = .center
        numberLabel.wantsLayer = true
        numberLabel.layer?.cornerRadius = 8
        numberLabel.layer?.backgroundColor = NSColor(
            red: 1.0,
            green: 0.540,
            blue: 0.180,
            alpha: 0.12
        ).cgColor

        let nameLabel = confirmationRowText(name, size: 14, weight: .semibold)
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let confidenceLabel = confirmationRowText("置信度", size: 12, weight: .medium)
        confidenceLabel.textColor = NSColor(red: 0.425, green: 0.475, blue: 0.450, alpha: 0.95)

        let confidenceView = confidenceBarView(confidenceBar)

        [numberLabel, nameLabel, confidenceLabel, confidenceView].forEach(button.addSubview)
        NSLayoutConstraint.activate([
            numberLabel.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 12),
            numberLabel.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            numberLabel.widthAnchor.constraint(equalToConstant: 28),
            numberLabel.heightAnchor.constraint(equalToConstant: 28),

            nameLabel.leadingAnchor.constraint(equalTo: numberLabel.trailingAnchor, constant: 14),
            nameLabel.centerYAnchor.constraint(equalTo: button.centerYAnchor),

            confidenceLabel.leadingAnchor.constraint(
                greaterThanOrEqualTo: nameLabel.trailingAnchor,
                constant: 12
            ),
            confidenceLabel.centerYAnchor.constraint(equalTo: button.centerYAnchor),

            confidenceView.leadingAnchor.constraint(equalTo: confidenceLabel.trailingAnchor, constant: 12),
            confidenceView.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -14),
            confidenceView.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            confidenceView.widthAnchor.constraint(equalToConstant: 58),
            confidenceView.heightAnchor.constraint(equalToConstant: 10),
        ])
    }

    private func confirmationRowText(
        _ text: String,
        size: CGFloat,
        weight: NSFont.Weight
    ) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isBezeled = false
        label.isEditable = false
        label.drawsBackground = false
        label.font = NSFont.systemFont(ofSize: size, weight: weight)
        label.textColor = NSColor(red: 0.114, green: 0.169, blue: 0.149, alpha: 1.0)
        return label
    }

    private func confidenceBarView(_ value: String) -> NSView {
        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .horizontal
        stack.spacing = 3
        stack.distribution = .fillEqually

        for character in value {
            let segment = NSView()
            segment.translatesAutoresizingMaskIntoConstraints = false
            segment.wantsLayer = true
            segment.layer?.cornerRadius = 2
            segment.layer?.backgroundColor = (character == "■"
                ? NSColor(red: 0.250, green: 0.690, blue: 0.455, alpha: 1.0)
                : NSColor(red: 0.895, green: 0.915, blue: 0.905, alpha: 1.0)
            ).cgColor
            stack.addArrangedSubview(segment)
        }
        return stack
    }

    private func confidenceBar(for index: Int) -> String {
        switch index {
        case 0: return "■■■■□□"
        case 1: return "■■■□□□"
        default: return "■■□□□□"
        }
    }

    // MARK: - Public API

    /// Shows the overlay in the default dictation state (waveform + "听写中").
    func show() {
        guard let window = window else { return }
        hideAgentConfirmationPresentation()
        temporaryMessageTask?.cancel()
        temporaryMessageTask = nil
        temporaryMessageAction = nil
        isShowingTemporaryMessage = false
        presentationGeneration &+= 1
        window.ignoresMouseEvents = true

        // Calculate initial size for empty text
        updateWindowSize(textWidth: OverlayLayout.minimumTextWidth)

        waveformView.isHidden = false
        waveformView.reset()
        waveformView.startAnimation()
        statusLabel.stringValue = "听写中"
        statusLabel.textColor = NSColor(red: 0.055, green: 0.420, blue: 0.345, alpha: 1.0)
        refiningSpinner.isHidden = true
        refiningSpinner.stopAnimation(nil)

        present(window)
    }

    /// Presents the overlay without resetting UI state.
    /// Used by agent-compose stage changes so the spinner and status labels
    /// set by `updateAgentComposeStatus` are not overwritten.
    func showWithoutReset() {
        guard let window = window else { return }
        temporaryMessageTask?.cancel()
        temporaryMessageTask = nil
        temporaryMessageAction = nil
        isShowingTemporaryMessage = false
        presentationGeneration &+= 1
        window.ignoresMouseEvents = true
        present(window)
    }

    private func present(_ window: NSWindow) {
        window.alphaValue = 1.0
        window.orderFront(nil)
        window.displayIfNeeded()

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
    }

    func updateTranscription(_ text: String, isRefining: Bool) {
        hideAgentConfirmationPresentation()
        let displayText: String
        if isRefining {
            displayText = text.isEmpty ? "正在识别文本" : text
            textLabel.textColor = NSColor(red: 0.220, green: 0.310, blue: 0.280, alpha: 0.92)
            statusLabel.stringValue = "纠错中"
            waveformView.stopAnimation()
            waveformView.isHidden = true
            refiningSpinner.isHidden = false
            refiningSpinner.startAnimation(nil)
        } else {
            displayText = text.isEmpty ? "正在聆听..." : text
            textLabel.textColor = NSColor(red: 0.114, green: 0.169, blue: 0.149, alpha: 1.0)
            statusLabel.stringValue = "听写中"
            waveformView.isHidden = false
            waveformView.startAnimation()
            refiningSpinner.isHidden = true
            refiningSpinner.stopAnimation(nil)
        }
        let visibleText = OverlayLayout.visibleTranscriptionText(displayText)
        textLabel.stringValue = visibleText

        let textSize = measuredOverlayTextSize(for: visibleText)

        updateWindowSize(textWidth: textSize.width, textHeight: textSize.height)
    }

    func updateRMS(_ rms: Float) {
        waveformView.updateRMS(rms)
    }

    /// Displays a temporary error/info message in the overlay that auto-dismisses
    /// after `duration` seconds. Used for non-blocking error feedback.
    func showTemporaryMessage(
        _ text: String,
        duration: TimeInterval = 3.0,
        tone: HUDTemporaryMessageTone = .info,
        action: (() -> Void)? = nil
    ) {
        hideAgentConfirmationPresentation()
        temporaryMessageTask?.cancel()
        guard OverlayLayout.shouldShowTemporaryMessage(text) else {
            temporaryMessageAction = nil
            isShowingTemporaryMessage = false
            presentationGeneration &+= 1
            dismiss()
            return
        }

        temporaryMessageAction = action
        isShowingTemporaryMessage = true
        presentationGeneration &+= 1
        let generation = presentationGeneration

        waveformView.stopAnimation()
        waveformView.isHidden = true
        applyTemporaryMessageTone(tone)
        refiningSpinner.isHidden = true
        refiningSpinner.stopAnimation(nil)

        textLabel.stringValue = text

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
        window.ignoresMouseEvents = action == nil
        present(window)

        temporaryMessageTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled,
                  let self,
                  self.presentationGeneration == generation else {
                return
            }
            self.isShowingTemporaryMessage = false
            self.temporaryMessageAction = nil
            self.dismiss(generation: generation)
        }
    }

    private func applyTemporaryMessageTone(_ tone: HUDTemporaryMessageTone) {
        switch tone {
        case .info:
            statusLabel.stringValue = "提示"
            statusLabel.textColor = NSColor(red: 0.670, green: 0.390, blue: 0.080, alpha: 1.0)
            textLabel.textColor = NSColor(red: 1.0, green: 0.78, blue: 0.38, alpha: 1.0)
        case .success:
            statusLabel.stringValue = "成功"
            statusLabel.textColor = NSColor(red: 0.055, green: 0.420, blue: 0.345, alpha: 1.0)
            textLabel.textColor = NSColor(red: 0.114, green: 0.169, blue: 0.149, alpha: 1.0)
        }
    }

    func dismiss() {
        guard !isShowingTemporaryMessage else { return }
        dismiss(generation: presentationGeneration)
    }

    private func dismiss(generation: UInt) {
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
                self.completeDismiss(window: window, generation: generation)
            }
        }
        Task { @MainActor [weak self, weak window] in
            try? await Task.sleep(nanoseconds: 230_000_000)
            guard let self, let window else { return }
            self.completeDismiss(window: window, generation: generation)
        }
    }

    private func completeDismiss(window: NSWindow, generation: UInt) {
        guard presentationGeneration == generation else { return }
        hideAgentConfirmationPresentation()
        textLabel.stringValue = ""
        statusLabel.stringValue = ""
        temporaryMessageAction = nil
        window.ignoresMouseEvents = true
        window.orderOut(nil)
        visualEffectView.layer?.removeAnimation(forKey: "voiceinput.exit")
    }

    func performTemporaryMessageClickForTesting() {
        temporaryMessageAction?()
    }

    @objc private func handleOverlayClick(_ recognizer: NSClickGestureRecognizer) {
        guard recognizer.state == .ended else { return }
        if !agentConfirmationCandidates.isEmpty {
            return
        }
        temporaryMessageAction?()
    }

    private func selectAgentCandidate(agentID: String) {
        let utterance = agentConfirmationUtterance
        agentConfirmationCandidates = []
        agentConfirmationUtterance = ""
        hideAgentConfirmationPresentation()
        window?.ignoresMouseEvents = true
        onAgentCandidateSelected?(agentID, utterance)
    }

    /// Returns the current transcription text shown in the overlay.
    var currentText: String {
        textLabel.stringValue
    }

    // MARK: - Agent Compose Status

    /// Updates the overlay for agent compose mode stages.
    func updateAgentComposeStatus(_ stage: AgentComposeHUDStage) {
        hideAgentConfirmationPresentation()
        switch stage {
        case .readingWindow:
            statusLabel.stringValue = "读取窗口"
            statusLabel.textColor = NSColor(red: 0.055, green: 0.420, blue: 0.345, alpha: 1.0)
            textLabel.stringValue = "正在读取窗口上下文..."
            textLabel.textColor = NSColor(red: 0.220, green: 0.310, blue: 0.280, alpha: 0.92)
            waveformView.stopAnimation()
            waveformView.isHidden = true
            refiningSpinner.isHidden = false
            refiningSpinner.startAnimation(nil)
        case .transcribing:
            statusLabel.stringValue = "转写中"
            statusLabel.textColor = NSColor(red: 0.055, green: 0.420, blue: 0.345, alpha: 1.0)
            textLabel.stringValue = "正在识别语音..."
            textLabel.textColor = NSColor(red: 0.220, green: 0.310, blue: 0.280, alpha: 0.92)
            waveformView.stopAnimation()
            waveformView.isHidden = true
            refiningSpinner.isHidden = false
            refiningSpinner.startAnimation(nil)
        case .generating:
            statusLabel.stringValue = "生成中"
            statusLabel.textColor = NSColor(red: 0.055, green: 0.420, blue: 0.345, alpha: 1.0)
            textLabel.stringValue = "正在生成文本..."
            textLabel.textColor = NSColor(red: 0.220, green: 0.310, blue: 0.280, alpha: 0.92)
            waveformView.stopAnimation()
            waveformView.isHidden = true
            refiningSpinner.isHidden = false
            refiningSpinner.startAnimation(nil)
        case .copied:
            statusLabel.stringValue = "已复制"
            statusLabel.textColor = NSColor(red: 0.055, green: 0.420, blue: 0.345, alpha: 1.0)
            textLabel.stringValue = "已复制到剪贴板"
            textLabel.textColor = NSColor(red: 0.114, green: 0.169, blue: 0.149, alpha: 1.0)
            refiningSpinner.isHidden = true
            refiningSpinner.stopAnimation(nil)
        case .inserted:
            statusLabel.stringValue = "已写入"
            statusLabel.textColor = NSColor(red: 0.055, green: 0.420, blue: 0.345, alpha: 1.0)
            textLabel.stringValue = "已写入当前输入框"
            textLabel.textColor = NSColor(red: 0.114, green: 0.169, blue: 0.149, alpha: 1.0)
            refiningSpinner.isHidden = true
            refiningSpinner.stopAnimation(nil)
        case .contextUnavailable:
            statusLabel.stringValue = "提示"
            statusLabel.textColor = NSColor(red: 0.670, green: 0.390, blue: 0.080, alpha: 1.0)
            textLabel.stringValue = "上下文不可用，仅使用口述"
            textLabel.textColor = NSColor(red: 1.0, green: 0.78, blue: 0.38, alpha: 1.0)
            refiningSpinner.isHidden = true
            refiningSpinner.stopAnimation(nil)
        }
    }

    func updateAgentDispatch(_ presentation: AgentDispatchHUDPresentation) {
        if case let .confirmation(utterance, candidates) = presentation {
            guard !candidates.isEmpty else {
                updateAgentDispatch(.failure(message: "没有可用队员", retainedText: utterance))
                return
            }
            agentConfirmationCandidates = candidates
            agentConfirmationUtterance = utterance
            showAgentConfirmationPresentation(utterance: utterance, candidates: candidates)
            return
        }

        hideAgentConfirmationPresentation()
        waveformView.stopAnimation()
        refiningSpinner.stopAnimation(nil)
        refiningSpinner.isHidden = true
        statusLabel.textColor = NSColor(red: 0.055, green: 0.420, blue: 0.345, alpha: 1.0)
        textLabel.textColor = NSColor(red: 0.114, green: 0.169, blue: 0.149, alpha: 1.0)
        statusLabel.stringValue = presentation.badge ?? presentation.title
        if case .listening = presentation {
            textLabel.stringValue = "说出要交给队员的任务"
            textLabel.toolTip = nil
        } else if case let .clipboardFallback(text) = presentation {
            textLabel.stringValue = AgentDispatchConfirmationUtteranceFormatter.displayText(text)
            textLabel.toolTip = text
        } else {
            textLabel.stringValue = presentation.detail.isEmpty
                ? presentation.title
                : presentation.detail
            textLabel.toolTip = nil
        }

        switch presentation {
        case .listening:
            waveformView.isHidden = false
            waveformView.startAnimation()
        case .fallbackInput, .clipboardFallback, .sent:
            waveformView.isHidden = true
        case .failure:
            waveformView.isHidden = true
            statusLabel.textColor = NSColor.systemRed
        case .idle, .exact:
            waveformView.isHidden = true
        case .confirmation:
            break
        }
        agentConfirmationCandidates = []
        agentConfirmationUtterance = ""
        window?.ignoresMouseEvents = true
        let textSize = measuredOverlayTextSize(for: textLabel.stringValue)
        updateWindowSize(textWidth: textSize.width, textHeight: textSize.height)
    }

    /// Updates the overlay text in real-time as LLM streaming content arrives.
    /// Called during the .generating stage to show partial text to the user.
    func updateStreamingText(_ partialText: String) {
        let displayText = OverlayLayout.visibleTranscriptionText(partialText)
        textLabel.stringValue = displayText
        let textSize = measuredOverlayTextSize(for: displayText)
        updateWindowSize(textWidth: textSize.width, textHeight: textSize.height)
        guard let window else { return }
        present(window)
    }
}

// MARK: - AgentComposeHUDStage

enum AgentComposeHUDStage: Equatable {
    case readingWindow
    case transcribing
    case generating
    case copied
    case inserted
    case contextUnavailable
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
