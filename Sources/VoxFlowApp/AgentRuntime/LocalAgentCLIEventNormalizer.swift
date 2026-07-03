import Foundation

struct LocalAgentCLIEventNormalizer: Sendable {
    private let providerName: String
    private let now: @Sendable () -> Date

    init(
        providerName: String,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.providerName = providerName
        self.now = now
    }

    func normalize(stdout: String, stderr: String, startedAt: Date) -> [AgentActionEvent] {
        var events = jsonEvents(from: stdout, startedAt: startedAt)
        let stderrEvents = stderr
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map {
                AgentActionEvent(
                    kind: .warning,
                    title: "\(providerName) 运行提示",
                    detail: $0,
                    timestamp: now(),
                    elapsedMS: elapsedMilliseconds(since: startedAt)
                )
            }
        events.append(contentsOf: stderrEvents)
        return events
    }

    private func jsonEvents(from stdout: String, startedAt: Date) -> [AgentActionEvent] {
        let trimmed = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        if let json = decodeJSON(trimmed) {
            return events(from: json, startedAt: startedAt)
        }
        return trimmed
            .split(whereSeparator: \.isNewline)
            .compactMap { decodeJSON(String($0).trimmingCharacters(in: .whitespacesAndNewlines)) }
            .flatMap { events(from: $0, startedAt: startedAt) }
    }

    private func events(from json: Any, startedAt: Date) -> [AgentActionEvent] {
        if let array = json as? [Any] {
            return array.flatMap { events(from: $0, startedAt: startedAt) }
        }
        guard let object = json as? [String: Any],
              let event = event(from: object, startedAt: startedAt) else {
            return []
        }
        return [event]
    }

    private func event(from object: [String: Any], startedAt: Date) -> AgentActionEvent? {
        let type = stringValue(object["type"])
        let timestamp = now()
        let elapsed = elapsedMilliseconds(since: startedAt)

        if let error = errorText(from: object) {
            let isFinalRetryFailure = type == "auto_retry_end" || stringValue(object["willRetry"]) == "false"
            return AgentActionEvent(
                kind: isFinalRetryFailure ? .error : .warning,
                title: isFinalRetryFailure ? "\(providerName) 执行失败" : "\(providerName) 运行提示",
                detail: error,
                timestamp: timestamp,
                elapsedMS: elapsed,
                isFailure: isFinalRetryFailure
            )
        }

        switch type {
        case "session":
            return AgentActionEvent(
                kind: .toolProgress,
                title: "\(providerName) 会话已创建",
                detail: firstNonEmptyString(object["cwd"], object["id"]),
                timestamp: timestamp,
                elapsedMS: elapsed
            )
        case "agent_start", "turn_start", "step_start":
            return AgentActionEvent(
                kind: .toolProgress,
                title: "\(providerName) 正在执行",
                detail: readableDetail(from: object),
                timestamp: timestamp,
                elapsedMS: elapsed
            )
        case "auto_retry_start":
            return AgentActionEvent(
                kind: .warning,
                title: "\(providerName) 正在重试",
                detail: firstNonEmptyString(object["errorMessage"], object["message"]),
                timestamp: timestamp,
                elapsedMS: elapsed
            )
        case "text", "message_update":
            guard let detail = readableDetail(from: object) else { return nil }
            return AgentActionEvent(
                kind: .modelDelta,
                title: "\(providerName) 输出",
                detail: detail,
                timestamp: timestamp,
                elapsedMS: elapsed
            )
        case "message_start", "message_end", "turn_end":
            guard messageRole(from: object) == "assistant",
                  let detail = readableDetail(from: object) else {
                return nil
            }
            return AgentActionEvent(
                kind: .modelDelta,
                title: "\(providerName) 输出",
                detail: detail,
                timestamp: timestamp,
                elapsedMS: elapsed
            )
        case "tool_call", "tool_use", "tool_start":
            let tool = firstNonEmptyString(object["name"], object["tool"]) ?? "tool"
            return AgentActionEvent(
                kind: .toolRequested,
                title: "\(providerName) 调用工具 \(tool)",
                detail: readableDetail(from: object),
                timestamp: timestamp,
                elapsedMS: elapsed,
                toolName: tool
            )
        case "tool_result", "tool_end", "step_finish":
            return AgentActionEvent(
                kind: .toolResolved,
                title: "\(providerName) 工具完成",
                detail: readableDetail(from: object),
                timestamp: timestamp,
                elapsedMS: elapsed,
                toolName: firstNonEmptyString(object["name"], object["tool"])
            )
        case "result", "agent_end":
            guard let detail = readableDetail(from: object) else { return nil }
            return AgentActionEvent(
                kind: .modelDelta,
                title: "\(providerName) 结果",
                detail: detail,
                timestamp: timestamp,
                elapsedMS: elapsed
            )
        default:
            if let detail = readableDetail(from: object) {
                return AgentActionEvent(
                    kind: .toolProgress,
                    title: "\(providerName) 事件",
                    detail: detail,
                    timestamp: timestamp,
                    elapsedMS: elapsed
                )
            }
            return nil
        }
    }

    private func readableDetail(from object: [String: Any]) -> String? {
        firstNonEmptyString(
            object["summary"],
            object["result"],
            object["response"],
            object["output"],
            object["text"],
            object["message"],
            object["content"],
            object["part"],
            object["assistantMessageEvent"],
            object["toolResults"]
        )
        .flatMap(trimmedNonEmpty)
        .flatMap { detail in
            guard !detail.looksLikePromptEcho else { return nil }
            return detail.truncatedForLocalAgentLog()
        }
    }

    private func messageRole(from object: [String: Any]) -> String? {
        if let role = object["role"] as? String {
            return role
        }
        if let message = object["message"] as? [String: Any] {
            return message["role"] as? String
        }
        return nil
    }

    private func errorText(from object: [String: Any]) -> String? {
        if stringValue(object["stopReason"]).localizedCaseInsensitiveContains("error") {
            return firstNonEmptyString(object["errorMessage"], object["error"], object["message"], object["result"])
        }
        if let message = object["message"] as? [String: Any],
           stringValue(message["stopReason"]).localizedCaseInsensitiveContains("error") {
            return firstNonEmptyString(message["errorMessage"], message["error"], message["message"], message["result"])
        }
        if let messages = object["messages"] as? [Any] {
            for case let message as [String: Any] in messages.reversed() {
                if let error = errorText(from: message) {
                    return error
                }
            }
        }
        if (object["success"] as? Bool) == false {
            return firstNonEmptyString(object["finalError"], object["errorMessage"], object["error"], object["message"])
        }
        return nil
    }

    private func elapsedMilliseconds(since startedAt: Date) -> Int {
        max(0, Int(now().timeIntervalSince(startedAt) * 1_000))
    }
}

private func decodeJSON(_ text: String) -> Any? {
    guard let data = text.data(using: .utf8) else { return nil }
    return try? JSONSerialization.jsonObject(with: data)
}

private func firstNonEmptyString(_ values: Any?...) -> String? {
    for value in values {
        guard let text = localAgentEventStringValue(value).flatMap(trimmedNonEmpty) else {
            continue
        }
        return text
    }
    return nil
}

private func localAgentEventStringValue(_ value: Any?) -> String? {
    guard let value else { return nil }
    if let string = value as? String {
        return string
    }
    if let number = value as? NSNumber {
        return number.stringValue
    }
    if let array = value as? [Any] {
        return array.compactMap(localAgentEventStringValue).joined(separator: "\n")
    }
    if let object = value as? [String: Any] {
        for key in ["text", "message", "content", "output", "result", "response", "summary", "delta"] {
            if let text = localAgentEventStringValue(object[key]).flatMap(trimmedNonEmpty) {
                return text
            }
        }
        if let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
           let text = String(data: data, encoding: .utf8) {
            return text
        }
    }
    return nil
}

private func stringValue(_ value: Any?) -> String {
    localAgentEventStringValue(value) ?? ""
}

private func trimmedNonEmpty(_ text: String) -> String? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

private extension String {
    var looksLikePromptEcho: Bool {
        contains("你是 VoxFlow 触发的本机") ||
            contains("用户语音指令：") ||
            count > 2_000
    }

    func truncatedForLocalAgentLog(limit: Int = 1_200) -> String {
        guard count > limit else { return self }
        let endIndex = index(startIndex, offsetBy: limit)
        return String(self[..<endIndex]) + "\n..."
    }
}
