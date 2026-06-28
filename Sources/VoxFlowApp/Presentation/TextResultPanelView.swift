import AppKit
import SwiftUI

struct TextResultPanelShell<Header: View, Tabs: View, Content: View, Playback: View, Footer: View>: View {
    private let header: Header
    private let tabs: Tabs
    private let content: Content
    private let playback: Playback
    private let footer: Footer
    private let onClose: () -> Void

    init(
        onClose: @escaping () -> Void,
        @ViewBuilder header: () -> Header,
        @ViewBuilder tabs: () -> Tabs,
        @ViewBuilder content: () -> Content,
        @ViewBuilder playback: () -> Playback,
        @ViewBuilder footer: () -> Footer
    ) {
        self.onClose = onClose
        self.header = header()
        self.tabs = tabs()
        self.content = content()
        self.playback = playback()
        self.footer = footer()
    }

    var body: some View {
        VStack(spacing: 12) {
            header
            tabs
                .pickerStyle(.segmented)
                .labelsHidden()

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .textBackgroundColor).opacity(0.88))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            playback
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
}

struct TextResultPanelHeader: View {
    let iconSystemName: String
    let title: String
    let statusMessage: String?
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: iconSystemName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppTheme.ColorToken.accent)
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                if let statusMessage {
                    Text(statusMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .overlay(TextResultPanelDragHandle())

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .help(L10n.localize("hud.text_result.close", comment: ""))
        }
    }
}

struct TextResultScrollableTextView: View {
    let text: String
    let isPlaceholder: Bool
    let isLoading: Bool

    init(
        text: String,
        isPlaceholder: Bool = false,
        isLoading: Bool = false
    ) {
        self.text = text
        self.isPlaceholder = isPlaceholder
        self.isLoading = isLoading
    }

    var body: some View {
        ZStack {
            ScrollView {
                Text(text)
                    .font(.system(size: 14, weight: .regular, design: .default))
                    .foregroundStyle(isPlaceholder ? Color.secondary : Color.primary)
                    .lineSpacing(5)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
            }

            if isLoading {
                ProgressView()
                    .controlSize(.regular)
                    .padding(14)
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }
}

struct TextResultPlaybackBar: View {
    let text: String
    let onStop: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text(L10n.localize("hud.text_result.reading", comment: ""))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.ColorToken.accent)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(AppTheme.ColorToken.accentSoft)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            Button(action: onStop) {
                Image(systemName: "pause.fill")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .help(L10n.localize("hud.text_result.stop_reading", comment: ""))
        }
        .padding(10)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.74))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct TextResultFooterBar<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 8) {
            content
            Spacer()
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
    }
}

struct TextResultPanelDragHandle: NSViewRepresentable {
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
