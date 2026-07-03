import Foundation

extension BuiltinAgentToolHost {
    func grepFiles(_ call: BuiltinAgentToolCall) -> BuiltinAgentToolResult {
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

        do {
            let records = try grepSearchRecords(root: root, call: call)
            let expression = try NSRegularExpression(
                pattern: pattern,
                options: (optionalBool("-i", in: call) ?? false) ? [.caseInsensitive] : []
            )
            let outputMode = call.arguments["output_mode"]?.stringValue ?? "files_with_matches"
            let headLimit = optionalInt("head_limit", in: call) ?? 250
            let offset = max(optionalInt("offset", in: call) ?? 0, 0)
            let result = try grepResult(
                records: records,
                expression: expression,
                outputMode: outputMode,
                lineNumbers: optionalBool("-n", in: call) ?? true,
                limit: headLimit,
                offset: offset
            )
            return .success(toolName: call.name, result: result)
        } catch let error as BuiltinAgentToolHostError {
            return .failure(toolName: call.name, code: error.code, message: error.message)
        } catch {
            return .failure(toolName: call.name, code: "grep_failed", message: error.localizedDescription)
        }
    }

    private func grepSearchRecords(root: URL, call: BuiltinAgentToolCall) throws -> [BuiltinAgentFileSearchSupport.FileRecord] {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory) else {
            throw BuiltinAgentToolHostError(code: "path_not_found", message: "Search path does not exist.")
        }

        let records: [BuiltinAgentFileSearchSupport.FileRecord]
        if isDirectory.boolValue {
            records = try BuiltinAgentFileSearchSupport.regularFiles(under: root)
        } else {
            let workspace = activeWorkspaceDirectory
            records = [
                BuiltinAgentFileSearchSupport.FileRecord(
                    url: root,
                    relativePath: BuiltinAgentFileSearchSupport.relativePath(from: workspace, to: root),
                    modifiedAt: Date()
                )
            ]
        }

        guard let glob = call.arguments["glob"]?.stringValue else { return records }
        return records.filter {
            BuiltinAgentFileSearchSupport.matchesGlob($0.relativePath, pattern: glob)
        }
    }

    private func grepResult(
        records: [BuiltinAgentFileSearchSupport.FileRecord],
        expression: NSRegularExpression,
        outputMode: String,
        lineNumbers: Bool,
        limit: Int,
        offset: Int
    ) throws -> [String: BuiltinAgentJSONValue] {
        switch outputMode {
        case "content":
            return try grepContentResult(
                records: records,
                expression: expression,
                lineNumbers: lineNumbers,
                limit: limit,
                offset: offset
            )
        case "count":
            return try grepCountResult(records: records, expression: expression, limit: limit, offset: offset)
        case "files_with_matches":
            return try grepFilesWithMatchesResult(records: records, expression: expression, limit: limit, offset: offset)
        default:
            throw BuiltinAgentToolHostError(code: "unsupported_output_mode", message: "Unsupported grep output mode.")
        }
    }

    private func grepFilesWithMatchesResult(
        records: [BuiltinAgentFileSearchSupport.FileRecord],
        expression: NSRegularExpression,
        limit: Int,
        offset: Int
    ) throws -> [String: BuiltinAgentJSONValue] {
        let filenames = try records.compactMap { record -> String? in
            let text = try String(contentsOf: record.url, encoding: .utf8)
            return containsMatch(in: text, expression: expression) ? record.relativePath : nil
        }
        let visible = limited(filenames, limit: limit, offset: offset)
        return [
            "mode": .string("files_with_matches"),
            "numFiles": .int(filenames.count),
            "filenames": .array(visible.items.map { .string($0) }),
            "appliedLimit": visible.appliedLimit.map(BuiltinAgentJSONValue.int) ?? .null,
            "appliedOffset": offset > 0 ? .int(offset) : .null
        ]
    }

    private func grepContentResult(
        records: [BuiltinAgentFileSearchSupport.FileRecord],
        expression: NSRegularExpression,
        lineNumbers: Bool,
        limit: Int,
        offset: Int
    ) throws -> [String: BuiltinAgentJSONValue] {
        var filenames: [String] = []
        var outputLines: [String] = []
        for record in records {
            let text = try String(contentsOf: record.url, encoding: .utf8)
            let lines = text.components(separatedBy: .newlines)
            var fileMatched = false
            for (index, line) in lines.enumerated() where containsMatch(in: line, expression: expression) {
                fileMatched = true
                let prefix = lineNumbers ? "\(record.relativePath):\(index + 1):" : "\(record.relativePath):"
                outputLines.append(prefix + line)
            }
            if fileMatched {
                filenames.append(record.relativePath)
            }
        }
        let visible = limited(outputLines, limit: limit, offset: offset)
        return [
            "mode": .string("content"),
            "numFiles": .int(filenames.count),
            "filenames": .array(filenames.map { .string($0) }),
            "content": .string(visible.items.joined(separator: "\n")),
            "numLines": .int(visible.items.count),
            "appliedLimit": visible.appliedLimit.map(BuiltinAgentJSONValue.int) ?? .null,
            "appliedOffset": offset > 0 ? .int(offset) : .null
        ]
    }

    private func grepCountResult(
        records: [BuiltinAgentFileSearchSupport.FileRecord],
        expression: NSRegularExpression,
        limit: Int,
        offset: Int
    ) throws -> [String: BuiltinAgentJSONValue] {
        var rows: [(String, Int)] = []
        for record in records {
            let text = try String(contentsOf: record.url, encoding: .utf8)
            let matches = expression.numberOfMatches(
                in: text,
                range: NSRange(text.startIndex..<text.endIndex, in: text)
            )
            if matches > 0 {
                rows.append((record.relativePath, matches))
            }
        }
        let visible = limited(rows, limit: limit, offset: offset)
        let content = visible.items.map { "\($0.0):\($0.1)" }.joined(separator: "\n")
        return [
            "mode": .string("count"),
            "numFiles": .int(rows.count),
            "filenames": .array(visible.items.map { .string($0.0) }),
            "content": .string(content),
            "numMatches": .int(rows.reduce(0) { $0 + $1.1 }),
            "appliedLimit": visible.appliedLimit.map(BuiltinAgentJSONValue.int) ?? .null,
            "appliedOffset": offset > 0 ? .int(offset) : .null
        ]
    }

    private func containsMatch(in text: String, expression: NSRegularExpression) -> Bool {
        expression.firstMatch(
            in: text,
            range: NSRange(text.startIndex..<text.endIndex, in: text)
        ) != nil
    }

    private func limited<T>(_ values: [T], limit: Int, offset: Int) -> (items: [T], appliedLimit: Int?) {
        let sliced = Array(values.dropFirst(min(offset, values.count)))
        guard limit != 0 else { return (sliced, nil) }
        let effectiveLimit = max(limit, 1)
        let items = Array(sliced.prefix(effectiveLimit))
        return (items, sliced.count > effectiveLimit ? effectiveLimit : nil)
    }
}
