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
    @State private var newTargetText = ""
    @State private var newAliasText = ""
    @State private var isClearAllAlertPresented = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.section) {
                    header
                    summaryCards
                    contentLayout
                }
                .padding(AppTheme.Spacing.page)
                .frame(maxWidth: 1_360, alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .top)
            }

            if let message = viewModel.lastActionMessage {
                VoiceCorrectionToastView(
                    message: message,
                    onUndo: viewModel.undoRecentLearning,
                    onDismiss: viewModel.clearFeedback
                )
                .padding(.trailing, AppTheme.Spacing.page)
                .padding(.bottom, AppTheme.Spacing.page)
            }
        }
        .background(AppTheme.ColorToken.pageBackground)
        .tint(AppTheme.ColorToken.accent)
        .onAppear { viewModel.loadIfNeeded() }
        .alert("清空全部误听写法？", isPresented: $isClearAllAlertPresented) {
            Button("取消", role: .cancel) {}
            Button("清空", role: .destructive) {
                viewModel.clearAllRules()
            }
        } message: {
            Text("会删除所有目标词下的误听写法，不会影响历史记录。")
        }
        .actionFeedbackOverlay(
            message: nil,
            error: viewModel.lastError,
            onDismiss: viewModel.clearFeedback
        )
    }

    private var contentLayout: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: AppTheme.Spacing.section) {
                targetLibraryPanel
                    .frame(minWidth: VoiceCorrectionLayout.libraryMinWidth)
                targetDetailPanel
                    .frame(width: VoiceCorrectionLayout.detailWidth)
            }

            VStack(alignment: .leading, spacing: AppTheme.Spacing.section) {
                targetLibraryPanel
                    .frame(minWidth: VoiceCorrectionLayout.libraryMinWidth)
                targetDetailPanel
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "text.badge.checkmark")
                .font(.system(size: 32, weight: .semibold))
            VStack(alignment: .leading, spacing: 4) {
                Text("易错词")
                    .font(.system(size: 30, weight: .semibold))
                Text("维护常被听错的专名、术语和写法；OCR 只作为本次临时上下文，不写入这里。")
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
            }
            Spacer()
            Button {
                isNewTargetPopoverPresented = true
            } label: {
                Label("新增目标词", systemImage: "plus")
                    .frame(height: 30)
            }
            .buttonStyle(.borderedProminent)
            .popover(isPresented: $isNewTargetPopoverPresented, arrowEdge: .bottom) {
                VoiceCorrectionTargetPopover(
                    targetText: $newTargetText,
                    aliasText: $newAliasText,
                    onCancel: {
                        isNewTargetPopoverPresented = false
                    },
                    onSave: {
                        viewModel.createTarget(text: newTargetText, aliasesText: newAliasText)
                        newTargetText = ""
                        newAliasText = ""
                        isNewTargetPopoverPresented = false
                    }
                )
            }
        }
    }

    private var summaryCards: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: AppTheme.Spacing.grid), count: 3),
            spacing: AppTheme.Spacing.grid
        ) {
            statCard(title: "目标词", value: "\(viewModel.visibleTargetCount)", subtitle: "长期个人词库", systemImage: "textformat")
            statCard(title: "误听写法", value: "\(viewModel.visibleAliasCount)", subtitle: "手动添加与自动学习", systemImage: "list.bullet")
            statCard(title: "本周修正", value: "\(weeklyCorrectionCount)", subtitle: "可在历史中撤销", systemImage: "clock.arrow.circlepath")
        }
    }

    private var targetLibraryPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Label("目标词库", systemImage: "list.bullet.rectangle")
                        .font(.system(size: 18, weight: .semibold))
                    Text("先维护正确写法，再为它添加常见误听写法")
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.ColorToken.secondaryText)
                }
                Spacer()
                TextField("搜索目标词或误听写法", text: $viewModel.searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
                Button {
                    isNewTargetPopoverPresented = true
                } label: {
                    Image(systemName: "plus")
                }
                .help("新增目标词")
                .buttonStyle(.bordered)
                Button {
                    isClearAllAlertPresented = true
                } label: {
                    Image(systemName: "trash")
                }
                .help("清空误听写法")
                .buttonStyle(.bordered)
            }

            Picker("", selection: $viewModel.selectedFilter) {
                Text("全部").tag(VoiceCorrectionRuleFilter.all)
                Text("活跃").tag(VoiceCorrectionRuleFilter.active)
                Text("已暂停").tag(VoiceCorrectionRuleFilter.suspended)
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
            Text("目标词").frame(width: VoiceCorrectionLayout.targetColumnWidth, alignment: .leading)
            Text("误听写法").frame(maxWidth: .infinity, alignment: .leading)
            Text("作用范围").frame(width: VoiceCorrectionLayout.scopeColumnWidth, alignment: .leading)
            Text("修正次数").frame(width: VoiceCorrectionLayout.countColumnWidth, alignment: .leading)
            Text("最近使用").frame(width: VoiceCorrectionLayout.recentColumnWidth, alignment: .leading)
            Text("状态").frame(width: VoiceCorrectionLayout.statusColumnWidth, alignment: .leading)
            Text("操作").frame(width: VoiceCorrectionLayout.actionColumnWidth, alignment: .trailing)
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
            Text("暂无目标词")
                .font(.system(size: 14, weight: .medium))
            Text("新增目标词后，可以继续添加常见误听写法。")
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
                    Text("目标词")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppTheme.ColorToken.accent)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Label("常见误听写法", systemImage: "text.quote")
                        .font(.system(size: 17, weight: .semibold))
                    ForEach(aliases) { alias in
                        aliasRow(alias)
                    }
                    Button {
                        isAliasPopoverPresented = true
                    } label: {
                        Label("添加误听写法", systemImage: "plus")
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
                        Label("最近学习", systemImage: "sparkles")
                            .font(.system(size: 17, weight: .semibold))
                        ForEach(recentLearningEvents) { event in
                            HStack(spacing: 8) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(event.title)
                                        .font(.system(size: 13, weight: .medium))
                                    Text("刚刚自动学习")
                                        .font(.system(size: 12))
                                        .foregroundStyle(AppTheme.ColorToken.secondaryText)
                                }
                                Spacer()
                                Button("撤销") {
                                    viewModel.undoRecentLearning()
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                    .padding(AppTheme.Spacing.card)
                    .appPanel()
                }

                DisclosureGroup("高级设置") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("作用范围、大小写敏感和匹配方式会在这里调整。")
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
                    Label("选择目标词", systemImage: "sidebar.right")
                        .font(.system(size: 17, weight: .semibold))
                    Text("从左侧目标词库选择一个词，查看它的常见误听写法。")
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
                Text("\(alias.appliedCount) 次")
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
            }
            Spacer()
            Menu {
                Button("暂停写法", systemImage: "pause.circle") {
                    viewModel.disableRule(alias)
                }
                Button("删除写法", systemImage: "trash", role: .destructive) {
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

private struct VoiceCorrectionAliasPopover: View {
    @Binding var aliasText: String
    let onCancel: () -> Void
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("添加误听写法")
                .font(.system(size: 18, weight: .semibold))
            Text("每行一个常见听错写法。")
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
                Button("取消", action: onCancel)
                Button("保存", action: onSave)
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
            Text("新增目标词")
                .font(.system(size: 18, weight: .semibold))
            VStack(alignment: .leading, spacing: 6) {
                Text("目标词")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
                TextField("Qwen", text: $targetText)
                    .textFieldStyle(.roundedBorder)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("常见误听写法（可选，每行一个）")
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
                Button("取消", action: onCancel)
                Button("保存", action: onSave)
                    .buttonStyle(.borderedProminent)
                    .disabled(targetText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(18)
        .frame(width: 340)
    }
}

private struct VoiceCorrectionToastView: View {
    let message: String
    let onUndo: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(AppTheme.ColorToken.accent)
            Text(message.hasPrefix("已学习：") ? message : "已学习：\(message)")
                .font(.system(size: 13, weight: .medium))
            Button("撤销", action: onUndo)
                .buttonStyle(.borderless)
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 14)
        .frame(height: 42)
        .background(AppTheme.ColorToken.panelBackground)
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.row, style: .continuous)
                .stroke(AppTheme.ColorToken.accent.opacity(0.35))
        )
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.row, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 18, x: 0, y: 8)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                onDismiss()
            }
        }
    }
}
