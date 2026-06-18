import SwiftUI
import UniformTypeIdentifiers

struct GlossaryView: View {
    @ObservedObject var viewModel: GlossaryViewModel
    @State private var selectedSection = GlossarySection.words
    @State private var wordInput = ""
    @State private var replacementSource = ""
    @State private var replacementTarget = ""
    @State private var isImporterPresented = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.section) {
                header
                sectionPicker

                switch selectedSection {
                case .words:
                    wordListPanel
                case .replacements:
                    replacementPanel
                }
            }
            .padding(AppTheme.Spacing.page)
            .frame(maxWidth: 980, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(AppTheme.ColorToken.pageBackground)
        .tint(AppTheme.ColorToken.accent)
        .actionFeedbackOverlay(
            message: viewModel.lastActionMessage,
            error: viewModel.lastError,
            onDismiss: viewModel.clearFeedback
        )
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.plainText],
            allowsMultipleSelection: false
        ) { result in
            do {
                guard let url = try result.get().first else { return }
                _ = try viewModel.importWordList(from: url)
            } catch {
                viewModel.report(error: error)
            }
        }
        .onAppear {
            viewModel.load()
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                Label("词汇表", systemImage: "text.book.closed")
                    .font(.system(size: 28, weight: .semibold))
                Text("让常用词、专有名词和易错词识别得更准确。")
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
            }
            Spacer()
            if selectedSection == .words {
                Button {
                    isImporterPresented = true
                } label: {
                    Label("导入 TXT", systemImage: "doc.badge.plus")
                }
            }
        }
    }

    private var sectionPicker: some View {
        HStack(spacing: 12) {
            GlossarySectionButton(
                title: "易错词",
                subtitle: "每行一个单词或短语",
                systemImage: "text.book.closed.fill",
                isSelected: selectedSection == .words
            ) {
                selectedSection = .words
            }
            GlossarySectionButton(
                title: "文本替换",
                subtitle: "把来源文本自动替换为目标文本",
                systemImage: "arrow.left.arrow.right",
                isSelected: selectedSection == .replacements
            ) {
                selectedSection = .replacements
            }
        }
    }

    private var wordListPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("添加易错词")
                        .font(.system(size: 13, weight: .semibold))
                    TextEditor(text: $wordInput)
                        .font(.system(size: 14))
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .frame(minHeight: 64, maxHeight: 100)
                        .background(AppTheme.ColorToken.panelBackground)
                        .overlay(controlBorder)
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.control))
                }
                Button {
                    addWords()
                } label: {
                    Label("添加", systemImage: "plus")
                        .frame(minWidth: 74)
                }
                .buttonStyle(.borderedProminent)
                .disabled(wordInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            TextField(
                "搜索易错词",
                text: Binding(
                    get: { viewModel.searchText },
                    set: { viewModel.updateSearch($0) }
                )
            )
            .textFieldStyle(.roundedBorder)

            if viewModel.terms.isEmpty {
                emptyState("暂无易错词，在上方添加或导入 TXT 文件")
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 180), spacing: 10)],
                    spacing: 10
                ) {
                    ForEach(viewModel.terms, id: \.id) { item in
                        HStack(spacing: 10) {
                            Text(item.term)
                                .font(.system(size: 14, weight: .medium))
                                .lineLimit(2)
                            Spacer()
                            Button {
                                viewModel.deleteTerm(id: item.id)
                            } label: {
                                Image(systemName: "trash")
                                    .frame(width: 32, height: 32)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.red)
                            .help("删除")
                        }
                        .padding(12)
                        .appPanel()
                    }
                }
            }

            if let summary = viewModel.lastImportSummary {
                Text("新增 \(summary.created) 个，跳过 \(summary.skipped) 个重复词条")
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
            }
        }
        .panelStyle()
    }

    private var replacementPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                TextField("来源文本", text: $replacementSource)
                Image(systemName: "arrow.right")
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
                TextField("替换为", text: $replacementTarget)
                Button {
                    addReplacement()
                } label: {
                    Label("添加", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .disabled(replacementSource.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .textFieldStyle(.roundedBorder)

            if viewModel.replacementRules.isEmpty {
                emptyState("暂无文本替换规则")
            } else {
                VStack(spacing: 10) {
                    ForEach(viewModel.replacementRules, id: \.id) { rule in
                        HStack(spacing: 12) {
                            Text(rule.source)
                                .fontWeight(.medium)
                            Image(systemName: "arrow.right")
                                .foregroundStyle(AppTheme.ColorToken.secondaryText)
                            Text(rule.target)
                            Spacer()
                            Button {
                                viewModel.deleteReplacementRule(id: rule.id)
                            } label: {
                                Image(systemName: "trash")
                                    .frame(width: 32, height: 32)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.red)
                            .help("删除")
                        }
                        .padding(12)
                        .appPanel()
                    }
                }
            }
        }
        .panelStyle()
    }

    private var controlBorder: some View {
        RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous)
            .stroke(AppTheme.ColorToken.subtleStroke, lineWidth: AppTheme.Border.panelLineWidth)
    }

    private func emptyState(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(AppTheme.ColorToken.secondaryText)
            .frame(maxWidth: .infinity, minHeight: 100)
    }

    private func addWords() {
        do {
            _ = try viewModel.addWordList(wordInput)
            wordInput = ""
        } catch {
            viewModel.report(error: error)
        }
    }

    private func addReplacement() {
        do {
            try viewModel.saveSimpleReplacement(
                source: replacementSource,
                target: replacementTarget
            )
            replacementSource = ""
            replacementTarget = ""
        } catch {
            viewModel.report(error: error)
        }
    }
}

private enum GlossarySection {
    case words
    case replacements
}

private struct GlossarySectionButton: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(AppTheme.ColorToken.accent)
                    .frame(width: 42, height: 42)
                    .background(isSelected ? AppTheme.ColorToken.accentSoft : AppTheme.ColorToken.controlBackground)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.icon, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.ColorToken.secondaryText)
                }
                Spacer()
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(
                isSelected
                    ? AppTheme.ColorToken.selectionBackground
                    : AppTheme.ColorToken.panelBackground
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                    .stroke(
                        isSelected
                            ? AppTheme.ColorToken.selectionBorder
                            : AppTheme.ColorToken.panelStroke,
                        lineWidth: AppTheme.Border.panelLineWidth
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous))
            .shadow(color: AppTheme.ColorToken.accent.opacity(isSelected ? 0.05 : 0.025), radius: 6, y: 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private extension View {
    func panelStyle() -> some View {
        self
            .padding(AppTheme.Spacing.card)
            .appPanel()
    }
}
