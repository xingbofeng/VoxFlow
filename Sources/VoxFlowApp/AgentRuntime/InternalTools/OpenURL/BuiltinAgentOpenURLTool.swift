import Foundation

extension BuiltinAgentToolHost {
    func openURL(_ call: BuiltinAgentToolCall) async -> BuiltinAgentToolResult {
        guard let urlString = requiredString("url", in: call),
              let url = URL(string: urlString),
              ["http", "https"].contains(url.scheme?.lowercased()) else {
            return .failure(toolName: call.name, code: "invalid_url")
        }
        guard Self.userExplicitlyAskedToOpen(url: url, instruction: environment.userInstruction) else {
            return .failure(toolName: call.name, code: "missing_explicit_user_intent")
        }
        let didOpen = await environment.executor.openURL(url)
        return didOpen
            ? .success(toolName: call.name, result: ["kind": .string("opened")])
            : .failure(toolName: call.name, code: "open_url_failed")
    }
}
