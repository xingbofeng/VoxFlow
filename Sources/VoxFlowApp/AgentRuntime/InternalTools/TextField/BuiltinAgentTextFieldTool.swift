import Foundation

extension BuiltinAgentToolHost {
    func textField(_ call: BuiltinAgentToolCall) async -> BuiltinAgentToolResult {
        guard let action = requiredString("action", in: call) else {
            return .failure(toolName: call.name, code: "missing_action")
        }
        switch action {
        case "read_selection":
            return readSelectionOrInputText(toolName: call.name)
        case "read_all":
            guard let context = environment.context else {
                return .failure(toolName: call.name, code: "missing_context")
            }
            return .success(
                toolName: call.name,
                result: ["text": context.inputAreaText.map(BuiltinAgentJSONValue.string) ?? .null]
            )
        case "insert":
            guard let text = requiredString("text", in: call) else {
                return .failure(toolName: call.name, code: "missing_text")
            }
            let didPaste = await environment.executor.pasteAtCursor(text)
            return didPaste
                ? .success(toolName: call.name, result: ["kind": .string("inserted")])
                : .failure(toolName: call.name, code: "insert_failed")
        case "replace_selection":
            guard let text = requiredString("text", in: call) else {
                return .failure(toolName: call.name, code: "missing_text")
            }
            guard nonEmpty(environment.context?.selectedText) != nil else {
                return .failure(toolName: call.name, code: "missing_selection")
            }
            let didReplace = await environment.executor.replaceSelection(text)
            return didReplace
                ? .success(toolName: call.name, result: ["kind": .string("replaced")])
                : .failure(toolName: call.name, code: "replace_failed")
        default:
            return .failure(toolName: call.name, code: "unsupported_text_field_action")
        }
    }
}
