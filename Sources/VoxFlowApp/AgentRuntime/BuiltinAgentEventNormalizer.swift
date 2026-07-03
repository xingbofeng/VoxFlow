import Foundation

enum BuiltinAgentRuntimeEvent: Decodable, Equatable, Sendable {
    case runStarted
    case turnStarted(step: Int?)
    case modelDelta(text: String)
    case toolRequested(toolCall: BuiltinAgentToolCall)
    case toolResolved(toolName: String, result: BuiltinAgentToolResult?)
    case tokenUsageUpdated(summary: String?)
    case turnCompleted(summary: String?)
    case warning(message: String?)
    case error(reason: String)

    private enum CodingKeys: String, CodingKey {
        case event
        case step
        case text
        case toolCall
        case toolName
        case result
        case summary
        case message
        case reason
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let event = try container.decode(String.self, forKey: .event)
        switch event {
        case "runStarted":
            self = .runStarted
        case "turnStarted":
            self = .turnStarted(step: try container.decodeIfPresent(Int.self, forKey: .step))
        case "modelDelta":
            self = .modelDelta(text: try container.decodeIfPresent(String.self, forKey: .text) ?? "")
        case "toolRequested":
            self = .toolRequested(toolCall: try container.decode(BuiltinAgentToolCall.self, forKey: .toolCall))
        case "toolResolved":
            self = .toolResolved(
                toolName: try container.decodeIfPresent(String.self, forKey: .toolName) ?? "tool",
                result: try container.decodeIfPresent(BuiltinAgentToolResult.self, forKey: .result)
            )
        case "tokenUsageUpdated":
            self = .tokenUsageUpdated(summary: try container.decodeIfPresent(String.self, forKey: .summary))
        case "turnCompleted":
            self = .turnCompleted(summary: try container.decodeIfPresent(String.self, forKey: .summary))
        case "warning":
            self = .warning(message: try container.decodeIfPresent(String.self, forKey: .message))
        case "error":
            self = .error(reason: try container.decodeIfPresent(String.self, forKey: .reason) ?? "builtin_agent_error")
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .event,
                in: container,
                debugDescription: "Unknown builtin agent event: \(event)"
            )
        }
    }
}

struct BuiltinAgentEventNormalizer: Sendable {
    private let now: @Sendable () -> Date

    init(now: @escaping @Sendable () -> Date = Date.init) {
        self.now = now
    }

    func normalize(_ event: BuiltinAgentRuntimeEvent, startedAt: Date) -> AgentActionEvent? {
        let timestamp = now()
        let elapsedMS = max(0, Int(timestamp.timeIntervalSince(startedAt) * 1_000))

        switch event {
        case .runStarted:
            return AgentActionEvent(
                kind: .turnStarted,
                title: "开始处理",
                detail: "内置 Agent 已启动",
                timestamp: timestamp,
                elapsedMS: elapsedMS
            )
        case let .turnStarted(step):
            return AgentActionEvent(
                kind: .turnStarted,
                title: "开始处理",
                detail: step.map { "第 \($0) 轮" },
                timestamp: timestamp,
                elapsedMS: elapsedMS
            )
        case let .modelDelta(text):
            return AgentActionEvent(
                kind: .modelDelta,
                title: "正在处理",
                detail: text.isEmpty ? nil : text,
                timestamp: timestamp,
                elapsedMS: elapsedMS
            )
        case let .toolRequested(toolCall):
            return AgentActionEvent(
                kind: .toolRequested,
                title: "调用工具 \(toolCall.name)",
                detail: argumentsSummary(toolCall.arguments),
                timestamp: timestamp,
                elapsedMS: elapsedMS,
                toolName: toolCall.name
            )
        case let .toolResolved(toolName, result):
            let failed = result?.ok == false
            return AgentActionEvent(
                kind: failed ? .warning : .toolResolved,
                title: failed ? "工具未执行" : "工具完成",
                detail: result?.error?.code ?? result?.result?["kind"]?.stringValue,
                timestamp: timestamp,
                elapsedMS: elapsedMS,
                toolName: toolName,
                isFailure: false
            )
        case let .tokenUsageUpdated(summary):
            return AgentActionEvent(
                kind: .tokenUsageUpdated,
                title: "更新用量",
                detail: summary,
                timestamp: timestamp,
                elapsedMS: elapsedMS
            )
        case let .turnCompleted(summary):
            return AgentActionEvent(
                kind: .turnCompleted,
                title: "任务完成",
                detail: summary,
                timestamp: timestamp,
                elapsedMS: elapsedMS
            )
        case let .warning(message):
            return AgentActionEvent(
                kind: .warning,
                title: "处理提示",
                detail: message,
                timestamp: timestamp,
                elapsedMS: elapsedMS
            )
        case let .error(reason):
            return AgentActionEvent(
                kind: .error,
                title: "任务失败",
                detail: reason,
                timestamp: timestamp,
                elapsedMS: elapsedMS,
                isFailure: true
            )
        }
    }

    private func argumentsSummary(_ arguments: [String: BuiltinAgentJSONValue]) -> String? {
        if let text = arguments["text"]?.stringValue {
            return text.truncatedForBuiltinAgentHUD()
        }
        if let url = arguments["url"]?.stringValue {
            return url.truncatedForBuiltinAgentHUD()
        }
        if let message = arguments["message"]?.stringValue {
            return message.truncatedForBuiltinAgentHUD()
        }
        return nil
    }
}

private extension String {
    func truncatedForBuiltinAgentHUD(limit: Int = 96) -> String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return trimmed }
        let endIndex = trimmed.index(trimmed.startIndex, offsetBy: limit)
        return String(trimmed[..<endIndex]) + "..."
    }
}
