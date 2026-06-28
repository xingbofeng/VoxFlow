import SwiftUI
import VoxFlowVoiceCorrection

private enum VoiceCorrectionLayout {
    static let libraryMinWidth: CGFloat = 620
    static let detailWidth: CGFloat = 300
    static let targetColumnWidth: CGFloat = 140
    static let scopeColumnWidth: CGFloat = 70
    static let countColumnWidth: CGFloat = 68
    static let recentColumnWidth: CGFloat = 68
    static let statusColumnWidth: CGFloat = 62
    static let actionColumnWidth: CGFloat = 36
    static let tableColumnSpacing: CGFloat = 12
}

struct VoiceCorrectionView: View {
    @ObservedObject var viewModel: VoiceCorrectionViewModel
    @State private var isNewTargetPopoverPresented = false
    @State private var isNewReplacementPopoverPresented = false
    @State private var isLearningDrawerPresented = true
    @State private var newTargetText = ""
    @State private var newAliasText = ""
    @State private var hotwordInput = ""
    @State private var replacementTrigger = ""
    @State private var replacementText = ""
    @State private var isClearAllAlertPresented = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.section) {
                header
                vocabularyTabs
                contentLayout
            }
            .padding(AppTheme.Spacing.page)
            .frame(maxWidth: 1_360, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(AppTheme.ColorToken.pageBackground)
        .tint(AppTheme.ColorToken.accent)
        .onAppear { viewModel.loadIfNeeded() }
        .alert(L10n.localize("correction.dialog.clear_all_title", comment: ""), isPresented: $isClearAllAlertPresented) {
            Button(L10n.localize("correction.action.cancel", comment: ""), role: .cancel) {}
            Button(L10n.localize("correction.action.clear", comment: ""), role: .destructive) {
                viewModel.clearAllRules()
            }
        } message: {
            Text(L10n.localize("correction.view.clear_all_message", comment: ""))
        }
        .actionFeedbackOverlay(
            message: viewModel.lastActionMessage,
            error: viewModel.lastError,
            onDismiss: viewModel.clearFeedback
        )
    }

    private var contentLayout: some View {
        Group {
            switch viewModel.selectedVocabularyTab {
            case .hotwords:
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: AppTheme.Spacing.section) {
                        hotwordPanel
                            .frame(minWidth: VoiceCorrectionLayout.libraryMinWidth)
                        learningDrawer
                            .frame(width: 360)
                    }

                    VStack(alignment: .leading, spacing: AppTheme.Spacing.section) {
                        hotwordPanel
                            .frame(minWidth: VoiceCorrectionLayout.libraryMinWidth)
                        learningDrawer
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            case .textReplacement:
                textReplacementPanel
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "text.badge.checkmark")
                .font(.system(size: 32, weight: .semibold))
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.localize("correction.view.title", comment: ""))
                    .font(.system(size: 30, weight: .semibold))
                Text(L10n.localize("correction.view.description", comment: ""))
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
            }
            Spacer()
            if viewModel.selectedVocabularyTab == .hotwords, viewModel.learningCandidates.isEmpty == false {
                Button {
                    isLearningDrawerPresented.toggle()
                } label: {
                    Label(L10n.localize("vocabulary.learning.drawer_title", comment: ""), systemImage: "sparkles")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var vocabularyTabs: some View {
        HStack(spacing: AppTheme.Spacing.grid) {
            ForEach(VoiceCorrectionVocabularyTab.allCases) { tab in
                Button {
                    viewModel.selectedVocabularyTab = tab
                    viewModel.searchText = ""
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: tab == .hotwords ? "book.closed" : "arrow.left.arrow.right")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(viewModel.selectedVocabularyTab == tab ? AppTheme.ColorToken.accent : AppTheme.ColorToken.secondaryText)
                            .frame(width: 44, height: 44)
                            .background(AppTheme.ColorToken.accent.opacity(viewModel.selectedVocabularyTab == tab ? 0.14 : 0.06))
                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.row, style: .continuous))
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Text(tab.title)
                                    .font(.system(size: 17, weight: .semibold))
                                Text(tab == .hotwords ? "\(viewModel.visibleTargetCount)" : "\(viewModel.rules.count)")
                                    .font(.system(size: 12, weight: .semibold))
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 4)
                                    .background(AppTheme.ColorToken.accent.opacity(0.10))
                                    .clipShape(Capsule())
                            }
                            Text(tab.subtitle)
                                .font(.system(size: 12))
                                .foregroundStyle(AppTheme.ColorToken.secondaryText)
                                .lineLimit(2)
                        }
                        Spacer()
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppTheme.ColorToken.panelBackground)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous)
                            .stroke(viewModel.selectedVocabularyTab == tab ? AppTheme.ColorToken.accent : AppTheme.ColorToken.subtleStroke)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var summaryCards: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: AppTheme.Spacing.grid), count: 3),
            spacing: AppTheme.Spacing.grid
        ) {
            statCard(
                title: L10n.localize("correction.target.title", comment: ""),
                value: "\(viewModel.visibleTargetCount)",
                subtitle: L10n.localize("correction.target.subtitle", comment: ""),
                systemImage: "textformat"
            )
            statCard(
                title: L10n.localize("correction.alias.title", comment: ""),
                value: "\(viewModel.visibleAliasCount)",
                subtitle: L10n.localize("correction.alias.subtitle", comment: ""),
                systemImage: "list.bullet"
            )
            statCard(
                title: L10n.localize("correction.weekly.title", comment: ""),
                value: "\(weeklyCorrectionCount)",
                subtitle: L10n.localize("correction.weekly.subtitle", comment: ""),
                systemImage: "clock.arrow.circlepath"
            )
        }
    }

    private var hotwordPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Button {
                    viewModel.openHotwordFile()
                } label: {
                    Label(L10n.localize("vocabulary.hotwords.file_button", comment: ""), systemImage: "doc.text")
                }
                .help(L10n.localize("vocabulary.hotwords.file_button_help", comment: ""))
                .buttonStyle(.bordered)

                Button {
                    viewModel.openHotwordFile()
                } label: {
                    Image(systemName: "folder")
                }
                .help(L10n.localize("vocabulary.hotwords.file_button_help", comment: ""))
                .buttonStyle(.bordered)

                Spacer()
                TextField(L10n.localize("correction.section.target_library_search_placeholder", comment: ""), text: $viewModel.searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 240)
            }

            HStack(spacing: 10) {
                Image(systemName: "plus")
                    .foregroundStyle(AppTheme.ColorToken.accent)
                TextField(L10n.localize("vocabulary.hotwords.input_placeholder", comment: ""), text: $hotwordInput)
                    .textFieldStyle(.plain)
                    .onSubmit(addHotwordFromInput)
                Text(L10n.localize("vocabulary.hotwords.input_return_hint", comment: ""))
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(AppTheme.ColorToken.panelBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.row, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.row, style: .continuous)
                    .stroke(AppTheme.ColorToken.accent.opacity(0.45))
            )

            if viewModel.filteredHotwordRows.isEmpty {
                emptyHotwords
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 145, maximum: 220), spacing: 10, alignment: .topLeading)],
                    alignment: .leading,
                    spacing: 10
                ) {
                    ForEach(viewModel.filteredHotwordRows) { row in
                        HotwordChip(row: row) {
                            viewModel.deleteHotword(row)
                        }
                    }
                }
            }

            Divider()
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(AppTheme.ColorToken.accent)
                Text(String(format: L10n.localize("vocabulary.hotwords.provider_budget_format", comment: ""), viewModel.visibleTargetCount))
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
                Spacer()
            }
        }
        .padding(AppTheme.Spacing.card)
        .appPanel()
    }

    private var learningDrawer: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(L10n.localize("vocabulary.learning.drawer_title", comment: ""))
                            .font(.system(size: 19, weight: .semibold))
                        Text("\(viewModel.learningCandidates.count)")
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(AppTheme.ColorToken.accent.opacity(0.10))
                            .clipShape(Capsule())
                    }
                    Text(L10n.localize("vocabulary.learning.drawer_description", comment: ""))
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.ColorToken.secondaryText)
                }
                Spacer()
                Button {
                    isLearningDrawerPresented.toggle()
                } label: {
                    Image(systemName: isLearningDrawerPresented ? "chevron.up" : "chevron.down")
                }
                .buttonStyle(.bordered)
                .help(L10n.localize(
                    isLearningDrawerPresented
                        ? "vocabulary.learning.action.collapse"
                        : "vocabulary.learning.action.expand",
                    comment: ""
                ))
            }

            if isLearningDrawerPresented {
                if viewModel.learningCandidates.isEmpty {
                    Text(L10n.localize("vocabulary.learning.empty", comment: ""))
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.ColorToken.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 20)
                } else {
                    ForEach(viewModel.learningCandidates) { candidate in
                        LearningCandidateRow(
                            candidate: candidate,
                            onAccept: { viewModel.acceptLearningCandidate(candidate) },
                            onIgnore: { viewModel.ignoreLearningCandidate(candidate) }
                        )
                    }
                }
            }
        }
        .padding(AppTheme.Spacing.card)
        .appPanel()
    }

    private var textReplacementPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 5) {
                    Label(L10n.localize("vocabulary.tab.text_replacement", comment: ""), systemImage: "arrow.left.arrow.right")
                        .font(.system(size: 20, weight: .semibold))
                    Text(L10n.localize("vocabulary.text_replacement.description", comment: ""))
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.ColorToken.secondaryText)
                }
                Spacer()
                TextField(L10n.localize("vocabulary.text_replacement.search_placeholder", comment: ""), text: $viewModel.searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 260)
                Button {
                    isNewReplacementPopoverPresented = true
                } label: {
                    Label(L10n.localize("vocabulary.text_replacement.add", comment: ""), systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .popover(isPresented: $isNewReplacementPopoverPresented, arrowEdge: .bottom) {
                    VoiceCorrectionReplacementPopover(
                        triggerText: $replacementTrigger,
                        replacementText: $replacementText,
                        onCancel: resetReplacementPopover,
                        onSave: saveReplacementRule
                    )
                }
                Button {
                    isClearAllAlertPresented = true
                } label: {
                    Label(L10n.localize("correction.action.clear", comment: ""), systemImage: "trash")
                }
                .buttonStyle(.bordered)
            }

            LazyVStack(spacing: 0) {
                if viewModel.filteredRules.isEmpty {
                    emptyTextReplacements
                } else {
                    ForEach(viewModel.filteredRules) { rule in
                        TextReplacementRuleRow(rule: rule, viewModel: viewModel)
                        Divider()
                    }
                }
            }
            .background(AppTheme.ColorToken.panelBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.row, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.row, style: .continuous)
                    .stroke(AppTheme.ColorToken.subtleStroke)
            )

            HStack(spacing: 8) {
                Image(systemName: "info.circle")
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
                Text(L10n.localize("vocabulary.text_replacement.order_hint", comment: ""))
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
            }
        }
        .padding(AppTheme.Spacing.card)
        .appPanel()
    }

    private var targetLibraryPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Label(L10n.localize("correction.section.target_library_title", comment: ""), systemImage: "list.bullet.rectangle")
                        .font(.system(size: 18, weight: .semibold))
                    Text(L10n.localize("correction.section.target_library_description", comment: ""))
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.ColorToken.secondaryText)
                }
                Spacer()
                TextField(L10n.localize("correction.section.target_library_search_placeholder", comment: ""), text: $viewModel.searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
                Button {
                    isNewTargetPopoverPresented = true
                } label: {
                    Image(systemName: "plus")
                }
                .help(L10n.localize("correction.help.add_target", comment: ""))
                .buttonStyle(.bordered)
                Button {
                    viewModel.openHotwordFile()
                } label: {
                    Image(systemName: "folder")
                }
                .help(L10n.localize("vocabulary.hotwords.file_button_help", comment: ""))
                .buttonStyle(.bordered)
                Button {
                    isClearAllAlertPresented = true
                } label: {
                    Image(systemName: "trash")
                }
                .help(L10n.localize("correction.help.clear_aliases", comment: ""))
                .buttonStyle(.bordered)
            }

            Picker("", selection: $viewModel.selectedFilter) {
                Text(L10n.localize("correction.filter.all", comment: "")).tag(VoiceCorrectionRuleFilter.all)
                Text(L10n.localize("correction.filter.active", comment: "")).tag(VoiceCorrectionRuleFilter.active)
                Text(L10n.localize("correction.filter.suspended", comment: "")).tag(VoiceCorrectionRuleFilter.suspended)
            }
            .pickerStyle(.segmented)
            .frame(width: 250)

            LazyVStack(spacing: 0) {
                targetHeader
                Divider()
                if viewModel.filteredTargetRows.isEmpty {
                    emptyTargets
                } else {
                    ForEach(viewModel.filteredTargetRows) { row in
                        VoiceCorrectionTargetRowView(
                            row: row,
                            isSelected: viewModel.selectedTarget?.id == row.id,
                            onSelect: { viewModel.selectTarget(row) }
                        )
                        Divider()
                    }
                }
            }
            .background(AppTheme.ColorToken.panelBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.row, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.row, style: .continuous)
                    .stroke(AppTheme.ColorToken.subtleStroke)
            )
        }
        .padding(AppTheme.Spacing.card)
        .appPanel()
    }

    private var targetDetailPanel: some View {
        VoiceCorrectionTargetDetailView(
            target: viewModel.selectedTarget,
            aliases: viewModel.selectedTargetAliases,
            recentLearningEvents: viewModel.recentLearningEvents,
            viewModel: viewModel
        )
    }

    private var targetHeader: some View {
        HStack(spacing: VoiceCorrectionLayout.tableColumnSpacing) {
            Text(L10n.localize("correction.table.header.target", comment: "")).frame(width: VoiceCorrectionLayout.targetColumnWidth, alignment: .leading)
            Text(L10n.localize("correction.alias.title", comment: "")).frame(maxWidth: .infinity, alignment: .leading)
            Text(L10n.localize("correction.table.header.scope", comment: "")).frame(width: VoiceCorrectionLayout.scopeColumnWidth, alignment: .leading)
            Text(L10n.localize("correction.table.header.count", comment: "")).frame(width: VoiceCorrectionLayout.countColumnWidth, alignment: .leading)
            Text(L10n.localize("correction.table.header.recent", comment: "")).frame(width: VoiceCorrectionLayout.recentColumnWidth, alignment: .leading)
            Text(L10n.localize("correction.table.header.status", comment: "")).frame(width: VoiceCorrectionLayout.statusColumnWidth, alignment: .leading)
            Text(L10n.localize("correction.table.header.action", comment: "")).frame(width: VoiceCorrectionLayout.actionColumnWidth, alignment: .trailing)
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(AppTheme.ColorToken.secondaryText)
        .padding(.horizontal, 12)
        .frame(height: 38)
    }

    private var emptyTargets: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.system(size: 24))
                .foregroundStyle(AppTheme.ColorToken.secondaryText)
            Text(L10n.localize("correction.list.empty_title", comment: ""))
                .font(.system(size: 14, weight: .medium))
            Text(L10n.localize("correction.list.empty_hint", comment: ""))
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.ColorToken.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
    }

    private var emptyHotwords: some View {
        VStack(spacing: 8) {
            Image(systemName: "book.closed")
                .font(.system(size: 24))
                .foregroundStyle(AppTheme.ColorToken.secondaryText)
            Text(L10n.localize("vocabulary.hotwords.empty_title", comment: ""))
                .font(.system(size: 14, weight: .medium))
            Text(L10n.localize("vocabulary.hotwords.empty_hint", comment: ""))
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.ColorToken.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
    }

    private var emptyTextReplacements: some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 24))
                .foregroundStyle(AppTheme.ColorToken.secondaryText)
            Text(L10n.localize("vocabulary.text_replacement.empty_title", comment: ""))
                .font(.system(size: 14, weight: .medium))
            Text(L10n.localize("vocabulary.text_replacement.empty_hint", comment: ""))
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.ColorToken.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
    }

    private func statCard(
        title: String,
        value: String,
        subtitle: String,
        systemImage: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppTheme.ColorToken.secondaryText)
            Text(value)
                .font(.system(size: 28, weight: .semibold))
            Text(subtitle)
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.ColorToken.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppTheme.Spacing.card)
        .appPanel()
    }

    private var weeklyCorrectionCount: Int {
        viewModel.targetRows.reduce(0) { sum, row in
            sum + row.projection.appliedCount
        }
    }

    private func addHotwordFromInput() {
        viewModel.addHotword(text: hotwordInput)
        hotwordInput = ""
    }

    private func saveReplacementRule() {
        var draft = viewModel.draftForNewRule()
        draft.original = replacementTrigger
        draft.replacement = replacementText
        draft.scope = .global
        draft.matchPolicy = .boundary
        viewModel.saveRule(draft)
        resetReplacementPopover()
    }

    private func resetReplacementPopover() {
        replacementTrigger = ""
        replacementText = ""
        isNewReplacementPopoverPresented = false
    }
}

private struct HotwordChip: View {
    let row: VoiceCorrectionTargetRow
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(row.targetText)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.tail)
            Text(row.hitCountText)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppTheme.ColorToken.secondaryText)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(AppTheme.ColorToken.accent.opacity(0.08))
                .clipShape(Capsule())
            Spacer(minLength: 6)
            Button(action: onDelete) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppTheme.ColorToken.secondaryText)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(AppTheme.ColorToken.panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.row, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.row, style: .continuous)
                .stroke(AppTheme.ColorToken.subtleStroke)
        )
    }
}

private struct LearningCandidateRow: View {
    let candidate: CorrectionTargetTerm
    let onAccept: () -> Void
    let onIgnore: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(candidate.text)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
                Button(L10n.localize("vocabulary.learning.accept", comment: ""), action: onAccept)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                Button(L10n.localize("vocabulary.learning.ignore", comment: ""), action: onIgnore)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            Text(String(format: L10n.localize("vocabulary.learning.observed_count_format", comment: ""), candidate.observedCount))
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.ColorToken.secondaryText)
        }
        .padding(12)
        .background(AppTheme.ColorToken.panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.row, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.row, style: .continuous)
                .stroke(AppTheme.ColorToken.subtleStroke)
        )
    }
}

private struct TextReplacementRuleRow: View {
    let rule: CorrectionRule
    @ObservedObject var viewModel: VoiceCorrectionViewModel

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(rule.original)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                HStack(spacing: 6) {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 11, weight: .semibold))
                    Text(rule.replacement)
                        .font(.system(size: 12))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .foregroundStyle(AppTheme.ColorToken.secondaryText)
            }
            Spacer()
            Text(String(format: L10n.localize("correction.target.correction_count_format", comment: ""), rule.appliedCount))
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.ColorToken.secondaryText)
            Menu {
                Button(L10n.localize("correction.action.pause_alias", comment: ""), systemImage: "pause.circle") {
                    viewModel.disableRule(rule)
                }
                Button(L10n.localize("correction.action.delete_alias", comment: ""), systemImage: "trash", role: .destructive) {
                    viewModel.deleteRule(rule)
                }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 26, height: 22)
            }
            .menuStyle(.borderlessButton)
        }
        .padding(.horizontal, 14)
        .frame(height: 58)
    }
}

private struct VoiceCorrectionTargetRowView: View {
    let row: VoiceCorrectionTargetRow
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: VoiceCorrectionLayout.tableColumnSpacing) {
                Text(row.targetText)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .frame(width: VoiceCorrectionLayout.targetColumnWidth, alignment: .leading)
                Text(row.aliasPreview)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(row.scopeTitle)
                    .frame(width: VoiceCorrectionLayout.scopeColumnWidth, alignment: .leading)
                Text(row.correctionCountText)
                    .frame(width: VoiceCorrectionLayout.countColumnWidth, alignment: .leading)
                Text(row.recentUseText)
                    .frame(width: VoiceCorrectionLayout.recentColumnWidth, alignment: .leading)
                HStack(spacing: 6) {
                    Circle()
                        .fill(statusTint)
                        .frame(width: 6, height: 6)
                    Text(row.statusTitle)
                }
                .frame(width: VoiceCorrectionLayout.statusColumnWidth, alignment: .leading)
                Image(systemName: "ellipsis")
                    .foregroundStyle(AppTheme.ColorToken.accent)
                    .frame(width: VoiceCorrectionLayout.actionColumnWidth, alignment: .trailing)
            }
            .font(.system(size: 13))
            .foregroundStyle(AppTheme.ColorToken.primaryText)
            .padding(.horizontal, 12)
            .frame(height: 50)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(isSelected ? AppTheme.ColorToken.accent.opacity(0.08) : .clear)
        }
        .buttonStyle(.plain)
    }

    private var statusTint: Color {
        row.projection.lifecycle == .active ? AppTheme.ColorToken.accent : AppTheme.ColorToken.secondaryText
    }
}

private struct VoiceCorrectionTargetDetailView: View {
    let target: VoiceCorrectionTargetRow?
    let aliases: [CorrectionRule]
    let recentLearningEvents: [VoiceCorrectionLearningEventRow]
    @ObservedObject var viewModel: VoiceCorrectionViewModel
    @State private var isAliasPopoverPresented = false
    @State private var aliasText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.section) {
            if let target {
                VStack(alignment: .leading, spacing: 6) {
                    Text(target.targetText)
                        .font(.system(size: 24, weight: .semibold))
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)
                Text(L10n.localize("correction.target.title", comment: ""))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppTheme.ColorToken.accent)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Label(L10n.localize("correction.detail.alias_section_title", comment: ""), systemImage: "text.quote")
                        .font(.system(size: 17, weight: .semibold))
                    ForEach(aliases) { alias in
                        aliasRow(alias)
                    }
                    Button {
                        isAliasPopoverPresented = true
                    } label: {
                        Label(L10n.localize("correction.action.add_alias", comment: ""), systemImage: "plus")
                    }
                    .buttonStyle(.bordered)
                    .popover(isPresented: $isAliasPopoverPresented, arrowEdge: .trailing) {
                        VoiceCorrectionAliasPopover(
                            aliasText: $aliasText,
                            onCancel: {
                                aliasText = ""
                                isAliasPopoverPresented = false
                            },
                            onSave: {
                                viewModel.addAliases(to: target, aliasesText: aliasText)
                                aliasText = ""
                                isAliasPopoverPresented = false
                            }
                        )
                    }
                }
                .padding(AppTheme.Spacing.card)
                .appPanel()

                if recentLearningEvents.isEmpty == false {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(L10n.localize("correction.detail.recent_learning_title", comment: ""), systemImage: "sparkles")
                            .font(.system(size: 17, weight: .semibold))
                        ForEach(recentLearningEvents) { event in
                            HStack(spacing: 8) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(event.title)
                                        .font(.system(size: 13, weight: .medium))
                                    Text(L10n.localize("correction.detail.recent_learning_text", comment: ""))
                                        .font(.system(size: 12))
                                        .foregroundStyle(AppTheme.ColorToken.secondaryText)
                                }
                                Spacer()
                                Button(L10n.localize("correction.action.undo", comment: "")) {
                                    viewModel.undoRecentLearning()
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                    .padding(AppTheme.Spacing.card)
                    .appPanel()
                }

                DisclosureGroup(L10n.localize("correction.detail.advanced_settings_title", comment: "")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.localize("correction.detail.advanced_settings_help", comment: ""))
                            .font(.system(size: 12))
                            .foregroundStyle(AppTheme.ColorToken.secondaryText)
                    }
                    .padding(.top, 8)
                }
                .font(.system(size: 13, weight: .medium))
                .padding(AppTheme.Spacing.card)
                .appPanel()
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Label(L10n.localize("correction.detail.no_target_title", comment: ""), systemImage: "sidebar.right")
                        .font(.system(size: 17, weight: .semibold))
                    Text(L10n.localize("correction.detail.no_target_hint", comment: ""))
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.ColorToken.secondaryText)
                }
                .padding(AppTheme.Spacing.card)
                .appPanel()
            }
        }
    }

    private func aliasRow(_ alias: CorrectionRule) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(alias.lifecycle == .active && alias.isEnabled ? AppTheme.ColorToken.accent : AppTheme.ColorToken.secondaryText)
                .frame(width: 6, height: 6)
            VStack(alignment: .leading, spacing: 2) {
                Text(alias.original)
                    .font(.system(size: 13, weight: .medium))
                Text(String(format: L10n.localize("correction.target.correction_count_format", comment: ""), alias.appliedCount))
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
            }
            Spacer()
            Menu {
                Button(L10n.localize("correction.action.pause_alias", comment: ""), systemImage: "pause.circle") {
                    viewModel.disableRule(alias)
                }
                Button(L10n.localize("correction.action.delete_alias", comment: ""), systemImage: "trash", role: .destructive) {
                    viewModel.deleteRule(alias)
                }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 26, height: 22)
            }
            .menuStyle(.borderlessButton)
        }
        .padding(.vertical, 6)
    }
}

private struct VoiceCorrectionReplacementPopover: View {
    @Binding var triggerText: String
    @Binding var replacementText: String
    let onCancel: () -> Void
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.localize("vocabulary.text_replacement.modal.title", comment: ""))
                .font(.system(size: 18, weight: .semibold))
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.localize("vocabulary.text_replacement.modal.trigger", comment: ""))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
                TextField(L10n.localize("vocabulary.text_replacement.modal.trigger_placeholder", comment: ""), text: $triggerText)
                    .textFieldStyle(.roundedBorder)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.localize("vocabulary.text_replacement.modal.replacement", comment: ""))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
                TextEditor(text: $replacementText)
                    .font(.system(size: 13))
                    .frame(width: 300, height: 120)
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.Radius.row, style: .continuous)
                            .stroke(AppTheme.ColorToken.subtleStroke)
                    )
            }
            HStack {
                Spacer()
                Button(L10n.localize("correction.action.cancel", comment: ""), action: onCancel)
                Button(L10n.localize("correction.action.save", comment: ""), action: onSave)
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        triggerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                            replacementText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
            }
        }
        .padding(18)
        .frame(width: 340)
    }
}

private struct VoiceCorrectionAliasPopover: View {
    @Binding var aliasText: String
    let onCancel: () -> Void
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.localize("correction.popover.add_alias_title", comment: ""))
                .font(.system(size: 18, weight: .semibold))
            Text(L10n.localize("correction.popover.add_alias_hint", comment: ""))
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.ColorToken.secondaryText)
            TextEditor(text: $aliasText)
                .font(.system(size: 13))
                .frame(width: 300, height: 110)
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.row, style: .continuous)
                        .stroke(AppTheme.ColorToken.subtleStroke)
                )
                HStack {
                    Spacer()
                    Button(L10n.localize("correction.action.cancel", comment: ""), action: onCancel)
                    Button(L10n.localize("correction.action.save", comment: ""), action: onSave)
                    .buttonStyle(.borderedProminent)
                    .disabled(aliasText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
        }
        .padding(18)
        .frame(width: 340)
    }
}

private struct VoiceCorrectionTargetPopover: View {
    @Binding var targetText: String
    @Binding var aliasText: String
    let onCancel: () -> Void
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.localize("correction.popover.new_target_title", comment: ""))
                .font(.system(size: 18, weight: .semibold))
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.localize("correction.target.title", comment: ""))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
                TextField("Qwen", text: $targetText)
                    .textFieldStyle(.roundedBorder)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.localize("correction.popover.aliases_title", comment: ""))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
                TextEditor(text: $aliasText)
                    .font(.system(size: 13))
                    .frame(width: 300, height: 96)
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.Radius.row, style: .continuous)
                            .stroke(AppTheme.ColorToken.subtleStroke)
                    )
            }
            HStack {
                Spacer()
                Button(L10n.localize("correction.action.cancel", comment: ""), action: onCancel)
                Button(L10n.localize("correction.action.save", comment: ""), action: onSave)
                    .buttonStyle(.borderedProminent)
                    .disabled(targetText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(18)
        .frame(width: 340)
    }
}
