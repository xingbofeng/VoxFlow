import Foundation

extension BuiltinAgentToolHost {
    func globFiles(_ call: BuiltinAgentToolCall) -> BuiltinAgentToolResult {
        guard let pattern = requiredString("pattern", in: call) else {
            return .failure(toolName: call.name, code: "missing_pattern")
        }
        let path = call.arguments["path"]?.stringValue
        let root = resolvedFileURL(path: path ?? ".")
        if let path,
           let failure = fileAccessFailure(
            toolName: call.name,
            path: path,
            url: root,
            requireWorkspaceForRelativePath: true
           ) {
            return failure
        }

        let start = Date()
        do {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory) else {
                return .failure(toolName: call.name, code: "directory_not_found")
            }
            guard isDirectory.boolValue else {
                return .failure(toolName: call.name, code: "path_not_directory")
            }

            let matches = try BuiltinAgentFileSearchSupport.regularFiles(under: root)
                .filter { BuiltinAgentFileSearchSupport.matchesGlob($0.relativePath, pattern: pattern) }
            let limit = min(max(optionalInt("limit", in: call) ?? 100, 1), 500)
            let visible = matches.prefix(limit)
            return .success(
                toolName: call.name,
                result: [
                    "durationMs": .int(Int(Date().timeIntervalSince(start) * 1_000)),
                    "numFiles": .int(matches.count),
                    "filenames": .array(visible.map { .string($0.relativePath) }),
                    "truncated": .bool(matches.count > visible.count)
                ]
            )
        } catch {
            return .failure(toolName: call.name, code: "glob_failed", message: error.localizedDescription)
        }
    }
}
