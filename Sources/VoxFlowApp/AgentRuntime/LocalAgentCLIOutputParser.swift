import Foundation

func localAgentChildEnvironment(
    for descriptor: LocalAgentProviderDescriptor,
    base: [String: String] = ProcessInfo.processInfo.environment
) -> [String: String] {
    guard [
        AgentProviderRegistry.codebuddy.providerID,
        AgentProviderRegistry.pi.providerID
    ].contains(descriptor.providerID) else {
        return base
    }
    var environment = base
    for key in [
        "HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "NO_PROXY",
        "http_proxy", "https_proxy", "all_proxy", "no_proxy"
    ] {
        environment.removeValue(forKey: key)
    }
    return environment
}

struct LocalAgentCLIParsedOutput: Equatable, Sendable {
    let text: String
    let errorMessage: String?

    var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

enum LocalAgentCLIOutputParser {
    static func parse(_ output: String) -> LocalAgentCLIParsedOutput {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) else {
            let lineParsed = parseLineDelimitedJSON(trimmed)
            if !lineParsed.isEmpty || lineParsed.errorMessage != nil {
                return lineParsed
            }
            return LocalAgentCLIParsedOutput(text: trimmed, errorMessage: nil)
        }
        return parseJSONValue(json)
    }

    private static func parseLineDelimitedJSON(_ output: String) -> LocalAgentCLIParsedOutput {
        var incrementalTexts: [String] = []
        var errors: [String] = []
        var finalText: String?
        var parsedAnyLine = false
        for line in output.split(whereSeparator: \.isNewline) {
            let textLine = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let data = textLine.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) else {
                continue
            }
            parsedAnyLine = true
            let parsed = parseJSONValue(json)
            if let error = parsed.errorMessage, !error.isEmpty {
                errors.append(error)
                if finalEventText(from: json) == nil {
                    continue
                }
            }
            if !parsed.isEmpty {
                if let text = finalEventText(from: json) {
                    finalText = text
                } else if shouldUseIncrementalText(from: json) {
                    incrementalTexts.append(parsed.text)
                }
            }
        }
        guard parsedAnyLine else {
            return LocalAgentCLIParsedOutput(text: "", errorMessage: nil)
        }
        let text = finalText ?? incrementalTexts.joined()
        return LocalAgentCLIParsedOutput(
            text: text.isEmpty ? (errors.first ?? "") : text,
            errorMessage: text.isEmpty ? errors.first : nil
        )
    }

    private static func parseJSONValue(_ json: Any) -> LocalAgentCLIParsedOutput {
        let text = preferredTextValue(from: json).trimmingCharacters(in: .whitespacesAndNewlines)
        let error = errorMessage(from: json, fallback: text)
        return LocalAgentCLIParsedOutput(
            text: text.isEmpty ? (error ?? "") : text,
            errorMessage: error
        )
    }
}

private func shouldUseIncrementalText(from json: Any) -> Bool {
    guard let object = json as? [String: Any],
          let type = object["type"] as? String else {
        return false
    }
    if type == "text" || type == "result" {
        return true
    }
    if type == "message_update" {
        return true
    }
    if let role = object["role"] as? String {
        return role == "assistant"
    }
    if let message = object["message"] as? [String: Any],
       message["role"] as? String == "assistant" {
        return true
    }
    return false
}

private func errorMessage(from json: Any, fallback: String) -> String? {
    guard let object = json as? [String: Any] else { return nil }
    if let finalError = firstNonEmptyText(object["finalError"]) {
        return finalError
    }
    if object["is_error"] as? Bool == true {
        return firstNonEmptyText(
            object["error"],
            object["message"],
            object["result"],
            object["response"],
            object["content"]
        ) ?? (fallback.isEmpty ? "Local agent returned an error" : fallback)
    }
    if let type = object["type"] as? String,
       type.localizedCaseInsensitiveContains("error") {
        return firstNonEmptyText(object["error"], object["message"], object["result"]) ?? fallback
    }
    if let subtype = object["subtype"] as? String,
       subtype.localizedCaseInsensitiveContains("error") {
        return firstNonEmptyText(object["error"], object["message"], object["result"]) ?? fallback
    }
    if let stopReason = object["stopReason"] as? String,
       stopReason.localizedCaseInsensitiveContains("error") {
        return firstNonEmptyText(
            object["errorMessage"],
            object["error"],
            object["message"],
            object["result"]
        ) ?? (fallback.isEmpty ? "Local agent returned an error" : fallback)
    }
    if let message = object["message"],
       let nestedError = errorMessage(from: message, fallback: fallback) {
        return nestedError
    }
    if let messages = object["messages"] as? [Any] {
        for message in messages.reversed() {
            if let nestedError = errorMessage(from: message, fallback: fallback) {
                return nestedError
            }
        }
    }
    if let errorMessage = object["errorMessage"] as? String,
       !errorMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return errorMessage
    }
    return nil
}

private func firstNonEmptyText(_ values: Any?...) -> String? {
    for value in values {
        guard let value else { continue }
        let text = textValue(from: value).trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            return text
        }
    }
    return nil
}

private func textValue(from json: Any) -> String {
    if let string = json as? String {
        return string
    }
    if let array = json as? [Any] {
        return array.map(textValue(from:)).filter { !$0.isEmpty }.joined()
    }
    guard let object = json as? [String: Any] else { return "" }
    for key in ["text", "message", "content", "output", "result", "response", "summary"] {
        if let value = object[key] {
            let text = textValue(from: value)
            if !text.isEmpty {
                return text
            }
        }
    }
    return ""
}

private func preferredTextValue(from json: Any) -> String {
    if let array = json as? [Any] {
        if let finalResult = array.reversed().compactMap(finalResultText(from:)).first {
            return finalResult
        }
        return array.map(preferredTextValue(from:)).filter { !$0.isEmpty }.joined()
    }
    if let finalResult = finalResultText(from: json) {
        return finalResult
    }
    return textValue(from: json)
}

private func finalResultText(from json: Any) -> String? {
    guard let object = json as? [String: Any] else { return nil }
    if let text = finalEventText(from: json) {
        return text
    }
    if let messages = object["messages"] as? [Any],
       let text = messages.reversed().compactMap(assistantMessageText(from:)).first {
        return text
    }
    if object["type"] as? String == "result" {
        return firstNonEmptyText(object["result"], object["response"], object["output"], object["summary"])
    }
    if object["type"] as? String == "text",
       let part = object["part"] as? [String: Any] {
        return firstNonEmptyText(part["text"])
    }
    if object["role"] as? String == "assistant" {
        return firstNonEmptyText(object["content"], object["text"], object["message"])
    }
    return nil
}

private func finalEventText(from json: Any) -> String? {
    guard let object = json as? [String: Any] else {
        return nil
    }
    if let messages = object["messages"] as? [Any],
       let text = messages.reversed().compactMap(assistantMessageText(from:)).first {
        return text
    }
    guard let type = object["type"] as? String else {
        return nil
    }
    switch type {
    case "agent_end":
        if let messages = object["messages"] as? [Any] {
            return messages.reversed().compactMap(assistantMessageText(from:)).first
        }
    case "turn_end", "message_end":
        if let message = object["message"] {
            return assistantMessageText(from: message)
        }
    case "message_update":
        if let event = object["assistantMessageEvent"] as? [String: Any],
           event["type"] as? String == "text_end" {
            return firstNonEmptyText(event["content"])
        }
    default:
        break
    }
    return nil
}

private func assistantMessageText(from json: Any) -> String? {
    guard let object = json as? [String: Any],
          object["role"] as? String == "assistant" else {
        return nil
    }
    return firstNonEmptyText(object["content"], object["text"], object["message"])
}
