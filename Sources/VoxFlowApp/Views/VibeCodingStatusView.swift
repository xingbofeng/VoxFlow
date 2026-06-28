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
                Text(L10n.localize("vibe.page.title", comment: "AI coding section title"))
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
            title: L10n.localize("vibe.current_agents.title", comment: "Current task agents section title"),
            subtitle: L10n.localize("vibe.current_agents.subtitle", comment: "Current task agents section subtitle"),
            systemImage: "person.3",
            tint: .blue
        ) {
            HStack(spacing: 10) {
                Button {
                    Task { await viewModel.refreshAgentSessions() }
                } label: {
                    Label(L10n.localize("vibe.current_agents.refresh", comment: "Refresh task agents button"), systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)

                Button {
                    Task { await viewModel.cleanStaleAgentSessions() }
                } label: {
                    Label(L10n.localize("vibe.current_agents.clean_stale", comment: "Clean stale task agents button"), systemImage: "trash")
                }
                .buttonStyle(.bordered)
            }

            if viewModel.currentAgentSessions.isEmpty {
                Text(L10n.localize("vibe.current_agents.empty", comment: "No task agents"))
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
                    .settingsRow()
            } else {
                ForEach(viewModel.currentAgentSessions) { agent in
                    agentRow(agent)
                }
            }

            if !viewModel.inactiveAgentSessions.isEmpty {
                Text(String(format: L10n.localize("vibe.current_agents.inactive_count_format", comment: "Hidden inactive sessions notice"), viewModel.inactiveAgentSessions.count))
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
                    .settingsRow()
            }
        }
    }

    private var recentDispatchCard: some View {
        VibeCodingStatusCard(
            title: L10n.localize("vibe.recent_dispatches.title", comment: "Recent dispatch records title"),
            subtitle: L10n.localize("vibe.recent_dispatches.subtitle", comment: "Recent dispatch records subtitle"),
            systemImage: "clock.arrow.circlepath",
            tint: .orange
        ) {
            HStack(alignment: .firstTextBaseline) {
                Text(L10n.localize("vibe.recent_dispatches.local_notice", comment: "Local speech content storage notice"))
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
                Spacer()
                if !viewModel.agentDispatchLogs.isEmpty {
                    Button(L10n.localize("vibe.recent_dispatches.clear", comment: "Clear dispatch records"), role: .destructive) {
                        Task { await viewModel.clearAgentDispatchLogs() }
                    }
                    .buttonStyle(.bordered)
                }
            }
            .settingsRow()

            if viewModel.agentDispatchLogs.isEmpty {
                Text(L10n.localize("vibe.recent_dispatches.empty", comment: "No recent records"))
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.ColorToken.secondaryText)
                    .settingsRow()
            } else {
                ForEach(viewModel.agentDispatchLogs.prefix(10)) { entry in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(entry.message)
                            .font(.system(size: 14, weight: .medium))
                            .lineLimit(2)
                        Text(entry.submitted ? L10n.localize("vibe.recent_dispatches.submitted", comment: "Dispatch log submitted status") : L10n.localize("vibe.recent_dispatches.not_submitted", comment: "Dispatch log not submitted status"))
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
                        .help(L10n.localize("vibe.agent.show_mcp_logs", comment: "Show MCP logs help"))
                }
                if let summary = agent.currentSelfSummary {
                    Text("\(summary.phase) · \(summary.summary)")
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.ColorToken.secondaryText)
                        .lineLimit(1)
                }
                if !agent.providerSessionRefs.isEmpty {
                    Text(String(format: L10n.localize("vibe.agent.associated_refs_format", comment: "Associated session logs count"), agent.providerSessionRefs.count))
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
                .help(L10n.localize("vibe.agent.copy_launch_command", comment: "Copy launch command help"))
            Button {
                Task { await viewModel.terminateAgentSession(agent) }
            } label: {
                Image(systemName: "stop.circle")
                    .foregroundStyle(agent.status.isDispatchable ? Color.red : AppTheme.ColorToken.secondaryText)
            }
            .buttonStyle(.borderless)
            .disabled(!agent.status.isDispatchable)
                .help(L10n.localize("vibe.agent.stop_process", comment: "Stop task agent process help"))
            Text(agent.status.localizedTitle)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(agent.status.isDispatchable ? Color.green : Color.orange)
        }
        .settingsRow()
    }

    private func mcpStatusText(for agent: AgentSessionCard) -> String {
        guard viewModel.agentDispatchMCPEnabled else {
            return L10n.localize("vibe.mcp.disabled", comment: "MCP channel disabled")
        }
        if let reportedAt = agent.mcpReportedAt {
            return String(format: L10n.localize("vibe.mcp.reported_with_time", comment: "MCP reported with relative time"), relativeTimeText(since: reportedAt))
        }
        if let seenAt = agent.mcpSeenAt {
            return String(format: L10n.localize("vibe.mcp.connected_with_time", comment: "MCP connected with relative time"), relativeTimeText(since: seenAt))
        }
        if agent.mcpInjected {
            return L10n.localize("vibe.mcp.connected_waiting", comment: "MCP connected but waiting")
        }
        return L10n.localize("vibe.mcp.disconnected", comment: "MCP not detected")
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
            return L10n.localize("vibe.mcp.help_disabled", comment: "MCP help for disabled state")
        }
        if let reportedAt = agent.mcpReportedAt {
            return String(format: L10n.localize("vibe.mcp.help_reported_format", comment: "MCP reported help text"), relativeTimeText(since: reportedAt))
        }
        if let seenAt = agent.mcpSeenAt {
            let request = agent.mcpLastRequest.map { String(format: L10n.localize("vibe.mcp.request_line", comment: "Recent request log line"), $0) } ?? ""
            return String(format: L10n.localize("vibe.mcp.help_connected_without_report", comment: "MCP connected no report help text"), relativeTimeText(since: seenAt), request)
        }
        if agent.mcpInjected {
            let config = agent.mcpConfigPath.map { String(format: L10n.localize("vibe.mcp.config_line", comment: "MCP config file line"), $0) } ?? ""
            return String(format: L10n.localize("vibe.mcp.help_injected_without_reading", comment: "MCP injected but not read help text"), config)
        }
        return L10n.localize("vibe.mcp.help_not_connected", comment: "MCP not connected help text")
    }

    private func relativeTimeText(since timestamp: TimeInterval) -> String {
        let seconds = max(0, Date().timeIntervalSince1970 - timestamp)
        if seconds < 60 {
            return L10n.localize("vibe.time.just_now", comment: "Relative time just now")
        }
        if seconds < 3_600 {
            return String(format: L10n.localize("vibe.time.minutes_ago", comment: "Relative minutes ago"), Int(seconds / 60))
        }
        if seconds < 86_400 {
            return String(format: L10n.localize("vibe.time.hours_ago", comment: "Relative hours ago"), Int(seconds / 3_600))
        }
        return String(format: L10n.localize("vibe.time.days_ago", comment: "Relative days ago"), Int(seconds / 86_400))
    }

    @ViewBuilder
    private func aliasEditor(for agent: AgentSessionCard) -> some View {
        if editingAgentID == agent.agentID {
            HStack(spacing: 8) {
                TextField(L10n.localize("vibe.alias.field_title", comment: "Task agent alias field title"), text: $draftAlias)
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
                    .help(L10n.localize("vibe.alias.confirm", comment: "Confirm alias edit"))
                Button {
                    editingAgentID = nil
                    draftAlias = ""
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                    .help(L10n.localize("vibe.alias.cancel", comment: "Cancel alias edit"))
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
                    .help(L10n.localize("vibe.alias.edit", comment: "Edit task agent alias"))
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
                Text(L10n.localize("vibe.mcp_log.title", comment: "MCP debug log title"))
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
                    .help(L10n.localize("vibe.mcp_log.close", comment: "Close debug log modal"))
            }

            VStack(alignment: .leading, spacing: 8) {
                MCPDebugField(label: L10n.localize("vibe.mcp_log.field_command", comment: "MCP command field"), value: agent.mcpCommand ?? "-")
                MCPDebugField(label: L10n.localize("vibe.mcp_log.field_args", comment: "MCP args field"), value: agent.mcpArgs.isEmpty ? "-" : agent.mcpArgs.joined(separator: " "))
                MCPDebugField(label: L10n.localize("vibe.mcp_log.field_config", comment: "MCP config path field"), value: agent.mcpConfigPath ?? "-")
                MCPDebugField(label: L10n.localize("vibe.mcp_log.field_log_path", comment: "MCP log path field"), value: agent.mcpLogPath ?? "-")
                MCPDebugField(label: L10n.localize("vibe.mcp_log.field_last_seen", comment: "MCP last seen field"), value: timestampText(agent.mcpSeenAt))
                MCPDebugField(label: L10n.localize("vibe.mcp_log.field_last_report", comment: "MCP last report field"), value: timestampText(agent.mcpReportedAt))
                MCPDebugField(label: L10n.localize("vibe.mcp_log.field_last_request", comment: "MCP last request field"), value: agent.mcpLastRequest ?? "-")
                MCPDebugField(label: L10n.localize("vibe.mcp_log.field_last_error", comment: "MCP last error field"), value: agent.mcpLastError ?? "-")
            }
            .padding(14)
            .background(AppTheme.ColorToken.controlBackground.opacity(0.72))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(L10n.localize("vibe.mcp_log.content_title", comment: "MCP log content title"))
                        .font(.system(size: 13, weight: .semibold))
                    if !logFileExists {
                        Text(L10n.localize("vibe.mcp_log.content_missing", comment: "MCP log file missing text"))
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
                        Label(L10n.localize("vibe.mcp_log.open_file", comment: "Open MCP log file"), systemImage: "doc")
                }
                .buttonStyle(.bordered)
                Button {
                    onCopy()
                } label: {
                        Label(L10n.localize("vibe.mcp_log.copy_diagnostics", comment: "Copy MCP diagnostics"), systemImage: "doc.on.doc")
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
