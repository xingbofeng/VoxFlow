import AppKit
import Foundation

enum BuiltinAgentJSONValue: Codable, Equatable, Sendable {
    case string(String)
    case int(Int)
    case bool(Bool)
    case array([BuiltinAgentJSONValue])
    case object([String: BuiltinAgentJSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode([BuiltinAgentJSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: BuiltinAgentJSONValue].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value):
            try container.encode(value)
        case let .int(value):
            try container.encode(value)
        case let .bool(value):
            try container.encode(value)
        case let .array(value):
            try container.encode(value)
        case let .object(value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }

    var stringValue: String? {
        if case let .string(value) = self { return value }
        return nil
    }
}

struct BuiltinAgentToolDefinition: Equatable, Sendable {
    let name: String
    let description: String
    let requiredArguments: [String]
}

enum BuiltinAgentToolRegistry {
    static let definitions: [BuiltinAgentToolDefinition] = [
        BuiltinAgentToolDefinition(
            name: "read_file",
            description: "Read an explicit file or VoxFlow virtual resource.",
            requiredArguments: ["file_path"]
        ),
        BuiltinAgentToolDefinition(
            name: "search_transcriptions",
            description: "Search local voice transcription history.",
            requiredArguments: ["query"]
        ),
        BuiltinAgentToolDefinition(
            name: "respond",
            description: "Deliver a user-facing status, warning, refusal, or manual-action notice.",
            requiredArguments: ["mode", "text"]
        ),
        BuiltinAgentToolDefinition(
            name: "ask_user_question",
            description: "Ask the user 1-4 Claude Code-style multiple-choice questions.",
            requiredArguments: ["questions"]
        ),
        BuiltinAgentToolDefinition(
            name: "write_file",
            description: "Write content to a file, defaulting to the session workspace for new files.",
            requiredArguments: ["file_path", "content"]
        ),
        BuiltinAgentToolDefinition(
            name: "edit_file",
            description: "Edit a file with old_text/new_text replacements.",
            requiredArguments: ["file_path", "old_string", "new_string"]
        ),
        BuiltinAgentToolDefinition(
            name: "notebook_edit",
            description: "Replace, insert, or delete cells in a Jupyter notebook.",
            requiredArguments: ["notebook_path", "new_source"]
        ),
        BuiltinAgentToolDefinition(
            name: "list_files",
            description: "List files under an explicit directory or supported virtual root.",
            requiredArguments: []
        ),
        BuiltinAgentToolDefinition(
            name: "glob_files",
            description: "Find files by glob pattern, using Claude Code Glob-style pattern/path arguments.",
            requiredArguments: ["pattern"]
        ),
        BuiltinAgentToolDefinition(
            name: "grep_files",
            description: "Search file contents with regex, using Claude Code Grep-style arguments.",
            requiredArguments: ["pattern"]
        ),
        BuiltinAgentToolDefinition(
            name: "clipboard",
            description: "Read or write clipboard text. Use action=read_text/read to read and action=write_text/write to write.",
            requiredArguments: ["action"]
        ),
        BuiltinAgentToolDefinition(
            name: "keyboard",
            description: "Simulate policy-gated foreground keyboard input.",
            requiredArguments: ["action"]
        ),
        BuiltinAgentToolDefinition(
            name: "text_field",
            description: "Read or modify the focused text field without submitting forms.",
            requiredArguments: ["action"]
        ),
        BuiltinAgentToolDefinition(
            name: "http_request",
            description: "Make a policy-gated HTTPS request.",
            requiredArguments: ["url"]
        ),
        BuiltinAgentToolDefinition(
            name: "open_url",
            description: "Open a URL only when the user explicitly asked to open that URL.",
            requiredArguments: ["url"]
        ),
        BuiltinAgentToolDefinition(
            name: "web_fetch",
            description: "Fetch content from an explicit URL and return extracted markdown-like text.",
            requiredArguments: ["url", "prompt"]
        ),
        BuiltinAgentToolDefinition(
            name: "web_search",
            description: "Search the web for current information and return source links.",
            requiredArguments: ["query"]
        )
    ]
}

struct BuiltinAgentToolCall: Codable, Equatable, Sendable {
    let id: String
    let name: String
    let arguments: [String: BuiltinAgentJSONValue]
}

struct BuiltinAgentToolError: Codable, Equatable, Sendable {
    let code: String
    let message: String?
}

struct BuiltinAgentReadFileState {
    let content: String
    let modifiedAt: TimeInterval
    let isFullRead: Bool
}

struct BuiltinAgentToolHostError: Error {
    let code: String
    let message: String
}

struct BuiltinAgentToolResult: Codable, Equatable, Sendable {
    let ok: Bool
    let toolName: String
    let result: [String: BuiltinAgentJSONValue]?
    let error: BuiltinAgentToolError?

    static func success(
        toolName: String,
        result: [String: BuiltinAgentJSONValue] = [:]
    ) -> BuiltinAgentToolResult {
        BuiltinAgentToolResult(
            ok: true,
            toolName: toolName,
            result: result,
            error: nil
        )
    }

    static func failure(
        toolName: String,
        code: String,
        message: String? = nil
    ) -> BuiltinAgentToolResult {
        BuiltinAgentToolResult(
            ok: false,
            toolName: toolName,
            result: nil,
            error: BuiltinAgentToolError(code: code, message: message)
        )
    }
}

@MainActor
protocol BuiltinAgentToolExecuting: AnyObject {
    func pasteAtCursor(_ text: String) async -> Bool
    func replaceSelection(_ text: String) async -> Bool
    func openURL(_ url: URL) async -> Bool
    func simulateKeyboard(action: String, text: String?, key: String?, keys: [String]) async -> Bool
    func notifyUser(_ message: String) async
}

@MainActor
protocol BuiltinAgentClipboardAccessing: AnyObject {
    func readText() -> String?
    func writeText(_ text: String)
}

@MainActor
final class SystemBuiltinAgentClipboard: BuiltinAgentClipboardAccessing {
    func readText() -> String? {
        NSPasteboard.general.string(forType: .string)
    }

    func writeText(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

@MainActor
struct BuiltinAgentToolEnvironment {
    let userInstruction: String
    let context: ContextSnapshot?
    let executor: any BuiltinAgentToolExecuting
    var historyRepository: (any HistoryRepository)?
    var workspaceDirectory: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    var clipboard: any BuiltinAgentClipboardAccessing = SystemBuiltinAgentClipboard()
    var httpClient: @Sendable (URLRequest) async throws -> (Data, URLResponse) = {
        try await URLSession.shared.data(for: $0)
    }
}

@MainActor
final class BuiltinAgentToolHost {
    static let maxReadableFileBytes: UInt64 = 1_000_000
    static let maxWritableFileBytes = 500_000
    static let maxHTTPBodyCharacters = 40_000

    let environment: BuiltinAgentToolEnvironment
    var readFileState: [String: BuiltinAgentReadFileState] = [:]

    var activeWorkspaceDirectory: URL {
        environment.workspaceDirectory
    }

    init(environment: BuiltinAgentToolEnvironment) {
        self.environment = environment
    }

    func call(_ call: BuiltinAgentToolCall) async -> BuiltinAgentToolResult {
        switch call.name {
        case "read_frontmost_context":
            return readFrontmostContext(toolName: call.name)
        case "read_selection_or_input_text":
            return readSelectionOrInputText(toolName: call.name)
        case "paste_at_cursor":
            return await pasteAtCursor(call)
        case "replace_selection":
            return await replaceSelection(call)
        case "notify_user":
            return await notifyUser(call)
        case "read_file":
            return readFile(call)
        case "search_transcriptions":
            return searchTranscriptions(call)
        case "respond":
            return await respond(call)
        case "ask_user_question":
            return await askUserQuestion(call)
        case "write_file":
            return writeFile(call)
        case "edit_file":
            return editFile(call)
        case "notebook_edit":
            return notebookEdit(call)
        case "list_files":
            return listFiles(call)
        case "glob_files":
            return globFiles(call)
        case "grep_files":
            return grepFiles(call)
        case "clipboard":
            return clipboard(call)
        case "keyboard":
            return await keyboard(call)
        case "text_field":
            return await textField(call)
        case "http_request":
            return await httpRequest(call)
        case "open_url":
            return await openURL(call)
        case "web_fetch":
            return await webFetch(call)
        case "web_search":
            return await webSearch(call)
        default:
            return .failure(toolName: call.name, code: "unknown_tool")
        }
    }

    private func readFrontmostContext(toolName: String) -> BuiltinAgentToolResult {
        guard let context = environment.context else {
            return .failure(toolName: toolName, code: "missing_context")
        }
        return .success(
            toolName: toolName,
            result: [
                "appName": context.targetAppName.map(BuiltinAgentJSONValue.string) ?? .null,
                "bundleID": context.targetAppBundleID.map(BuiltinAgentJSONValue.string) ?? .null,
                "windowTitle": context.windowTitle.map(BuiltinAgentJSONValue.string) ?? .null,
                "visibleText": context.visibleText.map(BuiltinAgentJSONValue.string) ?? .null,
                "warnings": .array(context.warnings.map(BuiltinAgentJSONValue.string))
            ]
        )
    }

    func readSelectionOrInputText(toolName: String) -> BuiltinAgentToolResult {
        guard let context = environment.context else {
            return .failure(toolName: toolName, code: "missing_context")
        }
        if let selectedText = nonEmpty(context.selectedText) {
            return .success(
                toolName: toolName,
                result: [
                    "source": .string("selection"),
                    "text": .string(selectedText)
                ]
            )
        }
        if let inputText = nonEmpty(context.inputAreaText) {
            return .success(
                toolName: toolName,
                result: [
                    "source": .string("inputArea"),
                    "text": .string(inputText)
                ]
            )
        }
        return .failure(toolName: toolName, code: "missing_text_target")
    }

    private func pasteAtCursor(_ call: BuiltinAgentToolCall) async -> BuiltinAgentToolResult {
        guard let text = requiredString("text", in: call) else {
            return .failure(toolName: call.name, code: "missing_text")
        }
        let didPaste = await environment.executor.pasteAtCursor(text)
        return didPaste
            ? .success(toolName: call.name, result: ["kind": .string("pasted")])
            : .failure(toolName: call.name, code: "paste_failed")
    }

    private func replaceSelection(_ call: BuiltinAgentToolCall) async -> BuiltinAgentToolResult {
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
    }

    private func notifyUser(_ call: BuiltinAgentToolCall) async -> BuiltinAgentToolResult {
        guard let message = requiredString("message", in: call) else {
            return .failure(toolName: call.name, code: "missing_message")
        }
        await environment.executor.notifyUser(message)
        return .success(toolName: call.name, result: ["kind": .string("notified")])
    }

    func requiredString(_ key: String, in call: BuiltinAgentToolCall) -> String? {
        nonEmpty(call.arguments[key]?.stringValue)
    }

    func requiredString(_ keys: String..., in call: BuiltinAgentToolCall) -> String? {
        for key in keys {
            if let value = nonEmpty(call.arguments[key]?.stringValue) {
                return value
            }
        }
        return nil
    }

    func optionalInt(_ key: String, in call: BuiltinAgentToolCall) -> Int? {
        if case let .int(value)? = call.arguments[key] {
            return value
        }
        if case let .string(value)? = call.arguments[key] {
            return Int(value)
        }
        return nil
    }

    func optionalBool(_ key: String, in call: BuiltinAgentToolCall) -> Bool? {
        if case let .bool(value)? = call.arguments[key] {
            return value
        }
        if case let .string(value)? = call.arguments[key] {
            switch value.lowercased() {
            case "true", "yes", "1":
                return true
            case "false", "no", "0":
                return false
            default:
                return nil
            }
        }
        return nil
    }

    func stringArray(_ key: String, in call: BuiltinAgentToolCall) -> [String] {
        if case let .array(values)? = call.arguments[key] {
            return values.compactMap(\.stringValue)
        }
        return []
    }

    func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    static func userExplicitlyAskedToOpen(url: URL, instruction: String) -> Bool {
        let normalizedInstruction = instruction.lowercased()
        let normalizedURL = url.absoluteString.lowercased()
        let openVerbs = ["打开", "访问", "跳转", "open ", "go to", "visit "]
        return normalizedInstruction.contains(normalizedURL)
            && openVerbs.contains { normalizedInstruction.contains($0) }
    }

    static func userExplicitlyMentionedURL(_ url: URL, instruction: String) -> Bool {
        instruction.lowercased().contains(url.absoluteString.lowercased())
    }

    private static func userExplicitlyMentioned(path: String, instruction: String) -> Bool {
        let normalizedInstruction = instruction.lowercased()
        let normalizedPath = path.lowercased()
        return normalizedInstruction.contains(normalizedPath)
            || normalizedInstruction.contains((normalizedPath as NSString).lastPathComponent)
    }

    func fileAccessFailure(
        toolName: String,
        path: String,
        url: URL,
        requireWorkspaceForRelativePath: Bool
    ) -> BuiltinAgentToolResult? {
        if isWorkspacePath(url) {
            return nil
        }
        if !isAbsoluteUserPath(path), requireWorkspaceForRelativePath {
            return .failure(toolName: toolName, code: "path_outside_workspace")
        }
        guard Self.userExplicitlyMentioned(path: path, instruction: environment.userInstruction) else {
            return .failure(toolName: toolName, code: "missing_explicit_user_intent")
        }
        return nil
    }

    func resolvedFileURL(path: String) -> URL {
        let expanded = NSString(string: path).expandingTildeInPath
        if expanded.hasPrefix("/") || path.hasPrefix("~") {
            return URL(fileURLWithPath: expanded).standardizedFileURL
        }
        return activeWorkspaceDirectory.appendingPathComponent(path).standardizedFileURL
    }

    private func isWorkspacePath(_ url: URL) -> Bool {
        let workspacePath = activeWorkspaceDirectory.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        return path == workspacePath || path.hasPrefix(workspacePath + "/")
    }

    private func isAbsoluteUserPath(_ path: String) -> Bool {
        path.hasPrefix("/") || path.hasPrefix("~")
    }

    func existingTextForWrite(url: URL) throws -> String? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        try ensureFileWasRead(url: url)
        return try String(contentsOf: url, encoding: .utf8)
    }

    func ensureFileWasRead(url: URL) throws {
        guard let state = readFileState[url.path] else {
            throw BuiltinAgentToolHostError(
                code: "file_not_read",
                message: "Read the file before modifying an existing file."
            )
        }
        let current = fileModificationTime(url)
        if current > state.modifiedAt {
            if state.isFullRead,
               let currentContent = try? String(contentsOf: url, encoding: .utf8),
               currentContent == state.content {
                return
            }
            throw BuiltinAgentToolHostError(
                code: "file_modified_since_read",
                message: "File has been modified since read; read it again before editing."
            )
        }
    }

    func fileModificationTime(_ url: URL) -> TimeInterval {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
    }

    func isBlockedDevicePath(_ path: String) -> Bool {
        let blocked = [
            "/dev/zero",
            "/dev/random",
            "/dev/urandom",
            "/dev/full",
            "/dev/stdin",
            "/dev/tty",
            "/dev/console",
            "/dev/stdout",
            "/dev/stderr",
            "/dev/fd/0",
            "/dev/fd/1",
            "/dev/fd/2"
        ]
        if blocked.contains(path) {
            return true
        }
        return path.hasPrefix("/proc/")
            && (path.hasSuffix("/fd/0") || path.hasSuffix("/fd/1") || path.hasSuffix("/fd/2"))
    }

    func isSubmitKey(_ key: String) -> Bool {
        ["enter", "return"].contains(key.lowercased())
    }
}

extension BuiltinAgentToolHost: @unchecked Sendable {}

extension String {
    func truncated(limit: Int) -> String {
        guard count > limit else { return self }
        return String(prefix(limit))
    }
}
