import Foundation
import SwiftUI

struct VibeCodingStatusView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var editingAgentID: String?
    @State private var draftAlias = ""
    @State private var mcpDebugAgent: AgentSessionCard?
    @State private var mcpDebugLogText = ""
    @State private var mcpDebugLogFileExists = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("AI 编程")
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
        .sheet(item: $mcpDebugAgent) { agent in
            MCPDebugLogModal(
                agent: agent,
                logText: mcpDebugLogText,
                logFileExists: mcpDebugLogFileExists,
                onCopy: {
                    viewModel.copyMCPDiagnostics(for: agent, logText: mcpDebugLogText)
                },
                onOpenLogFile: {
                    viewModel.openMCPLogFile(for: agent)
                },
                onClose: {
                    mcpDebugAgent = nil
                }
            )
            .frame(width: 760, height: 620)
        }
    }

    private var currentAgentsCard: some View {
        VibeCodingStatusCard(
            title: "当前任务助手",
            subtitle: "自动发现并读取已注册的任务助手",
            systemImage: "person.3",
            tint: .blue
        ) {
            HStack(spacing: 10) {
                Button {
                    Task { await viewModel.refreshAgentSessions() }
                } label: {
                    Label("刷新任务助手", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)

                Button {
                    Task { await viewModel.cleanStaleAgentSessions() }
                } label: {
                    Label("清理已退出/失效任务助手", systemImage: "trash")
                }
                .buttonStyle(.bordered)
            }

            if viewModel.currentAgentSessions.isEmpty {
                Text("当前没有可用任务助手")
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
                    .settingsRow()
            } else {
                ForEach(viewModel.currentAgentSessions) { agent in
                    agentRow(agent)
                }
            }

            if !viewModel.inactiveAgentSessions.isEmpty {
                Text("已隐藏 \(viewModel.inactiveAgentSessions.count) 个已退出或失效会话，不参与语音路由。")
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
                    .settingsRow()
            }
        }
    }

    private var recentDispatchCard: some View {
        VibeCodingStatusCard(
            title: "最近调度记录",
            subtitle: "默认保留发送指令与来源信息，不自动复制助手输出",
            systemImage: "clock.arrow.circlepath",
            tint: .orange
        ) {
            HStack(alignment: .firstTextBaseline) {
                Text("语音任务内容只保存在本地，可随时清空。")
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
                Text("暂未有最近记录")
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
                HStack(spacing: 6) {
                    Text(mcpStatusText(for: agent))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(mcpStatusColor(for: agent))
                        .help(mcpStatusHelp(for: agent))
                    Button {
                        presentMCPDebug(for: agent)
                    } label: {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.borderless)
                    .help("查看协作通道日志")
                }
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
            Button {
                Task { await viewModel.terminateAgentSession(agent) }
            } label: {
                Image(systemName: "stop.circle")
                    .foregroundStyle(agent.status.isDispatchable ? Color.red : AppTheme.ColorToken.secondaryText)
            }
            .buttonStyle(.borderless)
            .disabled(!agent.status.isDispatchable)
            .help("停止任务助手进程")
            Text(agent.status.localizedTitle)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(agent.status.isDispatchable ? Color.green : Color.orange)
        }
        .settingsRow()
    }

    private func mcpStatusText(for agent: AgentSessionCard) -> String {
        guard viewModel.agentDispatchMCPEnabled else {
            return "协作通道未开启"
        }
        if let reportedAt = agent.mcpReportedAt {
            return "协作通道已上报 · \(relativeTimeText(since: reportedAt))"
        }
        if let seenAt = agent.mcpSeenAt {
            return "协作通道已连接 · \(relativeTimeText(since: seenAt))"
        }
        if agent.mcpInjected {
            return "协作通道已接入，等待任务助手使用"
        }
        return "协作通道未检测到，建议重启任务助手"
    }

    private func mcpStatusColor(for agent: AgentSessionCard) -> Color {
        guard viewModel.agentDispatchMCPEnabled else {
            return AppTheme.ColorToken.secondaryText
        }
        if agent.mcpReportedAt != nil || agent.mcpSeenAt != nil {
            return .green
        }
        if agent.mcpInjected {
            return .orange
        }
        return .orange
    }

    private func mcpStatusHelp(for agent: AgentSessionCard) -> String {
        guard viewModel.agentDispatchMCPEnabled else {
            return "当前设置中未开启协作通道身份上报。"
        }
        if let reportedAt = agent.mcpReportedAt {
            return "任务助手已通过协作通道上报身份或工作状态，最近上报：\(relativeTimeText(since: reportedAt))。"
        }
        if let seenAt = agent.mcpSeenAt {
            let request = agent.mcpLastRequest.map { "\n最近请求：\($0)" } ?? ""
            return "任务助手已连接协作通道，但尚未上报状态。最近连接：\(relativeTimeText(since: seenAt))。\(request)"
        }
        if agent.mcpInjected {
            let config = agent.mcpConfigPath.map { "\n配置文件：\($0)" } ?? ""
            return "已为任务助手注入协作通道，但尚未检测到其读取。可在终端执行 /mcp 检查 voxflow 是否在线。\(config)"
        }
        return "当前会话没有检测到协作通道接入。若需查看状态，请重启对应任务助手。"
    }

    private func relativeTimeText(since timestamp: TimeInterval) -> String {
        let seconds = max(0, Date().timeIntervalSince1970 - timestamp)
        if seconds < 60 {
            return "刚刚"
        }
        if seconds < 3_600 {
            return "\(Int(seconds / 60)) 分钟前"
        }
        if seconds < 86_400 {
            return "\(Int(seconds / 3_600)) 小时前"
        }
        return "\(Int(seconds / 86_400)) 天前"
    }

    @ViewBuilder
    private func aliasEditor(for agent: AgentSessionCard) -> some View {
        if editingAgentID == agent.agentID {
            HStack(spacing: 8) {
                TextField("任务助手别名", text: $draftAlias)
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
                .help("修改任务助手别名")
            }
        }
    }

    private func startEditingAlias(for agent: AgentSessionCard) {
        editingAgentID = agent.agentID
        draftAlias = viewModel.preferredAlias(for: agent.agentID) ?? ""
    }

    private func presentMCPDebug(for agent: AgentSessionCard) {
        let snapshot = viewModel.mcpLogSnapshot(for: agent)
        mcpDebugLogText = snapshot.text
        mcpDebugLogFileExists = snapshot.fileExists
        mcpDebugAgent = agent
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

private struct MCPDebugLogModal: View {
    let agent: AgentSessionCard
    let logText: String
    let logFileExists: Bool
    let onCopy: () -> Void
    let onOpenLogFile: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                VibeCodingStatusIcon(systemImage: "doc.text.magnifyingglass", tint: .green)
                    .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 3) {
                    Text("协作通道日志")
                        .font(.system(size: 18, weight: .semibold))
                    Text(agent.displayName)
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.ColorToken.secondaryText)
                }
                Spacer()
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.borderless)
                .help("关闭")
            }

            VStack(alignment: .leading, spacing: 8) {
                MCPDebugField(label: "协作命令", value: agent.mcpCommand ?? "-")
                MCPDebugField(label: "参数", value: agent.mcpArgs.isEmpty ? "-" : agent.mcpArgs.joined(separator: " "))
                MCPDebugField(label: "配置路径", value: agent.mcpConfigPath ?? "-")
                MCPDebugField(label: "日志路径", value: agent.mcpLogPath ?? "-")
                MCPDebugField(label: "最近连接", value: timestampText(agent.mcpSeenAt))
                MCPDebugField(label: "上报时间", value: timestampText(agent.mcpReportedAt))
                MCPDebugField(label: "最近请求", value: agent.mcpLastRequest ?? "-")
                MCPDebugField(label: "最近错误", value: agent.mcpLastError ?? "-")
            }
            .padding(14)
            .background(AppTheme.ColorToken.controlBackground.opacity(0.72))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("日志内容")
                        .font(.system(size: 13, weight: .semibold))
                    if !logFileExists {
                        Text("日志文件暂未生成")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.orange)
                    }
                    Spacer()
                }
                ScrollView {
                    Text(logText)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(AppTheme.ColorToken.primaryText)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(12)
                }
                .background(Color.black.opacity(0.035))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(AppTheme.ColorToken.subtleStroke, lineWidth: AppTheme.Border.panelLineWidth)
                )
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .frame(maxHeight: .infinity)

            HStack {
                Spacer()
                Button {
                    onOpenLogFile()
                } label: {
                    Label("打开日志文件", systemImage: "doc")
                }
                .buttonStyle(.bordered)
                Button {
                    onCopy()
                } label: {
                    Label("复制诊断信息", systemImage: "doc.on.doc")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(22)
        .background(AppTheme.ColorToken.pageBackground)
    }

    private func timestampText(_ timestamp: TimeInterval?) -> String {
        guard let timestamp else { return "-" }
        return ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: timestamp))
    }
}

private struct MCPDebugField: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppTheme.ColorToken.secondaryText)
                .frame(width: 92, alignment: .leading)
            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(AppTheme.ColorToken.primaryText)
                .textSelection(.enabled)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
    }
}
