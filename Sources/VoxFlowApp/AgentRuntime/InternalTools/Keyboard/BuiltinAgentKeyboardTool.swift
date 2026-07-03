import Foundation

extension BuiltinAgentToolHost {
    func keyboard(_ call: BuiltinAgentToolCall) async -> BuiltinAgentToolResult {
        guard let action = requiredString("action", in: call) else {
            return .failure(toolName: call.name, code: "missing_action")
        }
        let text = call.arguments["text"]?.stringValue
        let key = call.arguments["key"]?.stringValue
        let keys = stringArray("keys", in: call)
        guard !keys.contains(where: isSubmitKey) && key.map(isSubmitKey) != true else {
            return .failure(toolName: call.name, code: "submit_key_not_allowed")
        }
        let ok = await environment.executor.simulateKeyboard(
            action: action,
            text: text,
            key: key,
            keys: keys
        )
        return ok
            ? .success(toolName: call.name, result: ["kind": .string("keyboard_simulated")])
            : .failure(toolName: call.name, code: "keyboard_failed")
    }
}
