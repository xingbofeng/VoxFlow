import AppKit
import SwiftUI

@MainActor
final class ScreenshotOCRResultPanelController {
    private static let logger = AppLogger.general

    private let service: ScreenshotOCRService
    private let clipboard: any ScreenshotOCRResultClipboard
    private let autoDismissScheduler: any ScreenshotOCRResultAutoDismissScheduling
    private var window: ScreenshotOCRResultPanel?
    private var autoDismissToken: (any ScreenshotOCRResultAutoDismissCancellable)?

    init(
        service: ScreenshotOCRService,
        clipboard: any ScreenshotOCRResultClipboard,
        autoDismissScheduler: any ScreenshotOCRResultAutoDismissScheduling = TaskScreenshotOCRResultAutoDismissScheduler()
    ) {
        self.service = service
        self.clipboard = clipboard
        self.autoDismissScheduler = autoDismissScheduler
    }

    func present(
        result: ScreenshotOCRResult,
        initialTab: ScreenshotOCRResultTab = .originalImage,
        autoDismiss: Bool = true,
        overlayImage: CGImage? = nil
    ) {
        Self.logger.debug(
            "ScreenshotOCRResultPanelController present requested initialTab=\(initialTab) autoDismiss=\(autoDismiss) image=\(result.originalImage != nil)"
        )
        ContextBoostSuppression.setSuppressed(true, reason: Self.contextBoostSuppressionReason)

        let viewModel = ScreenshotOCRResultViewModel(
            result: result,
            service: service,
            clipboard: clipboard,
            initialTab: initialTab,
            translatedOverlayImage: overlayImage
        )
        let rootView = ScreenshotOCRResultView(
            viewModel: viewModel,
            onClose: { [weak self, weak viewModel] in
                viewModel?.close()
                self?.close()
            }
        )

        if window == nil {
            window = makeWindow()
        }
        guard let window else { return }
        Self.logger.debug("ScreenshotOCRResultPanelController using window")
        window.contentView = NSHostingView(rootView: rootView)
        position(window)
        window.orderFrontRegardless()
        window.makeKey()
        if autoDismiss {
            scheduleAutoDismiss()
        } else {
            cancelAutoDismissForInteraction()
        }
    }

    func close() {
        Self.logger.debug("ScreenshotOCRResultPanelController close")
        autoDismissToken?.cancel()
        autoDismissToken = nil
        ContextBoostSuppression.setSuppressed(false, reason: Self.contextBoostSuppressionReason)
        service.stopSpeaking()
        window?.close()
        window = nil
    }

    private func scheduleAutoDismiss() {
        autoDismissToken?.cancel()
        Self.logger.debug("ScreenshotOCRResultPanelController scheduleAutoDismiss")
        autoDismissToken = autoDismissScheduler.schedule(after: 5) { [weak self] in
            self?.close()
        }
    }

    private func cancelAutoDismissForInteraction() {
        Self.logger.debug("ScreenshotOCRResultPanelController cancelAutoDismissForInteraction")
        autoDismissToken?.cancel()
        autoDismissToken = nil
    }

    private func makeWindow() -> ScreenshotOCRResultPanel {
        let panel = ScreenshotOCRResultPanel(
            contentRect: CGRect(x: 0, y: 0, width: 440, height: 560),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "屏幕识别"
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [
            .moveToActiveSpace,
            .fullScreenAuxiliary,
            .transient,
            .ignoresCycle
        ]
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.sharingType = .readOnly
        panel.hidesOnDeactivate = false
        panel.worksWhenModal = true
        panel.onCancel = { [weak self] in self?.close() }
        panel.onInteraction = { [weak self] in self?.cancelAutoDismissForInteraction() }
        return panel
    }

    private func position(_ window: NSWindow) {
        let screenFrame = activeScreenFrame()
        let size = window.frame.size
        let margin: CGFloat = 28
        window.setFrameOrigin(
            CGPoint(
                x: screenFrame.maxX - size.width - margin,
                y: screenFrame.minY + max(36, (screenFrame.height - size.height) * 0.46)
            )
        )
    }

    private func activeScreenFrame() -> CGRect {
        let mouseLocation = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) {
            return screen.visibleFrame
        }
        return NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 440, height: 560)
    }

    private static let contextBoostSuppressionReason = "screenshot_ocr_result_panel"
}

@MainActor
protocol ScreenshotOCRResultAutoDismissCancellable: AnyObject {
    func cancel()
}

@MainActor
protocol ScreenshotOCRResultAutoDismissScheduling: AnyObject {
    func schedule(
        after delay: TimeInterval,
        action: @escaping @MainActor () -> Void
    ) -> any ScreenshotOCRResultAutoDismissCancellable
}

@MainActor
private final class TaskScreenshotOCRResultAutoDismissScheduler: ScreenshotOCRResultAutoDismissScheduling {
    func schedule(
        after delay: TimeInterval,
        action: @escaping @MainActor () -> Void
    ) -> any ScreenshotOCRResultAutoDismissCancellable {
        let task = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            action()
        }
        return TaskScreenshotOCRResultAutoDismissToken(task: task)
    }
}

@MainActor
private final class TaskScreenshotOCRResultAutoDismissToken: ScreenshotOCRResultAutoDismissCancellable {
    private let task: Task<Void, Never>

    init(task: Task<Void, Never>) {
        self.task = task
    }

    func cancel() {
        task.cancel()
    }
}

private final class ScreenshotOCRResultPanel: NSPanel {
    var onCancel: (() -> Void)?
    var onInteraction: (() -> Void)?

    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    override func keyDown(with event: NSEvent) {
        if UInt32(event.keyCode) == 53 {
            onCancel?()
        } else {
            super.keyDown(with: event)
        }
    }

    override func sendEvent(_ event: NSEvent) {
        if event.isScreenshotResultPanelInteraction {
            onInteraction?()
        }
        super.sendEvent(event)
    }
}

private extension NSEvent {
    var isScreenshotResultPanelInteraction: Bool {
        switch type {
        case .leftMouseDown,
             .rightMouseDown,
             .otherMouseDown,
             .leftMouseDragged,
             .rightMouseDragged,
             .otherMouseDragged,
             .scrollWheel,
             .keyDown:
            return true
        default:
            return false
        }
    }
}

private struct NativeWindowDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        WindowDragHandleView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class WindowDragHandleView: NSView {
        override var mouseDownCanMoveWindow: Bool {
            true
        }

        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }
}

private struct ScreenshotOCRResultView: View {
    @ObservedObject var viewModel: ScreenshotOCRResultViewModel
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            header
            Picker("", selection: $viewModel.selectedTab) {
                Text("原图").tag(ScreenshotOCRResultTab.originalImage)
                Text("识别").tag(ScreenshotOCRResultTab.ocr)
                Text("翻译").tag(ScreenshotOCRResultTab.translation)
                Text("总结").tag(ScreenshotOCRResultTab.summary)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: viewModel.selectedTab) {
                Task { await viewModel.activateSelectedTabIfNeeded() }
            }

            content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor).opacity(0.88))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            if let playback = viewModel.playbackState {
                playbackBar(playback)
            }

            footer
        }
        .padding(14)
        .frame(width: 440, height: 560)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        )
        .onExitCommand(perform: onClose)
    }

    private var header: some View {
        HStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "viewfinder")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppTheme.ColorToken.accent)
                Text(completionTitle)
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                if let message = viewModel.statusMessage {
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .overlay(NativeWindowDragHandle())

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .help("关闭")
        }
    }

    private var completionTitle: String {
        viewModel.result.captureCompletionKind == .scrollingScreenshot ? "截图完成" : "识别完成"
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.selectedTab {
        case .originalImage:
            if let image = viewModel.result.originalImage {
                screenshotImagePreview(image)
            } else {
                placeholderText("暂无截图")
            }
        case .ocr:
            ScrollView {
                Text(viewModel.hasRecognizedText ? viewModel.displayedText : (viewModel.result.ocrStatusMessage ?? "未识别到截图文字"))
                    .font(.system(size: 14, weight: .regular, design: .default))
                    .foregroundStyle(viewModel.hasRecognizedText ? Color.primary : Color.secondary)
                    .lineSpacing(5)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
            }
        case .translation, .summary:
            ZStack {
                ScrollView {
                    Text(viewModel.displayedText)
                        .font(.system(size: 14, weight: .regular, design: .default))
                        .foregroundStyle(Color.primary)
                        .lineSpacing(5)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                }
                if viewModel.isLoadingSelectedTab {
                    ProgressView()
                        .controlSize(.regular)
                        .padding(14)
                        .background(.regularMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        case .translatedOverlay:
            if let image = viewModel.translatedOverlayImage {
                screenshotImagePreview(image)
            } else {
                placeholderText("暂无翻译覆盖图")
            }
        }
    }

    private func screenshotImagePreview(_ image: CGImage) -> some View {
        GeometryReader { geometry in
            ScrollView(.vertical) {
                Image(nsImage: NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height)))
                    .resizable()
                    .aspectRatio(CGFloat(image.width) / max(CGFloat(image.height), 1), contentMode: .fit)
                    .frame(width: max(1, geometry.size.width - 24))
                    .padding(12)
                    .contextMenu {
                        Button {
                            viewModel.copySelectedImage()
                        } label: {
                            Label("复制图片", systemImage: "photo.on.rectangle")
                        }
                    }
            }
        }
    }

    private func placeholderText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func playbackBar(_ playback: ScreenshotOCRPlaybackState) -> some View {
        HStack(spacing: 10) {
            Text("正在朗读")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.ColorToken.accent)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(AppTheme.ColorToken.accentSoft)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            Text(playback.text)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            Button {
                viewModel.stopSpeaking()
            } label: {
                Image(systemName: "pause.fill")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .help("停止朗读")
        }
        .padding(10)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.74))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button {
                Task { await viewModel.translate() }
            } label: {
                Label("翻译", systemImage: "translate")
            }
            .disabled(viewModel.isTranslating || viewModel.isSummarizing)

            Button {
                viewModel.speakSelectedText()
            } label: {
                Label("朗读", systemImage: "speaker.wave.2")
            }
            .disabled(viewModel.selectedTab == .originalImage)

            Button {
                viewModel.copySelectedText()
            } label: {
                Label("复制文字", systemImage: "doc.on.doc")
            }

            Button {
                viewModel.copySelectedImage()
            } label: {
                Label("复制图片", systemImage: "photo.on.rectangle")
            }
            .disabled(viewModel.selectedImage == nil)

            Spacer()
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
    }
}
