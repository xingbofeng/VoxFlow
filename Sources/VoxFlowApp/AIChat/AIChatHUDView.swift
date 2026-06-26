import AppKit
import SwiftUI
import MarkdownUI

private enum AIChatPanelConstants {
    static let bottomAnchorID = "ai-chat-bottom-anchor"
}

/// 问 AI 聊天面板视图。复用 `TextResultPanelController` 右侧浮窗，
/// 视觉语言与 `TextResultPanelShell` 保持一致（`.regularMaterial` 背景、圆角 12、拖拽 header）。
struct AIChatPanelView: View {
    @ObservedObject var viewModel: AIChatSessionViewModel
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            header
            messageList
            inputBar
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .frame(width: 440, height: 560)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        )
        .onExitCommand(perform: onClose)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(AppTheme.ColorToken.accent)
                    .frame(width: 32, height: 32)
                    .background(AppTheme.ColorToken.accentSoft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text("问 AI")
                        .font(.system(size: 15, weight: .semibold))
                    if viewModel.isStreaming {
                        Text("流式回复中…")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    } else if let error = viewModel.configurationError {
                        Text(error)
                            .font(.system(size: 12))
                            .foregroundStyle(.orange)
                            .lineLimit(1)
                    } else {
                        Text("使用已配置模型 · 多轮对话")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .overlay(TextResultPanelDragHandle())

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background(Color.primary.opacity(0.06), in: Circle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .help("关闭")
        }
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if let error = viewModel.configurationError {
                        configurationErrorView(error)
                    }
                    ForEach(viewModel.messages) { message in
                        messageRow(message)
                    }
                    Color.clear
                        .frame(height: 1)
                        .id(AIChatPanelConstants.bottomAnchorID)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 12)
            }
            .onAppear {
                scrollToBottom(proxy, animated: false)
            }
            .onChange(of: viewModel.messages.count) { _, _ in
                scrollToBottom(proxy)
            }
            .onChange(of: viewModel.messages.last?.content) { _, _ in
                if viewModel.isStreaming {
                    scrollToBottom(proxy)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.82))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private func configurationErrorView(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }

    private func messageRow(_ message: AIChatMessage) -> some View {
        HStack(alignment: .top, spacing: 8) {
            AIChatRoleBadge(role: message.role)
            VStack(alignment: .trailing, spacing: 6) {
                AIChatMessageBubble(role: message.role) {
                    messageContent(message)
                }
                if message.showsCopyAction {
                    Button {
                        copyToPasteboard(message.content)
                    } label: {
                        Label("复制回复", systemImage: "doc.on.doc")
                            .labelStyle(.titleAndIcon)
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.primary.opacity(0.06), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("复制 AI 回复")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func messageContent(_ message: AIChatMessage) -> some View {
        switch message.status {
        case .failed(let detail):
            Text("请求失败：\(detail)")
                .foregroundStyle(.red)
                .font(.system(size: 13))
                .textSelection(.enabled)
        case .streaming:
            if message.content.isEmpty {
                Text("…")
                    .foregroundStyle(.secondary)
                    .italic()
            } else {
                Markdown(message.content)
                    .markdownTextStyle(\.text) {
                        FontSize(13)
                    }
            }
        case .complete:
            if message.role == .assistant {
                Markdown(message.content)
                    .markdownTextStyle(\.text) {
                        FontSize(13)
                    }
            } else {
                Text(message.content)
                    .font(.system(size: 13))
                    .lineSpacing(3)
                    .textSelection(.enabled)
            }
        }
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("继续追问…", text: $viewModel.inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...4)
                .font(.system(size: 13))
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(nsColor: .textBackgroundColor).opacity(0.84))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                )
                .onSubmit(send)
            Button(action: send) {
                Image(systemName: viewModel.isStreaming ? "stop.circle.fill" : "arrow.up.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(
                        viewModel.isStreaming
                            ? Color.red.opacity(0.82)
                            : sendButtonColor
                    )
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.isStreaming && trimmedInput.isEmpty)
            .help(viewModel.isStreaming ? "停止生成" : "发送")
        }
    }

    private var trimmedInput: String {
        viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var sendButtonColor: Color {
        trimmedInput.isEmpty ? Color.secondary.opacity(0.55) : AppTheme.ColorToken.accent
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool = true) {
        let action = {
            proxy.scrollTo(AIChatPanelConstants.bottomAnchorID, anchor: .bottom)
        }
        if animated {
            withAnimation(.easeOut(duration: 0.18), action)
        } else {
            action()
        }
    }

    private func send() {
        if viewModel.isStreaming {
            viewModel.stop()
            return
        }
        let text = viewModel.inputText
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        viewModel.inputText = ""
        viewModel.send(text)
    }

    private func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

private extension AIChatMessage {
    var showsCopyAction: Bool {
        guard role == .assistant, !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        if case .complete = status { return true }
        return false
    }
}

private struct AIChatRoleBadge: View {
    let role: AIChatMessage.Role

    var body: some View {
        Text(role == .user ? "你" : "AI")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(role == .user ? AppTheme.ColorToken.accent : Color.secondary)
            .frame(width: 30, height: 24)
            .background(background, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private var background: Color {
        role == .user ? AppTheme.ColorToken.accentSoft : Color.primary.opacity(0.06)
    }
}

private struct AIChatMessageBubble<Content: View>: View {
    let role: AIChatMessage.Role
    private let content: Content

    init(
        role: AIChatMessage.Role,
        @ViewBuilder content: () -> Content
    ) {
        self.role = role
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(border, lineWidth: 1)
            )
    }

    private var background: Color {
        role == .user
            ? AppTheme.ColorToken.accentSoft.opacity(0.65)
            : Color(nsColor: .controlBackgroundColor).opacity(0.72)
    }

    private var border: Color {
        role == .user
            ? AppTheme.ColorToken.accent.opacity(0.16)
            : Color.primary.opacity(0.06)
    }
}
