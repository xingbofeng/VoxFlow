import AppKit
import SwiftUI

@MainActor
final class ScreenshotOCRResultPanelController {
    private let service: ScreenshotOCRService
    private let clipboard: any ClipboardSetting
    private var window: ScreenshotOCRResultPanel?

    init(service: ScreenshotOCRService, clipboard: any ClipboardSetting) {
        self.service = service
        self.clipboard = clipboard
    }

    func present(result: ScreenshotOCRResult) {
        let viewModel = ScreenshotOCRResultViewModel(
            result: result,
            service: service,
            clipboard: clipboard
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
        window.contentView = NSHostingView(rootView: rootView)
        position(window)
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        service.stopSpeaking()
        window?.close()
        window = nil
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
        panel.hidesOnDeactivate = false
        panel.worksWhenModal = true
        panel.onCancel = { [weak self] in self?.close() }
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
}

private final class ScreenshotOCRResultPanel: NSPanel {
    var onCancel: (() -> Void)?

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
                Text("OCR").tag(ScreenshotOCRResultTab.ocr)
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
    }

    private var header: some View {
        HStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "viewfinder")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.blue)
                Text("识别完成")
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
            .help("关闭")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.selectedTab {
        case .originalImage:
            if let image = viewModel.result.originalImage {
                Image(nsImage: NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height)))
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(12)
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
                .foregroundStyle(.green)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.green.opacity(0.12))
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
                Label("复制", systemImage: "doc.on.doc")
            }

            Spacer()
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
    }
}
