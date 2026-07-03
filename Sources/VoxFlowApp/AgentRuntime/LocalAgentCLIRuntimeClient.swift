import Foundation

struct LocalAgentCLIRuntimeClient: AgentRuntimeClient {
    static let defaultTimeoutSeconds: Double = 300

    private let descriptor: LocalAgentProviderDescriptor
    private let clock: any AppClock

    init(
        descriptor: LocalAgentProviderDescriptor,
        clock: any AppClock = SystemClock()
    ) {
        self.descriptor = descriptor
        self.clock = clock
    }

    func run(
        request: AgentRuntimeRequest,
        cliPath: String,
        cliVersion: String?,
        onEvent: @escaping @Sendable (AgentActionEvent) -> Void
    ) async throws -> AgentRuntimeResult {
        let startedAt = clock.now
        let started = AgentActionEvent(
            kind: .turnStarted,
            title: "\(descriptor.displayName) 开始执行",
            timestamp: startedAt,
            elapsedMS: 0
        )
        onEvent(started)

        do {
            let output = try await Task.detached(priority: .userInitiated) {
                let prompt = runtimePrompt(for: request, providerName: descriptor.displayName)
                return try runLocalAgentRuntimeCLI(
                    cliPath: cliPath,
                    arguments: localAgentRuntimeArguments(
                        for: descriptor,
                        model: request.model,
                        workingDirectory: request.workspace.sessionDirectory.path
                    ),
                    environment: localAgentChildEnvironment(for: descriptor),
                    prompt: prompt,
                    cwd: request.workspace.sessionDirectory.path,
                    timeoutSeconds: Self.defaultTimeoutSeconds
                )
            }.value
            let completedAt = clock.now
            let summary = output.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let runtimeEvents = LocalAgentCLIEventNormalizer(providerName: descriptor.displayName)
                .normalize(stdout: output.stdout, stderr: output.stderr, startedAt: startedAt)
            for event in runtimeEvents {
                onEvent(event)
            }
            let completed = AgentActionEvent(
                kind: .turnCompleted,
                title: "\(descriptor.displayName) 执行完成",
                detail: summary.isEmpty ? nil : summary,
                timestamp: completedAt,
                elapsedMS: elapsedMilliseconds(from: startedAt, to: completedAt)
            )
            onEvent(completed)
            let trace = AgentActionTrace(
                providerID: descriptor.providerID,
                executionMode: .localAgentRuntime,
                status: .completed,
                userInstruction: request.instruction,
                screenContext: request.screenContext,
                events: [started] + runtimeEvents + [completed],
                resultSummary: summary.isEmpty ? nil : summary,
                model: request.model ?? cliVersion,
                tokenUsage: nil,
                startedAt: startedAt,
                completedAt: completedAt,
                failureReason: nil
            )
            return AgentRuntimeResult(
                summary: summary.isEmpty ? "已完成" : summary,
                status: .completed,
                trace: trace
            )
        } catch {
            let failedAt = clock.now
            let runtimeEvents: [AgentActionEvent]
            if case let AgentRuntimeError.executionFailedWithOutput(_, stdout, stderr) = error {
                runtimeEvents = LocalAgentCLIEventNormalizer(providerName: descriptor.displayName)
                    .normalize(stdout: stdout, stderr: stderr, startedAt: startedAt)
            } else {
                runtimeEvents = []
            }
            for event in runtimeEvents {
                onEvent(event)
            }
            let failure = AgentActionEvent(
                kind: .error,
                title: "\(descriptor.displayName) 执行失败",
                detail: error.localizedDescription,
                timestamp: failedAt,
                elapsedMS: elapsedMilliseconds(from: startedAt, to: failedAt),
                isFailure: true
            )
            onEvent(failure)
            let trace = AgentActionTrace(
                providerID: descriptor.providerID,
                executionMode: .localAgentRuntime,
                status: .failed,
                userInstruction: request.instruction,
                screenContext: request.screenContext,
                events: [started] + runtimeEvents + [failure],
                resultSummary: nil,
                model: request.model ?? cliVersion,
                tokenUsage: nil,
                startedAt: startedAt,
                completedAt: failedAt,
                failureReason: error.localizedDescription
            )
            throw AgentRuntimeClientError.failed(trace)
        }
    }

    private func elapsedMilliseconds(from start: Date, to end: Date) -> Int {
        max(0, Int(end.timeIntervalSince(start) * 1000))
    }
}

private struct LocalAgentRuntimeCLIOutput {
    let text: String
    let stdout: String
    let stderr: String
}

func localAgentRuntimeArguments(
    for descriptor: LocalAgentProviderDescriptor,
    model: String?,
    workingDirectory: String? = nil
) -> [String] {
    var arguments: [String]
    switch descriptor.providerID {
    case AgentProviderRegistry.opencode.providerID:
        arguments = ["run", "--format", "json"]
        if let workingDirectory = workingDirectory?.trimmingCharacters(in: .whitespacesAndNewlines),
           !workingDirectory.isEmpty {
            arguments.append(contentsOf: ["--dir", workingDirectory])
        }
    case AgentProviderRegistry.claude.providerID:
        arguments = [
            "--print",
            "--output-format", "json",
            "--permission-mode", "bypassPermissions",
            "--disable-slash-commands",
            "--no-session-persistence"
        ]
    case AgentProviderRegistry.codebuddy.providerID:
        arguments = ["--print", "-y", "--output-format", "json"]
    case AgentProviderRegistry.pi.providerID:
        arguments = ["--print", "--mode", "json"]
    default:
        arguments = []
    }
    if descriptor.providerID != AgentProviderRegistry.claude.providerID,
       let model = model?.trimmingCharacters(in: .whitespacesAndNewlines),
       !model.isEmpty {
        arguments.append(contentsOf: ["--model", model])
    }
    return arguments
}

private func runtimePrompt(for request: AgentRuntimeRequest, providerName: String) -> String {
    var sections = [
        "你是 VoxFlow 触发的本机 \(providerName) runtime。请根据用户语音指令直接完成可执行动作；如果需要权限，请使用该 CLI 自带授权流程。",
        "不要向用户反问或要求补充说明。需求不完整时，请基于当前工作区、屏幕上下文和合理默认值完成最小可用结果；只有会删除/覆盖重要文件、提交代码、安装依赖、访问敏感信息或执行破坏性操作时才停止并说明未执行原因。",
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
            contextLines.append("选中文本：\n\(truncatedRuntimeContextText(selectedText))")
        }
        if let inputAreaText = context.inputAreaText {
            contextLines.append("输入区文本：\n\(truncatedRuntimeContextText(inputAreaText))")
        }
        if let visibleText = context.visibleText {
            contextLines.append("可见文本：\n\(truncatedRuntimeContextText(visibleText))")
        }
        if let imagePath = request.screenContext?.imagePath {
            contextLines.append("截图文件：\(imagePath)")
        }
        if !contextLines.isEmpty {
            sections.append("屏幕上下文：\n" + contextLines.joined(separator: "\n\n"))
        }
    }
    sections.append("如果用户语音指令要求创建、生成、修改或保存文件、HTML、代码或其他产物，必须在当前工作目录或其子目录落盘对应文件；不要只口头说明已完成。")
    sections.append("完成后用一句话总结你实际完成了什么。")
    return sections.joined(separator: "\n\n")
}

private func truncatedRuntimeContextText(_ text: String, limit: Int = 1_200) -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.count > limit else { return trimmed }
    return String(trimmed.prefix(limit)) + "\n…"
}

private func runLocalAgentRuntimeCLI(
    cliPath: String,
    arguments: [String],
    environment: [String: String],
    prompt: String,
    cwd: String,
    timeoutSeconds: Double
) throws -> LocalAgentRuntimeCLIOutput {
    let result = try LocalAgentProcessRunner.run(
        cliPath,
        arguments: arguments,
        environment: environment,
        stdin: prompt,
        cwd: cwd,
        timeoutSeconds: timeoutSeconds
    )
    if result.timedOut {
        throw AgentRuntimeError.executionFailedWithOutput(
            "runtime timed out",
            stdout: result.stdout,
            stderr: result.stderr
        )
    }
    let text: String
    do {
        text = try localAgentRuntimeOutputOrThrow(
            stdout: result.stdout,
            stderr: result.stderr,
            terminationStatus: result.exitCode,
            prompt: prompt
        )
    } catch let error as AgentRuntimeError {
        throw error.withOutput(stdout: result.stdout, stderr: result.stderr)
    }
    return LocalAgentRuntimeCLIOutput(
        text: text,
        stdout: result.stdout,
        stderr: result.stderr
    )
}

func localAgentRuntimeOutputOrThrow(
    stdout: String,
    stderr: String,
    terminationStatus: Int32,
    prompt: String? = nil
) throws -> String {
    guard terminationStatus == 0 else {
        let parsed = LocalAgentCLIOutputParser.parse(stdout)
        throw AgentRuntimeError.executionFailed(
            firstNonEmptyLocalAgentRuntimeErrorText(
                stderr,
                parsed.errorMessage,
                parsed.text,
                "进程退出码 \(terminationStatus)"
            )
        )
    }
    let parsed = LocalAgentCLIOutputParser.parse(stdout)
    if let errorMessage = parsed.errorMessage {
        throw AgentRuntimeError.executionFailed(errorMessage)
    }
    if parsed.isEmpty {
        let stderrMessage = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if !stderrMessage.isEmpty {
            throw AgentRuntimeError.executionFailed(stderrMessage)
        }
    }
    let displayText = localAgentRuntimeDisplayText(parsed.text, removingPromptEcho: prompt)
    if localAgentRuntimeOutputRequestsClarification(displayText) {
        throw AgentRuntimeError.executionFailed("本机 agent 请求澄清，VoxFlow 已拦截反问，未执行动作。")
    }
    return displayText
}

func localAgentRuntimeDisplayText(_ text: String, removingPromptEcho prompt: String?) -> String {
    guard let prompt = prompt?.trimmingCharacters(in: .whitespacesAndNewlines),
          !prompt.isEmpty else {
        return text
    }
    var result = text
    while let range = result.range(of: prompt) {
        result.removeSubrange(range)
    }
    return result.trimmingCharacters(in: .whitespacesAndNewlines)
}

func localAgentRuntimeOutputRequestsClarification(_ text: String) -> Bool {
    let normalized = text
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: "\n", with: " ")
    guard !normalized.isEmpty else { return false }
    let lowercased = normalized.lowercased()
    let patterns = [
        "请问",
        "你想",
        "你希望",
        "需要更具体",
        "需要更多",
        "请提供",
        "请告诉我",
        "能否提供",
        "无法执行，需要",
        "what kind",
        "please provide",
        "could you clarify",
        "need more details"
    ]
    guard patterns.contains(where: { lowercased.contains($0.lowercased()) }) else {
        return false
    }
    return normalized.contains("?")
        || normalized.contains("？")
        || lowercased.contains("请告诉我")
        || lowercased.contains("please provide")
        || lowercased.contains("could you clarify")
}

private func firstNonEmptyLocalAgentRuntimeErrorText(_ values: String?...) -> String {
    for value in values {
        let text = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !text.isEmpty {
            return text
        }
    }
    return "本机 agent 执行失败"
}
