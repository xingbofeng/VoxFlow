import AppKit
import CoreGraphics

@MainActor
public final class ScrollingScreenshotConfirmationPanelPresenter: ScrollingScreenshotConfirmationPresenting {
    private let imageSaver: any AnnotationImageSaving
    private let annotationEditor: any AnnotationEditing

    public init(
        imageSaver: any AnnotationImageSaving = SystemAnnotationImageSaver(),
        annotationEditor: any AnnotationEditing = AnnotationEditorPresenter()
    ) {
        self.imageSaver = imageSaver
        self.annotationEditor = annotationEditor
    }

    public func confirm(
        image: CGImage,
        request: ScrollingScreenshotRequest
    ) async -> ScrollingScreenshotConfirmationResult {
        await withCheckedContinuation { continuation in
            var didResume = false
            var panel: ScrollingScreenshotConfirmationPanel?
            let finish: (ScrollingScreenshotConfirmationResult) -> Void = { action in
                guard !didResume else { return }
                didResume = true
                panel?.close()
                continuation.resume(returning: action)
            }

            let confirmationPanel = ScrollingScreenshotConfirmationPanel(
                image: image,
                request: request,
                imageSaver: imageSaver,
                annotationEditor: annotationEditor,
                onAction: finish
            )
            panel = confirmationPanel
            NSApp.activate(ignoringOtherApps: true)
            confirmationPanel.makeKeyAndOrderFront(nil)
            confirmationPanel.orderFrontRegardless()
        }
    }
}

@MainActor
final class ScrollingScreenshotConfirmationPanel: NSPanel {
    private let image: CGImage
    private let imageSaver: any AnnotationImageSaving
    private let annotationEditor: any AnnotationEditing
    private let onAction: (ScrollingScreenshotConfirmationResult) -> Void
    private let imageView = NSImageView()
    private let scrollView = NSScrollView()
    private let toolbarView = NSVisualEffectView()
    private let statusLabel = NSTextField(labelWithString: "")

    init(
        image: CGImage,
        request: ScrollingScreenshotRequest,
        imageSaver: any AnnotationImageSaving,
        annotationEditor: any AnnotationEditing,
        onAction: @escaping (ScrollingScreenshotConfirmationResult) -> Void
    ) {
        self.image = image
        self.imageSaver = imageSaver
        self.annotationEditor = annotationEditor
        self.onAction = onAction

        let frame = Self.panelFrame(for: image, request: request)
        super.init(
            contentRect: frame,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        level = .screenSaver
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        ignoresMouseEvents = false
        isMovableByWindowBackground = true

        let content = NSView(frame: CGRect(origin: .zero, size: frame.size))
        content.wantsLayer = true
        content.layer?.cornerRadius = 6
        content.layer?.masksToBounds = true
        content.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        contentView = content

        let imageSize = CGSize(
            width: CGFloat(image.width) / max(request.selection.displayScale, 1),
            height: CGFloat(image.height) / max(request.selection.displayScale, 1)
        )
        imageView.image = NSImage(cgImage: image, size: imageSize)
        imageView.imageAlignment = .alignTopLeft
        imageView.imageScaling = .scaleNone
        imageView.frame = CGRect(origin: .zero, size: imageSize)

        let documentView = ScrollingScreenshotConfirmationDocumentView(frame: CGRect(origin: .zero, size: imageSize))
        documentView.addSubview(imageView)

        scrollView.frame = content.bounds
        scrollView.autoresizingMask = [.width, .height]
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 76, right: 0)
        scrollView.documentView = documentView
        content.addSubview(scrollView)

        configureToolbar(in: content)
    }

    override var canBecomeKey: Bool { true }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76:
            onAction(.accepted(image))
        case 53:
            onAction(.cancelled)
        default:
            super.keyDown(with: event)
        }
    }

    private func configureToolbar(in content: NSView) {
        toolbarView.material = .hudWindow
        toolbarView.blendingMode = .withinWindow
        toolbarView.state = .active
        toolbarView.wantsLayer = true
        toolbarView.layer?.cornerRadius = 10
        toolbarView.layer?.masksToBounds = true
        content.addSubview(toolbarView)

        let buttons: [(String, String, NSColor?, Selector)] = [
            ("pencil", "编辑", nil, #selector(editClicked)),
            ("square.and.arrow.down", "下载", nil, #selector(downloadClicked)),
            ("xmark", "取消", .systemRed, #selector(cancelClicked)),
            ("checkmark", "完成", .systemGreen, #selector(acceptClicked)),
        ]
        let buttonSize: CGFloat = 36
        let spacing: CGFloat = 12
        let padding: CGFloat = 12
        let width = padding * 2 + CGFloat(buttons.count) * buttonSize + CGFloat(buttons.count - 1) * spacing
        let height: CGFloat = 48
        toolbarView.frame = CGRect(
            x: (content.bounds.width - width) / 2,
            y: 14,
            width: width,
            height: height
        )
        toolbarView.autoresizingMask = [.minXMargin, .maxXMargin, .maxYMargin]

        for (index, item) in buttons.enumerated() {
            let button = NSButton(
                image: NSImage(systemSymbolName: item.0, accessibilityDescription: item.1) ?? NSImage(),
                target: self,
                action: item.3
            )
            button.isBordered = false
            button.toolTip = item.1
            button.contentTintColor = item.2 ?? .labelColor
            button.frame = CGRect(
                x: padding + CGFloat(index) * (buttonSize + spacing),
                y: (height - buttonSize) / 2,
                width: buttonSize,
                height: buttonSize
            )
            toolbarView.addSubview(button)
        }

        statusLabel.font = .systemFont(ofSize: 11, weight: .medium)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.alignment = .center
        statusLabel.isHidden = true
        statusLabel.frame = CGRect(x: 0, y: toolbarView.frame.maxY + 4, width: content.bounds.width, height: 18)
        statusLabel.autoresizingMask = [.width, .maxYMargin]
        content.addSubview(statusLabel)
    }

    @objc private func editClicked() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let editedImage = try await annotationEditor.edit(image: image)
                onAction(.accepted(editedImage))
            } catch InteractiveScreenshotError.cancelled {
                orderFrontRegardless()
            } catch {
                showStatus("编辑失败")
                NSSound.beep()
                orderFrontRegardless()
            }
        }
    }

    @objc private func downloadClicked() {
        imageSaver.savePNG(image: image, attachedTo: self) { [weak self] result in
            MainActor.assumeIsolated {
                switch result {
                case .success(true):
                    self?.showStatus("已保存")
                case .success(false):
                    self?.showStatus("")
                case .failure:
                    self?.showStatus("保存失败")
                    NSSound.beep()
                }
            }
        }
    }

    @objc private func cancelClicked() {
        onAction(.cancelled)
    }

    @objc private func acceptClicked() {
        onAction(.accepted(image))
    }

    private func showStatus(_ text: String) {
        statusLabel.stringValue = text
        statusLabel.isHidden = text.isEmpty
    }

    private static func panelFrame(for image: CGImage, request: ScrollingScreenshotRequest) -> CGRect {
        let selection = request.selection.normalizedRect
        let scale = max(request.selection.displayScale, 1)
        let imageSize = CGSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
        let maxWidth = min(760, max(260, request.display.frame.width - 96))
        let maxHeight = min(620, max(220, request.display.frame.height - 120))
        let width = min(max(max(selection.width, min(imageSize.width, 520)), 360), maxWidth)
        let height = min(max(min(imageSize.height, maxHeight), 260), maxHeight)
        let x = min(
            max(selection.midX - width / 2, request.display.frame.minX + 16),
            request.display.frame.maxX - width - 16
        )
        let y = min(
            max(selection.midY - height / 2, request.display.frame.minY + 48),
            request.display.frame.maxY - height - 16
        )
        return CGRect(x: x, y: y, width: width, height: height)
    }
}

private final class ScrollingScreenshotConfirmationDocumentView: NSView {
    override var isFlipped: Bool { true }
}
