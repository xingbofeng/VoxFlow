import Foundation

extension BuiltinAgentToolHost {
    func editFile(_ call: BuiltinAgentToolCall) -> BuiltinAgentToolResult {
        guard let path = requiredString("file_path", "path", in: call) else {
            return .failure(toolName: call.name, code: "missing_path")
        }
        guard let oldText = (call.arguments["old_string"]?.stringValue ?? call.arguments["old_text"]?.stringValue),
              let newText = (call.arguments["new_string"]?.stringValue ?? call.arguments["new_text"]?.stringValue) else {
            return .failure(toolName: call.name, code: "missing_edit_text")
        }
        guard oldText != newText else {
            return .failure(toolName: call.name, code: "no_changes")
        }
        let replaceAll = optionalBool("replace_all", in: call) ?? false
        let url = resolvedFileURL(path: path)
        if let failure = fileAccessFailure(toolName: call.name, path: path, url: url, requireWorkspaceForRelativePath: true) {
            return failure
        }
        do {
            let original: String
            if FileManager.default.fileExists(atPath: url.path) {
                let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                if let fileSize = attributes[.size] as? NSNumber,
                   fileSize.uint64Value > Self.maxReadableFileBytes {
                    return .failure(toolName: call.name, code: "file_too_large")
                }
                try ensureFileWasRead(url: url)
                original = try String(contentsOf: url, encoding: .utf8)
            } else {
                guard oldText.isEmpty else {
                    return .failure(toolName: call.name, code: "file_not_found")
                }
                original = ""
            }
            if oldText.isEmpty && original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                return .failure(toolName: call.name, code: "file_already_exists")
            }
            guard oldText.isEmpty || original.contains(oldText) else {
                return .failure(toolName: call.name, code: "old_text_not_found")
            }
            let matches = oldText.isEmpty ? 1 : original.components(separatedBy: oldText).count - 1
            guard replaceAll || matches <= 1 else {
                return .failure(toolName: call.name, code: "multiple_matches")
            }
            let edited: String
            if oldText.isEmpty {
                edited = newText
            } else if replaceAll {
                edited = original.replacingOccurrences(of: oldText, with: newText)
            } else {
                edited = original.replacingCharacters(in: original.range(of: oldText)!, with: newText)
            }
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try edited.write(to: url, atomically: true, encoding: .utf8)
            readFileState[url.path] = BuiltinAgentReadFileState(
                content: edited,
                modifiedAt: fileModificationTime(url),
                isFullRead: true
            )
            return .success(
                toolName: call.name,
                result: [
                    "path": .string(url.path),
                    "kind": .string("file_edited"),
                    "oldString": .string(oldText),
                    "newString": .string(newText),
                    "replaceAll": .bool(replaceAll)
                ]
            )
        } catch let error as BuiltinAgentToolHostError {
            return .failure(toolName: call.name, code: error.code, message: error.message)
        } catch {
            return .failure(toolName: call.name, code: "edit_failed", message: error.localizedDescription)
        }
    }
}
