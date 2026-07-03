import Foundation

extension BuiltinAgentToolHost {
    func readFile(_ call: BuiltinAgentToolCall) -> BuiltinAgentToolResult {
        guard let path = requiredString("file_path", "path", in: call) else {
            return .failure(toolName: call.name, code: "missing_path")
        }
        let url = resolvedFileURL(path: path)
        if let failure = fileAccessFailure(toolName: call.name, path: path, url: url, requireWorkspaceForRelativePath: true) {
            return failure
        }
        guard !isBlockedDevicePath(url.path) else {
            return .failure(toolName: call.name, code: "blocked_device_path")
        }
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            if let fileType = attributes[.type] as? FileAttributeType, fileType == .typeDirectory {
                return .failure(toolName: call.name, code: "is_directory")
            }
            if let fileSize = attributes[.size] as? NSNumber,
               fileSize.uint64Value > Self.maxReadableFileBytes {
                return .failure(
                    toolName: call.name,
                    code: "file_too_large",
                    message: "File exceeds \(Self.maxReadableFileBytes) bytes; ask for a smaller file or use a narrower export."
                )
            }
            let data = try Data(contentsOf: url)
            let text = String(data: data, encoding: .utf8) ?? ""
            let charOffset = optionalInt("char_offset", in: call)
            let visibleText: String
            let offset: Int
            let truncated: Bool
            if let charOffset {
                let limit = min(optionalInt("limit", in: call) ?? 8_000, 20_000)
                offset = max(charOffset, 0)
                visibleText = String(text.dropFirst(min(offset, text.count)).prefix(limit))
                truncated = text.count > offset + limit
            } else {
                let lines = text.components(separatedBy: .newlines)
                let startLine = max(optionalInt("offset", in: call) ?? 0, 0)
                let lineLimit = min(optionalInt("limit", in: call) ?? lines.count, 2_000)
                offset = startLine
                visibleText = lines
                    .dropFirst(min(startLine, lines.count))
                    .prefix(lineLimit)
                    .enumerated()
                    .map { index, line in "\(startLine + index + 1)\t\(line)" }
                    .joined(separator: "\n")
                truncated = lines.count > startLine + lineLimit
            }
            let modifiedAt = fileModificationTime(url)
            readFileState[url.path] = BuiltinAgentReadFileState(
                content: text,
                modifiedAt: modifiedAt,
                isFullRead: charOffset == nil && optionalInt("offset", in: call) == nil && optionalInt("limit", in: call) == nil
            )
            return .success(
                toolName: call.name,
                result: [
                    "path": .string(url.path),
                    "offset": .int(offset),
                    "content": .string(visibleText),
                    "truncated": .bool(truncated)
                ]
            )
        } catch {
            return .failure(toolName: call.name, code: "read_failed", message: error.localizedDescription)
        }
    }
}
