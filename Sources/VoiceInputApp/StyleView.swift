import SwiftUI

struct StyleView: View {
    @ObservedObject var viewModel: StyleViewModel
    @State private var prompt = ""

    var body: some View {
        HStack(spacing: 0) {
            styleList
                .frame(width: 300)
                .background(AppTheme.ColorToken.sidebarBackground)
            Divider()
            editor
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(AppTheme.ColorToken.pageBackground)
        .tint(AppTheme.ColorToken.accent)
        .onAppear {
            viewModel.load()
            prompt = viewModel.selectedProfile?.prompt ?? ""
        }
    }

    private var styleList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("风格", systemImage: "slider.horizontal.3")
                .font(.system(size: 24, weight: .semibold))
                .padding(.horizontal, 18)
                .padding(.top, 22)

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(viewModel.profiles, id: \.id) { profile in
                        Button {
                            select(profile)
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: profile.iconName)
                                    .foregroundStyle(AppTheme.ColorToken.accent)
                                    .frame(width: 24, height: 24)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(profile.name)
                                        .font(.system(size: 14, weight: .semibold))
                                    if let subtitle = profile.subtitle {
                                        Text(subtitle)
                                            .font(.system(size: 12))
                                            .foregroundStyle(AppTheme.ColorToken.secondaryText)
                                            .lineLimit(2)
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 11)
                            .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
                            .background(viewModel.selectedProfile?.id == profile.id ? AppTheme.ColorToken.selectionBackground : Color.clear)
                            .overlay(
                                RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                                    .stroke(
                                        viewModel.selectedProfile?.id == profile.id
                                            ? AppTheme.ColorToken.selectionBorder
                                            : Color.clear,
                                        lineWidth: AppTheme.Border.selectedLineWidth
                                    )
                            )
                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 18)
            }
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.section) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.selectedProfile?.name ?? "风格")
                        .font(.system(size: 26, weight: .semibold))
                    Text("编辑 Markdown 提示词，并在右侧实时预览。")
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.ColorToken.secondaryText)
                }
                Spacer()
                Button("确认") {
                    savePrompt()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(viewModel.selectedProfile == nil)
            }

            ActionFeedbackView(
                message: viewModel.lastActionMessage,
                error: viewModel.lastError,
                onDismiss: viewModel.clearFeedback
            )

            HSplitView {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Markdown", systemImage: "text.alignleft")
                        .font(.system(size: 13, weight: .semibold))
                    TextEditor(text: $prompt)
                        .font(.system(.body, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .padding(10)
                        .background(AppTheme.ColorToken.panelBackground)
                        .overlay(editorBorder)
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.card))
                        .shadow(color: AppTheme.ColorToken.accent.opacity(0.03), radius: 6, y: 2)
                }
                .frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity)

                VStack(alignment: .leading, spacing: 8) {
                    Label("预览", systemImage: "eye")
                        .font(.system(size: 13, weight: .semibold))
                    ScrollView {
                        Text(markdownPreview)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .padding(14)
                    }
                    .background(AppTheme.ColorToken.panelBackground)
                    .overlay(editorBorder)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.card))
                    .shadow(color: AppTheme.ColorToken.accent.opacity(0.03), radius: 6, y: 2)
                }
                .frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(AppTheme.Spacing.page)
    }

    private var markdownPreview: AttributedString {
        (try? AttributedString(
            markdown: prompt,
            options: .init(interpretedSyntax: .full)
        )) ?? AttributedString(prompt)
    }

    private var editorBorder: some View {
        RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
            .stroke(AppTheme.ColorToken.panelStroke, lineWidth: AppTheme.Border.panelLineWidth)
    }

    private func select(_ profile: StyleProfileRecord) {
        do {
            try viewModel.selectProfile(id: profile.id)
            prompt = viewModel.selectedProfile?.prompt ?? profile.prompt
        } catch {
            viewModel.report(error: error)
        }
    }

    private func savePrompt() {
        guard let profile = viewModel.selectedProfile else { return }
        do {
            try viewModel.updateProfile(id: profile.id, prompt: prompt)
            prompt = viewModel.selectedProfile?.prompt ?? prompt
        } catch {
            viewModel.report(error: error)
        }
    }
}

private extension StyleProfileRecord {
    var iconName: String {
        switch id {
        case "builtin.original": return "text.alignleft"
        case "builtin.formal": return "doc.text"
        case "builtin.casual": return "bubble.left.and.bubble.right"
        case "builtin.energetic": return "sparkles"
        case "builtin.coding": return "chevron.left.forwardslash.chevron.right"
        case "builtin.email": return "envelope"
        default: return "slider.horizontal.3"
        }
    }
}
