import AppKit
import SwiftUI

@MainActor
final class ScreenshotOCRResultPanelController {
    private static let logger = AppLogger.general

    private let service: ScreenshotOCRService
    private let clipboard: any ScreenshotOCRResultClipboard
    private let autoDismissScheduler: any ScreenshotOCRResultAutoDismissScheduling
    private let panelController = TextResultPanelController(title: "屏幕识别")
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

        Self.logger.debug("ScreenshotOCRResultPanelController using window")
        panelController.present(
            rootView: rootView,
            contentSize: NSSize(width: 440, height: 560),
            onCancel: { [weak self] in self?.close() },
            onInteraction: { [weak self] in self?.cancelAutoDismissForInteraction() }
        )
        if autoDismiss {
            scheduleAutoDismiss()
        } else {
            cancelAutoDismissForInteraction()
        }
    }

    func presentThumbnail(
        result: ScreenshotOCRResult,
        initialTab: ScreenshotOCRResultTab = .originalImage,
        overlayImage: CGImage? = nil
    ) {
        Self.logger.debug(
            "ScreenshotOCRResultPanelController presentThumbnail requested initialTab=\(initialTab) image=\(result.originalImage != nil)"
        )
        autoDismissToken?.cancel()
        autoDismissToken = nil
        ContextBoostSuppression.setSuppressed(true, reason: Self.contextBoostSuppressionReason)

        let rootView = ScreenshotOCRResultThumbnailView(
            result: result,
            overlayImage: overlayImage,
            onOpen: { [weak self] in
                self?.present(
                    result: result,
                    initialTab: initialTab,
                    autoDismiss: false,
                    overlayImage: overlayImage
                )
            }
        )

        panelController.present(
            rootView: rootView,
            contentSize: NSSize(width: 260, height: 150),
            bottomMargin: 28,
            onCancel: { [weak self] in self?.close() }
        )
        autoDismissToken = autoDismissScheduler.schedule(after: 3) { [weak self] in
            self?.close()
        }
    }

    func close() {
        Self.logger.debug("ScreenshotOCRResultPanelController close")
        autoDismissToken?.cancel()
        autoDismissToken = nil
        ContextBoostSuppression.setSuppressed(false, reason: Self.contextBoostSuppressionReason)
        service.stopSpeaking()
        panelController.close()
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

private struct ScreenshotOCRResultView: View {
    @ObservedObject var viewModel: ScreenshotOCRResultViewModel
    let onClose: () -> Void

    var body: some View {
        TextResultPanelShell(onClose: onClose) {
            TextResultPanelHeader(
                iconSystemName: "viewfinder",
                title: completionTitle,
                statusMessage: viewModel.statusMessage,
                onClose: onClose
            )
        } tabs: {
            Picker("", selection: $viewModel.selectedTab) {
                Text("原图").tag(ScreenshotOCRResultTab.originalImage)
                Text("识别").tag(ScreenshotOCRResultTab.ocr)
                Text("翻译").tag(ScreenshotOCRResultTab.translation)
                Text("总结").tag(ScreenshotOCRResultTab.summary)
            }
            .onChange(of: viewModel.selectedTab) {
                viewModel.activateSelectedTabTaskIfNeeded()
            }
        } content: {
            content
        } playback: {
            if let playback = viewModel.playbackState {
                TextResultPlaybackBar(text: playback.text) {
                    viewModel.stopSpeaking()
                }
            }
        } footer: {
            footer
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
            TextResultScrollableTextView(
                text: viewModel.hasRecognizedText ? viewModel.displayedText : (viewModel.result.ocrStatusMessage ?? "未识别到截图文字"),
                isPlaceholder: !viewModel.hasRecognizedText
            )
        case .translation, .summary:
            TextResultScrollableTextView(
                text: viewModel.displayedText,
                isLoading: viewModel.isLoadingSelectedTab
            )
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

    private var footer: some View {
        TextResultFooterBar {
            Button {
                viewModel.startTranslationTask()
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
        }
    }
}

private struct ScreenshotOCRResultThumbnailView: View {
    let result: ScreenshotOCRResult
    let overlayImage: CGImage?
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            thumbnailContent
                .frame(width: 260, height: 150)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.22), radius: 16, x: 0, y: 8)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var thumbnailContent: some View {
        if let image = overlayImage ?? result.originalImage {
            Image(nsImage: NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height)))
                .resizable()
                .scaledToFill()
        } else {
            Text(result.originalText.isEmpty ? "截图完成" : result.originalText)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(4)
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Color(nsColor: .windowBackgroundColor))
        }
    }
}
