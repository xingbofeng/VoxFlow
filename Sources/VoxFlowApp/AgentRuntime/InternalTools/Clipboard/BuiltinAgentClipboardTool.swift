extension BuiltinAgentToolHost {
    func clipboard(_ call: BuiltinAgentToolCall) -> BuiltinAgentToolResult {
        guard let action = requiredString("action", in: call) else {
            return .failure(toolName: call.name, code: "missing_action")
        }
        switch action {
        case "read_text", "read", "get_text", "get":
            return .success(
                toolName: call.name,
                result: ["text": environment.clipboard.readText().map(BuiltinAgentJSONValue.string) ?? .null]
            )
        case "write_text", "write", "set_text", "set":
            guard let text = requiredString("text", in: call) else {
                return .failure(toolName: call.name, code: "missing_text")
            }
            environment.clipboard.writeText(text)
            return .success(toolName: call.name, result: ["kind": .string("clipboard_text_written")])
        default:
            return .failure(toolName: call.name, code: "unsupported_clipboard_action")
        }
    }
}
