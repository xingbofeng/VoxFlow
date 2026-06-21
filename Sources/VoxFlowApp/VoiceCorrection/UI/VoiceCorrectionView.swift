import SwiftUI
import VoxFlowVoiceCorrection

struct VoiceCorrectionView: View {
    @ObservedObject var viewModel: VoiceCorrectionViewModel
    @State private var editorDraft = VoiceCorrectionRuleDraft.empty(currentBundleIdentifier: nil)
    @State private var isEditorPresented = false
    @State private var pendingDeleteRule: CorrectionRule?
    @State private var isClearAllAlertPresented = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.section) {
                header
                if viewModel.shadowMode {
                    shadowModeBanner
                }
                summaryCards
                contentGrid
            }
            .padding(AppTheme.Spacing.page)
            .frame(maxWidth: 1_260, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(AppTheme.ColorToken.pageBackground)
        .tint(AppTheme.ColorToken.accent)
        .onAppear { viewModel.loadIfNeeded() }
        .sheet(isPresented: $isEditorPresented) {
            VoiceCorrectionRuleEditor(
                draft: $editorDraft,
                viewModel: viewModel,
                onCancel: { isEditorPresented = false },
                onSave: {
                    viewModel.saveRule(editorDraft)
                    isEditorPresented = false
                }
            )
        }
        .alert("删除规则？", isPresented: deleteAlertBinding) {
            Button("取消", role: .cancel) {
                pendingDeleteRule = nil
            }
            Button("删除", role: .destructive) {
                if let pendingDeleteRule {
                    viewModel.deleteRule(pendingDeleteRule)
                }
                pendingDeleteRule = nil
            }
        } message: {
            Text("删除后不会影响历史记录。")
        }
        .alert("清空全部规则？", isPresented: $isClearAllAlertPresented) {
            Button("取消", role: .cancel) {}
            Button("清空", role: .destructive) {
                viewModel.clearAllRules()
            }
        } message: {
            Text("所有活跃规则、候选规则和已暂停规则都会删除。")
        }
        .actionFeedbackOverlay(
            message: viewModel.lastActionMessage,
            error: viewModel.lastError,
            onDismiss: viewModel.clearFeedback
        )
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "text.badge.checkmark")
                .font(.system(size: 32, weight: .semibold))
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 10) {
                    Text("易错词")
                        .font(.system(size: 30, weight: .semibold))
                    if viewModel.candidateRules.isEmpty == false {
                        badge("\(viewModel.candidateRules.count) 个候选", tint: .orange)
                    }
                }
                Text("ASR 输出和 LLM 修正之后运行，只处理普通听写 final transcript。")
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
            }
            Spacer()
            Button {
                editorDraft = viewModel.draftForNewRule()
                isEditorPresented = true
            } label: {
                Label("新增规则", systemImage: "plus")
                    .frame(height: 30)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var shadowModeBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "shield.lefthalf.filled")
                .foregroundStyle(.orange)
            Text("Shadow Mode 已开启：系统只记录会发生的修正，不会修改输入文本。")
                .font(.system(size: 13, weight: .medium))
            Spacer()
            Toggle(
                "",
                isOn: shadowModeBinding
            )
            .toggleStyle(.switch)
            .labelsHidden()
        }
        .padding(.horizontal, 14)
        .frame(height: 42)
        .background(.orange.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.row, style: .continuous)
                .stroke(.orange.opacity(0.24))
        )
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.row, style: .continuous))
    }

    private var summaryCards: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: AppTheme.Spacing.grid), count: 4),
            spacing: AppTheme.Spacing.grid
        ) {
            toggleCard(
                title: "启用状态",
                value: viewModel.isEnabled ? "已开启" : "已关闭",
                systemImage: "shield.checkered",
                isOn: enabledBinding
            )
            statCard(title: "活跃规则", value: "\(viewModel.activeRules.count)", systemImage: "list.bullet")
            statCard(title: "候选规则", value: "\(viewModel.candidateRules.count)", systemImage: "tray.full")
            statCard(title: "Benchmark", value: viewModel.benchmarkStatusTitle, subtitle: viewModel.benchmarkStatusDetail, systemImage: "checkmark.seal")
        }
    }

    private var contentGrid: some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.section) {
            rulesPanel
                .frame(minWidth: 620)
            VStack(spacing: AppTheme.Spacing.section) {
                safetyPanel
                candidatesPanel
                recentLearningPanel
            }
            .frame(width: 310)
        }
    }

    private var rulesPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Label("规则列表", systemImage: "list.bullet.rectangle")
                        .font(.system(size: 18, weight: .semibold))
                    Text("ASR 输出后自动修正，不影响 OCR 和指令模式")
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.ColorToken.secondaryText)
                }
                Spacer()
                TextField("搜索易错词", text: $viewModel.searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 210)
                Button {
                    editorDraft = viewModel.draftForNewRule()
                    isEditorPresented = true
                } label: {
                    Image(systemName: "plus")
                }
                .help("新增规则")
                .buttonStyle(.bordered)
                Button {
                    isClearAllAlertPresented = true
                } label: {
                    Image(systemName: "trash")
                }
                .help("清空全部规则")
                .buttonStyle(.bordered)
            }

            Picker("", selection: $viewModel.selectedFilter) {
                ForEach(VoiceCorrectionRuleFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 300)

            LazyVStack(spacing: 0) {
                ruleHeader
                Divider()
                if viewModel.filteredRules.isEmpty {
                    emptyRules
                } else {
                    ForEach(viewModel.filteredRules) { rule in
                        VoiceCorrectionRuleRowView(
                            rule: rule,
                            viewModel: viewModel,
                            onEdit: {
                                editorDraft = viewModel.draft(for: rule)
                                isEditorPresented = true
                            },
                            onDelete: {
                                pendingDeleteRule = rule
                            }
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

    private var ruleHeader: some View {
        HStack(spacing: 14) {
            Text("原文").frame(maxWidth: .infinity, alignment: .leading)
            Text("替换为").frame(maxWidth: .infinity, alignment: .leading)
            Text("作用范围").frame(width: 110, alignment: .leading)
            Text("匹配策略").frame(width: 80, alignment: .leading)
            Text("状态").frame(width: 76, alignment: .leading)
            Text("应用次数").frame(width: 70, alignment: .leading)
            Text("操作").frame(width: 76, alignment: .trailing)
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(AppTheme.ColorToken.secondaryText)
        .padding(.horizontal, 12)
        .frame(height: 38)
    }

    private var emptyRules: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.system(size: 24))
                .foregroundStyle(AppTheme.ColorToken.secondaryText)
            Text("暂无规则")
                .font(.system(size: 14, weight: .medium))
            Text("新增手动规则，或等待自动学习生成候选。")
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.ColorToken.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
    }

    private var safetyPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("安全开关", systemImage: "shield")
                .font(.system(size: 18, weight: .semibold))
            switchRow("启用易错词修正", isOn: enabledBinding)
            switchRow("自动学习候选词", isOn: autoLearningBinding)
            switchRow("自动学习直接生效", isOn: autoLearningAppliesImmediatelyBinding)
            switchRow("Shadow Mode", subtitle: "只记录结果，不修改输入", isOn: shadowModeBinding)
        }
        .padding(AppTheme.Spacing.card)
        .appPanel()
    }

    private var candidatesPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("学习候选", systemImage: "cube.transparent")
                .font(.system(size: 18, weight: .semibold))
            if viewModel.candidateRules.isEmpty {
                Text("暂无候选。关闭“直接生效”后，自动学习会进入这里。")
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
            } else {
                ForEach(viewModel.candidateRules.prefix(4)) { rule in
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(rule.original)  →  \(rule.replacement)")
                            .font(.system(size: 13, weight: .semibold))
                        Text("\(viewModel.scopeTitle(for: rule)) · 第 \(max(1, rule.observedCount)) 次观察")
                            .font(.system(size: 12))
                            .foregroundStyle(AppTheme.ColorToken.secondaryText)
                        HStack {
                            Button("忽略") { viewModel.ignoreCandidate(rule) }
                            Button("确认") { viewModel.acceptCandidate(rule) }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(10)
                    .appControlSurface(cornerRadius: AppTheme.Radius.row)
                }
            }
        }
        .padding(AppTheme.Spacing.card)
        .appPanel()
    }

    private var recentLearningPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("最近修正", systemImage: "clock")
                    .font(.system(size: 18, weight: .semibold))
                Spacer()
                Button {
                    viewModel.undoRecentLearning()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .help("撤销最近自动学习")
                .buttonStyle(.borderless)
            }
            if viewModel.recentLearningEvents.isEmpty {
                Text("暂无自动学习事件。")
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
            } else {
                ForEach(viewModel.recentLearningEvents) { event in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(AppTheme.ColorToken.accent)
                            .frame(width: 5, height: 5)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.title)
                                .font(.system(size: 13, weight: .medium))
                            Text(event.detail)
                                .font(.system(size: 12))
                                .foregroundStyle(AppTheme.ColorToken.secondaryText)
                        }
                        Spacer()
                    }
                }
            }
        }
        .padding(AppTheme.Spacing.card)
        .appPanel()
    }

    private func statCard(
        title: String,
        value: String,
        subtitle: String? = nil,
        systemImage: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppTheme.ColorToken.secondaryText)
            Text(value)
                .font(.system(size: 28, weight: .semibold))
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppTheme.Spacing.card)
        .appPanel()
    }

    private func toggleCard(
        title: String,
        value: String,
        systemImage: String,
        isOn: Binding<Bool>
    ) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 12) {
                Label(title, systemImage: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
                Text(value)
                    .font(.system(size: 28, weight: .semibold))
            }
            Spacer()
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .labelsHidden()
        }
        .padding(AppTheme.Spacing.card)
        .appPanel()
    }

    private func switchRow(
        _ title: String,
        subtitle: String? = nil,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.ColorToken.secondaryText)
                }
            }
            Spacer()
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .labelsHidden()
        }
    }

    private func badge(_ text: String, tint: Color = AppTheme.ColorToken.accent) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(tint.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { viewModel.isEnabled },
            set: { viewModel.setEnabled($0) }
        )
    }

    private var autoLearningBinding: Binding<Bool> {
        Binding(
            get: { viewModel.autoLearningEnabled },
            set: { viewModel.setAutoLearningEnabled($0) }
        )
    }

    private var autoLearningAppliesImmediatelyBinding: Binding<Bool> {
        Binding(
            get: { viewModel.autoLearningAppliesImmediately },
            set: { viewModel.setAutoLearningAppliesImmediately($0) }
        )
    }

    private var shadowModeBinding: Binding<Bool> {
        Binding(
            get: { viewModel.shadowMode },
            set: { viewModel.setShadowMode($0) }
        )
    }

    private var deleteAlertBinding: Binding<Bool> {
        Binding(
            get: { pendingDeleteRule != nil },
            set: { newValue in
                if !newValue {
                    pendingDeleteRule = nil
                }
            }
        )
    }
}

private struct VoiceCorrectionRuleRowView: View {
    let rule: CorrectionRule
    @ObservedObject var viewModel: VoiceCorrectionViewModel
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Text(rule.original)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("→  \(rule.replacement)")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(viewModel.scopeTitle(for: rule))
                .frame(width: 110, alignment: .leading)
            Text(viewModel.matchPolicyTitle(rule.matchPolicy))
                .frame(width: 80, alignment: .leading)
            HStack(spacing: 6) {
                Circle()
                    .fill(statusTint)
                    .frame(width: 6, height: 6)
                Text(viewModel.lifecycleTitle(rule.lifecycle))
            }
            .frame(width: 76, alignment: .leading)
            Text("\(rule.appliedCount) 次")
                .frame(width: 70, alignment: .leading)
            HStack(spacing: 8) {
                if rule.source == .automaticLearning {
                    Text("新")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(AppTheme.ColorToken.accent)
                }
                Menu {
                    Button("编辑规则", systemImage: "pencil", action: onEdit)
                    Button("暂停规则", systemImage: "pause.circle") {
                        viewModel.disableRule(rule)
                    }
                    if rule.lifecycle == .candidate {
                        Button("确认加入", systemImage: "checkmark.circle") {
                            viewModel.acceptCandidate(rule)
                        }
                        Button("忽略候选", systemImage: "xmark.circle") {
                            viewModel.ignoreCandidate(rule)
                        }
                    }
                    Divider()
                    Button("删除规则", systemImage: "trash", role: .destructive, action: onDelete)
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 28, height: 24)
                }
                .menuStyle(.borderlessButton)
            }
            .frame(width: 76, alignment: .trailing)
        }
        .font(.system(size: 13))
        .foregroundStyle(rule.isEnabled ? AppTheme.ColorToken.primaryText : AppTheme.ColorToken.secondaryText)
        .padding(.horizontal, 12)
        .frame(height: 48)
    }

    private var statusTint: Color {
        if !rule.isEnabled {
            return AppTheme.ColorToken.secondaryText
        }
        switch rule.lifecycle {
        case .active:
            return AppTheme.ColorToken.accent
        case .candidate:
            return .orange
        case .suspended, .retired:
            return AppTheme.ColorToken.secondaryText
        }
    }
}

private struct VoiceCorrectionRuleEditor: View {
    @Binding var draft: VoiceCorrectionRuleDraft
    let viewModel: VoiceCorrectionViewModel
    let onCancel: () -> Void
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text(draft.id == nil ? "新增易错词规则" : "编辑易错词规则")
                .font(.system(size: 20, weight: .semibold))

            VStack(alignment: .leading, spacing: 14) {
                labeledTextField("原始识别", text: $draft.original)
                labeledTextField("修正为", text: $draft.replacement)

                HStack(spacing: 12) {
                    Text("作用范围")
                        .frame(width: 90, alignment: .leading)
                    Picker("", selection: $draft.scope) {
                        ForEach(VoiceCorrectionScopeDraft.allCases) { scope in
                            Text(scope.title).tag(scope)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                HStack(spacing: 12) {
                    Text("匹配方式")
                        .frame(width: 90, alignment: .leading)
                    Picker("", selection: $draft.matchPolicy) {
                        ForEach(MatchPolicy.allCases, id: \.self) { policy in
                            Text(viewModel.matchPolicyTitle(policy)).tag(policy)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Toggle("启用后立即生效", isOn: $draft.isEnabled)
                    .toggleStyle(.switch)

                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Text("自动学习不会创建全局规则；高歧义短词需限定应用。")
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.ColorToken.secondaryText)
                }
            }

            HStack {
                Spacer()
                Button("取消", action: onCancel)
                Button("保存规则", action: onSave)
                    .buttonStyle(.borderedProminent)
                    .disabled(draft.original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                              draft.replacement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(28)
        .frame(width: 520)
        .background(AppTheme.ColorToken.pageBackground)
    }

    private func labeledTextField(
        _ title: String,
        text: Binding<String>
    ) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .frame(width: 90, alignment: .leading)
            TextField(title, text: text)
                .textFieldStyle(.roundedBorder)
        }
    }
}
