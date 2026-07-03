import Foundation

extension BuiltinAgentToolHost {
    func writeFile(_ call: BuiltinAgentToolCall) -> BuiltinAgentToolResult {
        guard let path = requiredString("file_path", "path", in: call) else {
            return .failure(toolName: call.name, code: "missing_path")
        }
        guard let content = requiredString("content", in: call) else {
            return .failure(toolName: call.name, code: "missing_content")
        }
        guard content.utf8.count <= Self.maxWritableFileBytes else {
            return .failure(toolName: call.name, code: "content_too_large")
        }
        let url = resolvedFileURL(path: path)
        if let failure = fileAccessFailure(toolName: call.name, path: path, url: url, requireWorkspaceForRelativePath: true) {
            return failure
        }
        do {
            let original = try existingTextForWrite(url: url)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try content.write(to: url, atomically: true, encoding: .utf8)
            readFileState[url.path] = BuiltinAgentReadFileState(
                content: content,
                modifiedAt: fileModificationTime(url),
                isFullRead: true
            )
            return .success(
                toolName: call.name,
                result: [
                    "path": .string(url.path),
                    "bytes": .int(content.utf8.count),
                    "kind": .string("file_written"),
                    "type": .string(original == nil ? "create" : "update"),
                    "originalFile": original.map(BuiltinAgentJSONValue.string) ?? .null
                ]
            )
        } catch let error as BuiltinAgentToolHostError {
            return .failure(toolName: call.name, code: error.code, message: error.message)
        } catch {
            return .failure(toolName: call.name, code: "write_failed", message: error.localizedDescription)
        }
    }
}
