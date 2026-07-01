import Foundation

protocol AgentRuntimeClient: Sendable {
    func run(
        request: AgentRuntimeRequest,
        cliPath: String,
        cliVersion: String?,
        onEvent: @escaping @Sendable (AgentActionEvent) -> Void
    ) async throws -> AgentRuntimeResult
}

struct CodexRuntimeClient: AgentRuntimeClient {
    private let normalizer: CodexEventNormalizer
    private let clock: any AppClock

    init(
        normalizer: CodexEventNormalizer = CodexEventNormalizer(),
        clock: any AppClock = SystemClock()
    ) {
        self.normalizer = normalizer
        self.clock = clock
    }

    func run(
        request: AgentRuntimeRequest,
        cliPath: String,
        cliVersion: String?,
        onEvent: @escaping @Sendable (AgentActionEvent) -> Void
    ) async throws -> AgentRuntimeResult {
        let startedAt = clock.now
        var events: [AgentActionEvent] = []
        var status: AgentActionStatus = .pending
        var finalSummary = ""
        var capturedTokenUsage: AgentTokenUsage?

        let session = try CodexAppServerSession(cliPath: cliPath).start()
        defer { session.stop() }
        try session.send([
            "method": "initialize",
            "id": 1,
            "params": [
                "clientInfo": [
                    "name": "VoxFlow",
                    "version": "1"
                ],
                "capabilities": [String: Any]()
            ]
        ])

        var sawFinalAgentMessage = false
        var completed = false

        for await streamEvent in session.stream {
            switch streamEvent {
            case let .stdout(line):
                guard let decoded = decodeCodexJSONLine(line) else { continue }
                if decoded["id"] as? Int == 1, decoded["result"] != nil {
                    try session.send(threadStartRequest(for: request))
                    continue
                }
                if decoded["id"] as? Int == 2,
                   let id = threadID(from: decoded) {
                    try session.send(turnStartRequest(threadID: id, request: request))
                    continue
                }
                if decoded["id"] as? Int == 3, decoded["error"] != nil {
                    status = .failed
                    let error = AgentActionEvent(
                        kind: .error,
                        title: "Codex 执行失败",
                        detail: stringValue(decoded["error"] ?? "turn/start failed"),
                        timestamp: clock.now,
                        elapsedMS: elapsedMilliseconds(since: startedAt),
                        isFailure: true
                    )
                    events.append(error)
                    onEvent(error)
                    completed = true
                    break
                }

                let method = decoded["method"] as? String
                if let summary = agentMessageText(from: decoded) {
                    if method == "item/agentMessage/delta" {
                        finalSummary += summary
                    } else {
                        finalSummary = summary
                    }
                    sawFinalAgentMessage = true
                }
                if let usage = tokenUsage(from: decoded) {
                    capturedTokenUsage = usage
                }
                let raw = rawEvent(from: decoded)
                if let normalized = normalizer.normalize(raw, startedAt: startedAt) {
                    events.append(normalized)
                    status = normalizer.status(after: normalized)
                    onEvent(normalized)
                }
                if method == "turn/completed" ||
                    (method == "thread/status/changed" && sawFinalAgentMessage && threadStatusIsIdle(decoded)) {
                    completed = true
                    break
                }
            case let .stderr(line):
                let warning = AgentActionEvent(
                    kind: .warning,
                    title: "Codex 运行提示",
                    detail: line,
                    timestamp: clock.now,
                    elapsedMS: elapsedMilliseconds(since: startedAt)
                )
                events.append(warning)
            case let .terminated(exitCode):
                if exitCode != 0 {
                    status = .failed
                    let error = AgentActionEvent(
                        kind: .error,
                        title: "Codex 执行失败",
                        detail: "进程退出码 \(exitCode)",
                        timestamp: clock.now,
                        elapsedMS: elapsedMilliseconds(since: startedAt),
                        isFailure: true
                    )
                    events.append(error)
                    onEvent(error)
                }
                completed = true
            }
            if completed { break }
        }

        if Task.isCancelled {
            throw AgentRuntimeError.cancelled
        }

        let completedAt = clock.now
        if status != .failed {
            status = .completed
        }
        let summary = finalSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        let trace = AgentActionTrace(
            providerID: AgentProviderRegistry.codex.providerID,
            executionMode: .codexRuntime,
            status: status,
            userInstruction: request.instruction,
            screenContext: screenContext(for: request),
            events: events,
            resultSummary: summary.isEmpty ? nil : summary,
            model: request.model ?? cliVersion,
            tokenUsage: capturedTokenUsage,
            startedAt: startedAt,
            completedAt: completedAt,
            failureReason: status == .failed ? events.last(where: \.isFailure)?.detail : nil
        )

        guard status != .failed else {
            throw AgentRuntimeClientError.failed(trace)
        }

        return AgentRuntimeResult(
            summary: summary.isEmpty ? "已完成" : summary,
            status: status,
            trace: trace
        )
    }

    private func threadStartRequest(for request: AgentRuntimeRequest) -> [String: Any] {
        var params: [String: Any] = [
            "cwd": request.workspace.rootDirectory.path,
            "approvalPolicy": "on-request",
            "sandbox": "workspace-write",
            "ephemeral": true,
            "baseInstructions": "你是 VoxFlow 触发的本机 Codex runtime。请根据用户语音指令直接完成可执行动作；如果需要权限，请使用 Codex 自带授权流程。"
        ]
        if let model = request.model?.trimmingCharacters(in: .whitespacesAndNewlines), !model.isEmpty {
            params["model"] = model
        }
        return [
            "method": "thread/start",
            "id": 2,
            "params": params
        ]
    }

    private func turnStartRequest(threadID: String, request: AgentRuntimeRequest) -> [String: Any] {
        var input: [[String: Any]] = [
            [
                "type": "text",
                "text": prompt(for: request),
                "text_elements": []
            ]
        ]
        if Self.supportsImageInput(modelID: request.model),
           let imagePath = request.screenContext?.imagePath {
            input.append([
                "type": "localImage",
                "path": imagePath,
                "detail": "auto"
            ])
        }
        var params: [String: Any] = [
            "threadId": threadID,
            "input": input,
            "cwd": request.workspace.rootDirectory.path,
            "approvalPolicy": "on-request"
        ]
        if let model = request.model?.trimmingCharacters(in: .whitespacesAndNewlines), !model.isEmpty {
            params["model"] = model
        }
        return [
            "method": "turn/start",
            "id": 3,
            "params": params
        ]
    }

    private func prompt(for request: AgentRuntimeRequest) -> String {
        let imageInputSupported = Self.supportsImageInput(modelID: request.model)
        var sections = [
            "你是 VoxFlow 触发的本机 Codex runtime。请根据用户语音指令直接完成可执行动作；如果需要权限，请使用 Codex 自带授权流程。",
            "用户语音指令：\n\(request.instruction)"
        ]
        if let target = request.target {
            sections.append(
                [
                    "目标应用：\(target.appName ?? "未知")",
                    "Bundle ID：\(target.bundleID ?? "未知")",
                    "窗口标题：\(target.windowTitle ?? "未知")"
                ].joined(separator: "\n")
            )
        }
        if let context = request.context {
            var contextLines: [String] = []
            if let windowTitle = context.windowTitle {
                contextLines.append("窗口标题：\(windowTitle)")
            }
            if let selectedText = context.selectedText {
                contextLines.append("选中文本：\n\(selectedText)")
            }
            if let inputAreaText = context.inputAreaText {
                contextLines.append("输入区文本：\n\(inputAreaText)")
            }
            if let visibleText = context.visibleText {
                contextLines.append("可见文本：\n\(visibleText)")
            }
            if imageInputSupported,
               let visual = request.screenContext?.imagePath {
                contextLines.append("截图文件：\(visual)")
            } else if context.visualContentAvailable {
                contextLines.append("视觉上下文：屏幕捕获可用，但当前模型未接收图片输入。")
            }
            if !contextLines.isEmpty {
                sections.append("屏幕上下文：\n" + contextLines.joined(separator: "\n\n"))
            }
        } else if imageInputSupported,
                  let visual = request.screenContext?.imagePath {
            sections.append("屏幕上下文：\n截图文件：\(visual)")
        }
        sections.append("完成后用一句话总结你实际完成了什么。")
        return sections.joined(separator: "\n\n")
    }

    static func supportsImageInput(modelID: String?) -> Bool {
        guard let modelID = modelID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !modelID.isEmpty else {
            return true
        }
        return modelID.caseInsensitiveCompare("gpt-5.3-spark") != .orderedSame
    }

    private func screenContext(for request: AgentRuntimeRequest) -> ScreenContextSnapshot? {
        if let screenContext = request.screenContext {
            return screenContext
        }
        guard request.context != nil || request.target != nil else { return nil }
        return ScreenContextSnapshot(
            thumbnailPath: nil,
            imagePath: nil,
            appName: request.context?.targetAppName ?? request.target?.appName,
            bundleID: request.context?.targetAppBundleID ?? request.target?.bundleID,
            windowTitle: request.context?.windowTitle ?? request.target?.windowTitle,
            capturedAt: clock.now
        )
    }

    private func decodeCodexJSONLine(_ line: String) -> [String: Any]? {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any] else {
            return nil
        }
        return dictionary
    }

    private func rawEvent(from object: [String: Any]) -> CodexRuntimeRawEvent {
        let type = object["method"] as? String ?? object["type"] as? String ?? "unknown"
        var params: [String: String] = [:]
        for (key, value) in object where key != "type" && key != "method" && key != "params" {
            params[key] = stringValue(value)
        }
        if let nestedParams = object["params"] as? [String: Any] {
            for (key, value) in nestedParams {
                params[key] = stringValue(value)
            }
        }
        if let item = object["item"] as? [String: Any] {
            for (key, value) in item {
                params[key] = stringValue(value)
            }
        }
        if let item = itemObject(from: object) {
            for (key, value) in item {
                params[key] = stringValue(value)
            }
        }
        return CodexRuntimeRawEvent(method: type, params: params)
    }

    private func agentMessageText(from object: [String: Any]) -> String? {
        if object["method"] as? String == "item/agentMessage/delta",
           let params = object["params"] as? [String: Any],
           let delta = params["delta"] as? String {
            return delta
        }
        let item = itemObject(from: object)
        let itemType = item?["type"] as? String
        guard itemType == "agent_message" || itemType == "agentMessage" else {
            return nil
        }
        return item?["text"] as? String
    }

    private func tokenUsage(from object: [String: Any]) -> AgentTokenUsage? {
        let topLevelUsage = object["usage"] as? [String: Any]
        let params = object["params"] as? [String: Any]
        let usage = topLevelUsage ??
            ((params?["tokenUsage"] as? [String: Any])?["total"] as? [String: Any])
        guard let usage else {
            return nil
        }
        let input = (usage["input_tokens"] as? Int) ?? (usage["inputTokens"] as? Int)
        let output = (usage["output_tokens"] as? Int) ?? (usage["outputTokens"] as? Int)
        return AgentTokenUsage(
            inputTokens: input,
            outputTokens: output,
            totalTokens: [input, output].compactMap { $0 }.reduce(0, +)
        )
    }

    private func threadID(from object: [String: Any]) -> String? {
        guard let result = object["result"] as? [String: Any],
              let thread = result["thread"] as? [String: Any] else {
            return nil
        }
        return thread["id"] as? String
    }

    private func threadStatusIsIdle(_ object: [String: Any]) -> Bool {
        guard let params = object["params"] as? [String: Any],
              let status = params["status"] as? [String: Any],
              status["type"] as? String == "idle" else {
            return false
        }
        return true
    }

    private func itemObject(from object: [String: Any]) -> [String: Any]? {
        if let item = object["item"] as? [String: Any] {
            return item
        }
        if let params = object["params"] as? [String: Any],
           let item = params["item"] as? [String: Any] {
            return item
        }
        return nil
    }

    private func stringValue(_ value: Any) -> String {
        if let value = value as? String {
            return value
        }
        if JSONSerialization.isValidJSONObject(value),
           let data = try? JSONSerialization.data(withJSONObject: value),
           let json = String(data: data, encoding: .utf8) {
            return json
        }
        return "\(value)"
    }

    private func elapsedMilliseconds(since start: Date) -> Int {
        max(0, Int(clock.now.timeIntervalSince(start) * 1_000))
    }
}

enum AgentRuntimeClientError: Error {
    case failed(AgentActionTrace)
}

private enum CodexExecStreamEvent: Sendable {
    case stdout(String)
    case stderr(String)
    case terminated(Int32)
}

private final class CodexExecLineBuffer: @unchecked Sendable {
    private var pending = ""
    private let emit: @Sendable (String) -> Void

    init(emit: @escaping @Sendable (String) -> Void) {
        self.emit = emit
    }

    func append(_ data: Data) {
        guard !data.isEmpty,
              let chunk = String(data: data, encoding: .utf8) else { return }
        pending += chunk
        let parts = pending.components(separatedBy: .newlines)
        pending = parts.last ?? ""
        for line in parts.dropLast() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            emit(trimmed)
        }
    }

    func flush() {
        let trimmed = pending.trimmingCharacters(in: .whitespacesAndNewlines)
        pending = ""
        guard !trimmed.isEmpty else { return }
        emit(trimmed)
    }
}

private final class CodexAppServerSession: @unchecked Sendable {
    let cliPath: String
    private let process = Process()
    private let stdinPipe = Pipe()
    private let stdoutPipe = Pipe()
    private let stderrPipe = Pipe()
    private let writeQueue = DispatchQueue(label: "com.voxflow.codex-app-server.stdin")
    private var continuation: AsyncStream<CodexExecStreamEvent>.Continuation?
    private var hasStarted = false

    lazy var stream: AsyncStream<CodexExecStreamEvent> = AsyncStream { [weak self] continuation in
        self?.continuation = continuation
        continuation.onTermination = { [weak self] _ in
            self?.stop()
        }
    }

    init(cliPath: String) {
        self.cliPath = cliPath
    }

    func start() throws -> Self {
        _ = stream
        guard !hasStarted else { return self }
        hasStarted = true

        process.executableURL = URL(fileURLWithPath: cliPath)
        process.arguments = ["app-server", "--stdio"]
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let stdoutBuffer = CodexExecLineBuffer { [weak self] line in
            self?.continuation?.yield(.stdout(line))
        }
        let stderrBuffer = CodexExecLineBuffer { [weak self] line in
            self?.continuation?.yield(.stderr(line))
        }

        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            stdoutBuffer.append(handle.availableData)
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            stderrBuffer.append(handle.availableData)
        }

        do {
            try process.run()
        } catch {
            continuation?.yield(.stderr(error.localizedDescription))
            continuation?.yield(.terminated(-1))
            continuation?.finish()
            throw error
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            process.waitUntilExit()
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            stdoutBuffer.flush()
            stderrBuffer.flush()
            continuation?.yield(.terminated(process.terminationStatus))
            continuation?.finish()
        }

        return self
    }

    func send(_ object: [String: Any]) throws {
        try writeQueue.sync {
            guard process.isRunning else {
                throw AgentRuntimeError.executionFailed("Codex app-server is not running.")
            }
            let data = try JSONSerialization.data(withJSONObject: object)
            stdinPipe.fileHandleForWriting.write(data)
            if let newline = "\n".data(using: .utf8) {
                stdinPipe.fileHandleForWriting.write(newline)
            }
        }
    }

    func stop() {
        writeQueue.sync {
            try? stdinPipe.fileHandleForWriting.close()
            if process.isRunning {
                process.terminate()
            }
        }
    }
}
