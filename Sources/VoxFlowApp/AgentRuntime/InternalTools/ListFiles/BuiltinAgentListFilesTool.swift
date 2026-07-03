import Foundation

extension BuiltinAgentToolHost {
    func listFiles(_ call: BuiltinAgentToolCall) -> BuiltinAgentToolResult {
        guard let path = requiredString("path", in: call) else {
            return .success(
                toolName: call.name,
                result: [
                    "kind": .string("roots"),
                    "entries": .array([
                        .string("~/Library/Application Support/VoxFlow")
                    ])
                ]
            )
        }
        let url = resolvedFileURL(path: path)
        if let failure = fileAccessFailure(toolName: call.name, path: path, url: url, requireWorkspaceForRelativePath: false) {
            return failure
        }
        do {
            let names = try FileManager.default.contentsOfDirectory(atPath: url.path)
                .sorted()
                .prefix(100)
                .map(BuiltinAgentJSONValue.string)
            return .success(toolName: call.name, result: ["entries": .array(Array(names))])
        } catch {
            return .failure(toolName: call.name, code: "list_failed", message: error.localizedDescription)
        }
    }
}
