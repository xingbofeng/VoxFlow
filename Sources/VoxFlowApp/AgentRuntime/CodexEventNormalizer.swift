import Foundation

struct CodexRuntimeRawEvent: Equatable, Sendable {
    let method: String
    let params: [String: String]
}

struct CodexEventNormalizer: Sendable {
    private let now: @Sendable () -> Date

    init(now: @escaping @Sendable () -> Date = Date.init) {
        self.now = now
    }

    func normalize(_ event: CodexRuntimeRawEvent, startedAt: Date) -> AgentActionEvent? {
        let timestamp = now()
        let elapsedMS = max(0, Int(timestamp.timeIntervalSince(startedAt) * 1_000))
        switch event.method {
        case "turn/started", "turn.started", "thread.started":
            return AgentActionEvent(
                kind: .turnStarted,
                title: "开始处理",
                detail: "收到语音指令，开始任务规划",
                timestamp: timestamp,
                elapsedMS: elapsedMS
            )
        case "item/started":
            guard event.params["type"] == "commandExecution" else { return nil }
            return AgentActionEvent(
                kind: .toolRequested,
                title: "调用工具 shell",
                detail: event.params["command"],
                timestamp: timestamp,
                elapsedMS: elapsedMS,
                toolName: "shell"
            )
        case "item/agentMessage/delta", "item.completed", "item/completed":
            if event.params["type"] == "commandExecution" {
                let succeeded = event.params["status"] == "completed"
                return AgentActionEvent(
                    kind: succeeded ? .toolResolved : .error,
                    title: succeeded ? "工具完成" : "工具失败",
                    detail: event.params["aggregatedOutput"] ?? event.params["command"],
                    timestamp: timestamp,
                    elapsedMS: elapsedMS,
                    toolName: "shell",
                    isFailure: !succeeded
                )
            }
            if event.params["type"] == "error" {
                return AgentActionEvent(
                    kind: .warning,
                    title: "Codex 运行提示",
                    detail: event.params["message"],
                    timestamp: timestamp,
                    elapsedMS: elapsedMS
                )
            }
            return AgentActionEvent(
                kind: .modelDelta,
                title: "正在处理",
                detail: event.params["delta"] ?? event.params["text"] ?? event.params["message"],
                timestamp: timestamp,
                elapsedMS: elapsedMS
            )
        case "turn/plan/updated", "item/plan/delta":
            return AgentActionEvent(
                kind: .planUpdated,
                title: "更新计划",
                detail: event.params["delta"] ?? event.params["plan"],
                timestamp: timestamp,
                elapsedMS: elapsedMS
            )
        case "item/tool/call", "item/toolCall/started", "item/mcpToolCall/started":
            let tool = event.params["name"] ?? event.params["tool"] ?? "tool"
            return AgentActionEvent(
                kind: .toolRequested,
                title: "调用工具 \(tool)",
                detail: event.params["arguments"] ?? event.params["detail"],
                timestamp: timestamp,
                elapsedMS: elapsedMS,
                toolName: tool
            )
        case "item/permissions/requestApproval":
            return AgentActionEvent(
                kind: .toolRequested,
                title: "等待授权",
                detail: event.params["message"] ?? event.params["detail"],
                timestamp: timestamp,
                elapsedMS: elapsedMS,
                toolName: event.params["name"] ?? event.params["tool"]
            )
        case "item/mcpToolCall/progress":
            let tool = event.params["name"] ?? event.params["tool"]
            return AgentActionEvent(
                kind: .toolProgress,
                title: "工具执行中",
                detail: event.params["message"] ?? event.params["detail"],
                timestamp: timestamp,
                elapsedMS: elapsedMS,
                toolName: tool
            )
        case "serverRequest/resolved":
            let result = event.params["result"] ?? event.params["detail"] ?? ""
            if result.localizedCaseInsensitiveContains("denied") ||
                result.localizedCaseInsensitiveContains("declined") ||
                result.localizedCaseInsensitiveContains("拒绝") {
                return AgentActionEvent(
                    kind: .error,
                    title: "授权被拒绝",
                    detail: result,
                    timestamp: timestamp,
                    elapsedMS: elapsedMS,
                    toolName: event.params["name"] ?? event.params["tool"],
                    isFailure: true
                )
            }
            return AgentActionEvent(
                kind: .toolResolved,
                title: "工具完成",
                detail: result.isEmpty ? nil : result,
                timestamp: timestamp,
                elapsedMS: elapsedMS,
                toolName: event.params["name"] ?? event.params["tool"]
            )
        case "thread/tokenUsage/updated":
            return AgentActionEvent(
                kind: .tokenUsageUpdated,
                title: "更新用量",
                detail: event.params["summary"],
                timestamp: timestamp,
                elapsedMS: elapsedMS
            )
        case "turn/completed", "turn.completed":
            return AgentActionEvent(
                kind: .turnCompleted,
                title: "任务完成",
                detail: event.params["summary"],
                timestamp: timestamp,
                elapsedMS: elapsedMS
            )
        case "warning", "guardianWarning", "configWarning":
            return AgentActionEvent(
                kind: .warning,
                title: "处理提示",
                detail: event.params["message"] ?? event.params["detail"],
                timestamp: timestamp,
                elapsedMS: elapsedMS
            )
        case "error", "thread/realtime/error":
            if event.params["willRetry"] == "true" || event.params["willRetry"] == "1" {
                return AgentActionEvent(
                    kind: .warning,
                    title: "处理提示",
                    detail: event.params["message"] ?? event.params["error"],
                    timestamp: timestamp,
                    elapsedMS: elapsedMS
                )
            }
            return AgentActionEvent(
                kind: .error,
                title: "任务失败",
                detail: event.params["message"] ?? event.params["error"],
                timestamp: timestamp,
                elapsedMS: elapsedMS,
                isFailure: true
            )
        default:
            return nil
        }
    }

    func status(after event: AgentActionEvent) -> AgentActionStatus {
        if event.title == "等待授权" {
            return .waitingForPermission
        }
        switch event.kind {
        case .turnStarted, .modelDelta, .planUpdated:
            return .running
        case .toolRequested, .toolProgress, .toolResolved:
            return .running
        case .tokenUsageUpdated:
            return .running
        case .turnCompleted:
            return .completed
        case .warning:
            return .running
        case .error:
            return .failed
        }
    }

    func hudStage(after event: AgentActionEvent) -> AgentComposeHUDStage {
        if event.title == "等待授权" {
            return .runtimeWaitingForPermission(summary: hudSummary(after: event))
        }
        switch event.kind {
        case .toolRequested, .toolProgress, .toolResolved:
            return .runtimeOperating(summary: nil)
        case .error:
            return .runtimeFailed(summary: hudSummary(after: event))
        case .turnCompleted:
            return .runtimeCompleted(summary: hudSummary(after: event))
        case .modelDelta, .planUpdated, .tokenUsageUpdated, .warning:
            return .runtimeProcessing(summary: nil)
        case .turnStarted:
            return .runtimeProcessing(summary: nil)
        }
    }

    private func hudSummary(after event: AgentActionEvent) -> String? {
        let rawSummary = event.detail?.trimmingCharacters(in: .whitespacesAndNewlines)
        let summary = rawSummary?.isEmpty == false ? rawSummary : event.title
        guard summary?.looksLikeTechnicalPayload != true else {
            return nil
        }
        return summary?.truncatedForAgentRuntimeHUD()
    }
}

private extension String {
    var looksLikeTechnicalPayload: Bool {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("{") ||
            trimmed.hasPrefix("[") ||
            trimmed.hasPrefix("/") ||
            trimmed.hasPrefix("~") ||
            trimmed.hasPrefix("file://") ||
            trimmed.localizedCaseInsensitiveContains("/Users/") ||
            trimmed.localizedCaseInsensitiveContains("/Applications/") ||
            trimmed.localizedCaseInsensitiveContains("Application Support/") ||
            trimmed.localizedCaseInsensitiveContains("```") ||
            trimmed.localizedCaseInsensitiveContains("\"codexErrorInfo\"") ||
            trimmed.localizedCaseInsensitiveContains("\"message\"")
    }

    func truncatedForAgentRuntimeHUD(limit: Int = 96) -> String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return trimmed }
        let endIndex = trimmed.index(trimmed.startIndex, offsetBy: limit)
        return String(trimmed[..<endIndex]) + "..."
    }
}
