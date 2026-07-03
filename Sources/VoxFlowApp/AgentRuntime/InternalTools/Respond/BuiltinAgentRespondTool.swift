import Foundation

extension BuiltinAgentToolHost {
    func respond(_ call: BuiltinAgentToolCall) async -> BuiltinAgentToolResult {
        guard let text = requiredString("text", in: call) else {
            return .failure(toolName: call.name, code: "missing_text")
        }
        await environment.executor.notifyUser(text)
        return .success(toolName: call.name, result: ["kind": .string("responded")])
    }
}
