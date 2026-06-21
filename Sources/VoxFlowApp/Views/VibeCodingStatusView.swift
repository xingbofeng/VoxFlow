import SwiftUI

struct VibeCodingStatusView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var editingAgentID: String?
    @State private var draftAlias = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Vibe Coding")
                    .font(.system(size: 30, weight: .bold))

                currentAgentsCard
                recentDispatchCard
            }
            .padding(30)
            .frame(maxWidth: 1_080, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(AppTheme.ColorToken.pageBackground)
        .actionFeedbackOverlay(
            message: viewModel.lastActionMessage,
            error: viewModel.lastError,
            onDismiss: viewModel.clearFeedback
        )
        .task {
            await autoRefreshAgentSessions()
        }
    }

    private var currentAgentsCard: some View {
        VibeCodingStatusCard(
            title: "当前队员",
            subtitle: "自动读取 wrapper 注册的终端 Agent",
            systemImage: "person.3",
            tint: .blue
        ) {
            HStack(spacing: 10) {
                Button {
                    Task { await viewModel.refreshAgentSessions() }
                } label: {
                    Label("刷新队员", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)

                Button {
                    Task { await viewModel.cleanStaleAgentSessions() }
                } label: {
                    Label("清理失效队员", systemImage: "trash")
                }
                .buttonStyle(.bordered)
            }

            if viewModel.agentSessions.isEmpty {
                Text("当前没有已注册队员")
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
                    .settingsRow()
            } else {
                ForEach(viewModel.agentSessions) { agent in
                    agentRow(agent)
                }
            }
        }
    }

    private var recentDispatchCard: some View {
        VibeCodingStatusCard(
            title: "最近调度记录",
            subtitle: "默认保留发送指令和队员引用，不复制 Agent 输出",
            systemImage: "clock.arrow.circlepath",
            tint: .orange
        ) {
            HStack(alignment: .firstTextBaseline) {
                Text("语音指挥内容只保存在本地，可随时清空。")
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
                Spacer()
                if !viewModel.agentDispatchLogs.isEmpty {
                    Button("清空记录", role: .destructive) {
                        Task { await viewModel.clearAgentDispatchLogs() }
                    }
                    .buttonStyle(.bordered)
                }
            }
            .settingsRow()

            if viewModel.agentDispatchLogs.isEmpty {
                Text("暂无调度记录")
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
                    .settingsRow()
            } else {
                ForEach(viewModel.agentDispatchLogs.prefix(10)) { entry in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(entry.message)
                            .font(.system(size: 14, weight: .medium))
                            .lineLimit(2)
                        Text(entry.submitted ? "已提交" : "未提交")
                            .font(.system(size: 12))
                            .foregroundStyle(entry.submitted ? Color.green : Color.orange)
                    }
                    .settingsRow()
                }
            }
        }
    }

    private func agentRow(_ agent: AgentSessionCard) -> some View {
        HStack(spacing: 14) {
            VibeCodingStatusIcon(systemImage: "terminal", tint: .blue)
                .frame(width: 42, height: 42)
            VStack(alignment: .leading, spacing: 6) {
                aliasEditor(for: agent)
                Text([agent.cli, agent.repoName, agent.branch].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
                if let summary = agent.currentSelfSummary {
                    Text("\(summary.phase) · \(summary.summary)")
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.ColorToken.secondaryText)
                        .lineLimit(1)
                }
                if !agent.providerSessionRefs.isEmpty {
                    Text("已关联 \(agent.providerSessionRefs.count) 个会话/日志引用")
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.ColorToken.secondaryText)
                }
            }
            Spacer()
            Button {
                viewModel.copyAgentLaunchCommand(agent)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .help("复制启动命令")
            Text(agent.status.localizedTitle)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(agent.status.isDispatchable ? Color.green : Color.orange)
        }
        .settingsRow()
    }

    @ViewBuilder
    private func aliasEditor(for agent: AgentSessionCard) -> some View {
        if editingAgentID == agent.agentID {
            HStack(spacing: 8) {
                TextField("队员别名", text: $draftAlias)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 280)
                Button {
                    let alias = draftAlias
                    editingAgentID = nil
                    Task { await viewModel.setAgentAlias(alias, for: agent.agentID) }
                } label: {
                    Image(systemName: "checkmark")
                }
                .buttonStyle(.borderless)
                .help("确认修改")
                Button {
                    editingAgentID = nil
                    draftAlias = ""
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .help("取消修改")
            }
        } else {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.preferredAlias(for: agent.agentID) ?? agent.displayName)
                        .font(.system(size: 15, weight: .semibold))
                    if let alias = viewModel.preferredAlias(for: agent.agentID), alias != agent.displayName {
                        Text(agent.displayName)
                            .font(.system(size: 11))
                            .foregroundStyle(AppTheme.ColorToken.secondaryText)
                    }
                }
                Button {
                    startEditingAlias(for: agent)
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)
                .help("修改队员别名")
            }
        }
    }

    private func startEditingAlias(for agent: AgentSessionCard) {
        editingAgentID = agent.agentID
        draftAlias = viewModel.preferredAlias(for: agent.agentID) ?? ""
    }

    private func autoRefreshAgentSessions() async {
        await viewModel.refreshAgentSessions(reportFailures: false)
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled else { return }
            await viewModel.refreshAgentSessions(reportFailures: false)
        }
    }
}

private struct VibeCodingStatusCard<Content: View>: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    let content: Content

    init(
        title: String,
        subtitle: String,
        systemImage: String,
        tint: Color,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                VibeCodingStatusIcon(systemImage: systemImage, tint: tint)
                    .frame(width: 46, height: 46)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 18, weight: .semibold))
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.ColorToken.secondaryText)
                }
            }
            VStack(spacing: 10) {
                content
            }
        }
        .padding(20)
        .appPanel(cornerRadius: 14)
    }
}

private struct VibeCodingStatusIcon: View {
    let systemImage: String
    let tint: Color

    var body: some View {
        RoundedRectangle(cornerRadius: AppTheme.Radius.icon, style: .continuous)
            .fill(tint.opacity(0.09))
            .overlay {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(tint)
            }
    }
}
