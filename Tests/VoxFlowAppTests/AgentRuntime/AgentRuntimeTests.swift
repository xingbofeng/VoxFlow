import Darwin
import XCTest
@testable import VoxFlowApp

final class AgentRuntimeTests: XCTestCase {
    func testLocalAgentProviderRegistryExposesSupportedProviders() {
        let providers = AgentProviderRegistry.enabledRuntimeProviders

        XCTAssertEqual(providers.map(\.providerID), ["codex", "opencode", "claude", "codebuddy", "pi"])
        XCTAssertEqual(providers.first { $0.providerID == "pi" }?.displayName, "Pi Agent")
        XCTAssertEqual(providers.first { $0.providerID == "opencode" }?.displayName, "Opencode")
        XCTAssertEqual(providers.first { $0.providerID == "opencode" }?.baseURL, "local://opencode")
        XCTAssertEqual(providers.first { $0.providerID == "claude" }?.executableNames, ["claude"])
        XCTAssertTrue(providers.allSatisfy { $0.capabilities.contains(.agentRuntime) })
    }

    func testLLMProviderRecordIdentifiesLocalAgentProvidersAndCodexCompatibility() {
        let legacyCodexByType = LLMProviderRecord(
            id: "legacy",
            displayName: "Codex",
            providerType: "codex",
            baseURL: "https://unused.example.com",
            defaultModel: "gpt-5.5",
            apiKeyRef: "codex-local-runtime",
            temperature: 0,
            timeoutSeconds: 120,
            enabled: true,
            isDefault: true,
            lastHealthStatus: nil,
            lastHealthMessage: nil,
            lastLatencyMS: nil,
            createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let opencode = LLMProviderRecord(
            id: "opencode",
            displayName: "opencode",
            providerType: "opencode",
            baseURL: "local://opencode",
            defaultModel: "opencode/default",
            apiKeyRef: "opencode-local-runtime",
            temperature: 0,
            timeoutSeconds: 120,
            enabled: true,
            isDefault: false,
            lastHealthStatus: nil,
            lastHealthMessage: nil,
            lastLatencyMS: nil,
            createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )

        XCTAssertTrue(legacyCodexByType.isCodexLLMProvider)
        XCTAssertTrue(legacyCodexByType.isLocalAgentProvider)
        XCTAssertTrue(opencode.isLocalAgentProvider)
        XCTAssertFalse(opencode.isOpenAICompatibleProvider)
    }

    func testAgentExecutionModeAddsGenericRuntimeWhileOldCodexTraceDecodes() throws {
        let newMode = try JSONDecoder().decode(AgentExecutionMode.self, from: #""localAgentRuntime""#.data(using: .utf8)!)
        let oldMode = try JSONDecoder().decode(AgentExecutionMode.self, from: #""codexRuntime""#.data(using: .utf8)!)
        let oldFallbackMode = try JSONDecoder().decode(
            AgentExecutionMode.self,
            from: "\"\(["codex", "TextFallback"].joined())\"".data(using: .utf8)!
        )

        XCTAssertEqual(newMode, .localAgentRuntime)
        XCTAssertEqual(oldMode, .codexRuntime)
        XCTAssertEqual(oldFallbackMode, .textOnly)
    }

    func testRuntimeProviderSelectionResolvesLocalProviderDescriptor() {
        let selection = AgentRuntimeProviderSelection(providerID: "opencode", model: "kimi-k2")

        XCTAssertFalse(selection.usesCodexRuntime)
        XCTAssertEqual(selection.localAgentProvider?.providerID, "opencode")
        XCTAssertEqual(selection.localAgentProvider?.baseURL, "local://opencode")
    }

    func testLocalAgentCLIDetectorReadsVersionAndRequiredHelpWithoutPromptInvocation() async throws {
        let root = try makeTemporaryDirectory()
        let cli = root.appendingPathComponent("opencode")
        let promptMarker = root.appendingPathComponent("prompt-invoked")
        try """
        #!/bin/sh
        if [ "$1" = "--version" ]; then
          echo "opencode 1.2.3"
          exit 0
        fi
        if [ "$1" = "run" ] && [ "$2" = "--help" ]; then
          echo "Usage: opencode run --format json"
          exit 0
        fi
        if [ "$1" = "run" ]; then
          echo prompt > "\(promptMarker.path)"
          exit 0
        fi
        exit 1
        """.write(to: cli, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: cli.path)
        let clock = MutableAgentRuntimeClock(now: Date(timeIntervalSince1970: 1_800_000_000))
        let adapter = LocalAgentCLIAdapter(
            descriptor: AgentProviderRegistry.opencode,
            configuration: LocalAgentCLIConfiguration(
                cacheTTL: 60,
                candidateCLIPaths: [cli.path],
                versionArguments: ["--version"],
                helpChecks: [
                    LocalAgentCLIHelpCheck(arguments: ["run", "--help"], requiredFragments: ["run", "--format", "json"])
                ],
                modelListArguments: ["models"]
            ),
            clock: clock
        )

        let availability = await adapter.cachedOrDetect(forceRefresh: true)

        XCTAssertTrue(availability.isAvailable)
        XCTAssertEqual(availability.providerID, "opencode")
        XCTAssertEqual(availability.cliPath, cli.path)
        XCTAssertEqual(availability.cliVersion, "opencode 1.2.3")
        XCTAssertFalse(FileManager.default.fileExists(atPath: promptMarker.path))
    }

    func testLocalAgentCLIDetectorReadsVersionFromStderr() async throws {
        let root = try makeTemporaryDirectory()
        let cli = root.appendingPathComponent("pi")
        try """
        #!/bin/sh
        if [ "$1" = "--version" ]; then
          echo "0.75.5" >&2
          exit 0
        fi
        if [ "$1" = "--help" ]; then
          echo "Usage: pi print"
          exit 0
        fi
        exit 1
        """.write(to: cli, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: cli.path)

        let adapter = LocalAgentCLIAdapter(
            descriptor: AgentProviderRegistry.pi,
            configuration: LocalAgentCLIConfiguration(
                candidateCLIPaths: [cli.path],
                versionArguments: ["--version"],
                helpChecks: [
                    LocalAgentCLIHelpCheck(arguments: ["--help"], requiredFragments: ["print"])
                ]
            )
        )

        let availability = await adapter.cachedOrDetect(forceRefresh: true)

        XCTAssertTrue(availability.isAvailable)
        XCTAssertEqual(availability.cliVersion, "0.75.5")
    }

    func testLocalAgentProcessRunnerProvidesStablePathForEnvShebangCLIs() throws {
        let result = try LocalAgentProcessRunner.run(
            "/usr/bin/env",
            arguments: ["sh", "-c", "printf stable-path"],
            environment: [:]
        )

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stdout, "stable-path")
    }

    func testLocalAgentProcessRunnerTerminatesChildProcessOnTimeout() throws {
        let root = try makeTemporaryDirectory()
        let childPIDFile = root.appendingPathComponent("child.pid")
        let cli = root.appendingPathComponent("spawn-child")
        try """
        #!/bin/sh
        sleep 30 &
        echo $! > "\(childPIDFile.path)"
        wait
        """.write(to: cli, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: cli.path)

        let result = try LocalAgentProcessRunner.run(
            cli.path,
            arguments: [],
            timeoutSeconds: 0.1
        )
        let childPID = try Int32(
            String(contentsOf: childPIDFile, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        ).unwrap()

        XCTAssertTrue(result.timedOut)
        XCTAssertTrue(waitUntilProcessExits(pid: childPID, timeout: 2))
    }

    func testLocalAgentCLIModelListParsesJSONAndPlainTextModels() async throws {
        let root = try makeTemporaryDirectory()
        let jsonCLI = root.appendingPathComponent("opencode")
        try """
        #!/bin/sh
        if [ "$1" = "models" ]; then
          echo '[{"id":"kimi-k2"},{"model":"qwen3-coder"},{"id":"kimi-k2"}]'
          exit 0
        fi
        exit 1
        """.write(to: jsonCLI, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: jsonCLI.path)
        let textCLI = root.appendingPathComponent("claude")
        try """
        #!/bin/sh
        if [ "$1" = "models" ]; then
          echo 'sonnet'
          echo 'opus'
          exit 0
        fi
        exit 1
        """.write(to: textCLI, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: textCLI.path)

        let jsonAdapter = LocalAgentCLIAdapter(
            descriptor: AgentProviderRegistry.opencode,
            configuration: LocalAgentCLIConfiguration(candidateCLIPaths: [jsonCLI.path], modelListArguments: ["models"])
        )
        let textAdapter = LocalAgentCLIAdapter(
            descriptor: AgentProviderRegistry.claude,
            configuration: LocalAgentCLIConfiguration(candidateCLIPaths: [textCLI.path], modelListArguments: ["models"])
        )

        let jsonModels = await jsonAdapter.listModels(cliPath: jsonCLI.path)
        let textModels = await textAdapter.listModels(cliPath: textCLI.path)

        XCTAssertEqual(jsonModels, ["kimi-k2", "qwen3-coder"])
        XCTAssertEqual(textModels, ["sonnet", "opus"])
    }

    func testLocalAgentCLIModelListDrainsLargeOutputBeforeExit() async throws {
        let root = try makeTemporaryDirectory()
        let cli = root.appendingPathComponent("opencode")
        let filler = String(repeating: "x", count: 1_024)
        try """
        #!/bin/sh
        if [ "$1" = "models" ]; then
          i=0
          while [ "$i" -lt 1024 ]; do
            echo "\(filler)"
            i=$((i + 1))
          done
          echo "large-output-model"
          exit 0
        fi
        exit 1
        """.write(to: cli, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: cli.path)
        let adapter = LocalAgentCLIAdapter(
            descriptor: AgentProviderRegistry.opencode,
            configuration: LocalAgentCLIConfiguration(candidateCLIPaths: [cli.path], modelListArguments: ["models"])
        )

        let models = await adapter.listModels(cliPath: cli.path)

        XCTAssertTrue(models.contains("large-output-model"))
    }

    func testLocalAgentCLIModelListParsesStderrTableModels() async throws {
        let root = try makeTemporaryDirectory()
        let cli = root.appendingPathComponent("pi")
        try """
        #!/bin/sh
        if [ "$1" = "--list-models" ]; then
          echo "provider     model                         context" >&2
          echo "commandcode  claude-haiku-4-5-20251001     200K" >&2
          echo "commandcode  claude-opus-4-7               200K" >&2
          exit 0
        fi
        exit 1
        """.write(to: cli, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: cli.path)
        let adapter = LocalAgentCLIAdapter(
            descriptor: AgentProviderRegistry.pi,
            configuration: LocalAgentCLIConfiguration(candidateCLIPaths: [cli.path], modelListArguments: ["--list-models"])
        )

        let models = await adapter.listModels(cliPath: cli.path)

        XCTAssertEqual(models, ["claude-haiku-4-5-20251001", "claude-opus-4-7"])
    }

    func testLocalAgentCLIModelListParsesCodeBuddySupportedModelsFromHelp() async throws {
        let root = try makeTemporaryDirectory()
        let cli = root.appendingPathComponent("codebuddy")
        try """
        #!/bin/sh
        if [ "$1" = "--help" ]; then
          echo "  --model <model> Currently supported: (glm-5.2, kimi-k2.7, deepseek-v4-pro)"
          exit 0
        fi
        exit 1
        """.write(to: cli, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: cli.path)
        let adapter = LocalAgentCLIAdapter(
            descriptor: AgentProviderRegistry.codebuddy,
            configuration: LocalAgentCLIConfiguration(candidateCLIPaths: [cli.path], modelListArguments: ["--help"])
        )

        let models = await adapter.listModels(cliPath: cli.path)

        XCTAssertEqual(models, ["glm-5.2", "kimi-k2.7", "deepseek-v4-pro"])
    }

    func testLocalAgentCLIModelListFailureAllowsManualFallback() async throws {
        let root = try makeTemporaryDirectory()
        let cli = root.appendingPathComponent("codebuddy")
        try """
        #!/bin/sh
        exit 2
        """.write(to: cli, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: cli.path)
        let adapter = LocalAgentCLIAdapter(
            descriptor: AgentProviderRegistry.codebuddy,
            configuration: LocalAgentCLIConfiguration(candidateCLIPaths: [cli.path], modelListArguments: ["models"])
        )

        let models = await adapter.listModels(cliPath: cli.path)

        XCTAssertEqual(models, [])
    }

    func testCodeBuddyDefaultModelListReadsSupportedModelsFromHelp() async throws {
        let root = try makeTemporaryDirectory()
        let cli = root.appendingPathComponent("codebuddy")
        try """
        #!/bin/sh
        if [ "$1" = "--help" ]; then
          echo "  --model <model> Currently supported: (glm-5.2, kimi-k2.7)"
          exit 0
        fi
        exit 1
        """.write(to: cli, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: cli.path)
        let configuration = LocalAgentCLIConfiguration.default(for: AgentProviderRegistry.codebuddy)

        let adapter = LocalAgentCLIAdapter(
            descriptor: AgentProviderRegistry.codebuddy,
            configuration: configuration
        )

        let models = await adapter.listModels(cliPath: cli.path)

        XCTAssertEqual(models, ["glm-5.2", "kimi-k2.7"])
    }

    func testClaudeModelListReadsConfiguredModelFromSettingsJSON() async throws {
        let root = try makeTemporaryDirectory()
        let settings = root.appendingPathComponent("settings.json")
        try """
        {
          "env": {
            "ANTHROPIC_DEFAULT_HAIKU_MODEL": "claude-haiku-4-5",
            "ANTHROPIC_DEFAULT_HAIKU_MODEL_NAME": "deepseek-v4-flash-202605"
          },
          "model": "haiku"
        }
        """.write(to: settings, atomically: true, encoding: .utf8)
        let cli = root.appendingPathComponent("claude")
        try """
        #!/bin/sh
        exit 1
        """.write(to: cli, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: cli.path)
        let adapter = LocalAgentCLIAdapter(
            descriptor: AgentProviderRegistry.claude,
            configuration: LocalAgentCLIConfiguration(
                candidateCLIPaths: [cli.path],
                modelListArguments: nil,
                claudeSettingsURL: settings
            )
        )

        let models = await adapter.listModels(cliPath: cli.path)

        XCTAssertEqual(models, ["deepseek-v4-flash-202605"])
    }

    func testClaudeConfiguredModelFallsBackToResolvedModelID() throws {
        let root = try makeTemporaryDirectory()
        let settings = root.appendingPathComponent("settings.json")
        try """
        {
          "env": {
            "ANTHROPIC_DEFAULT_SONNET_MODEL": "claude-sonnet-4-6"
          },
          "model": "sonnet"
        }
        """.write(to: settings, atomically: true, encoding: .utf8)

        XCTAssertEqual(
            LocalAgentCLIAdapter.claudeConfiguredModelID(settingsURL: settings),
            "claude-sonnet-4-6"
        )
    }

    func testLocalAgentOutputParserTreatsCLIErrorJSONAsFailure() {
        let output = """
        {"type":"result","subtype":"success","is_error":true,"result":"model auto is unavailable"}
        """

        let parsed = LocalAgentCLIOutputParser.parse(output)

        XCTAssertEqual(parsed.text, "model auto is unavailable")
        XCTAssertEqual(parsed.errorMessage, "model auto is unavailable")
    }

    func testLocalAgentOutputParserExtractsNestedTypeErrorMessage() {
        let output = """
        {"type":"error","error":{"type":"CreditsError","message":"Insufficient balance"}}
        """

        let parsed = LocalAgentCLIOutputParser.parse(output)

        XCTAssertEqual(parsed.text, "Insufficient balance")
        XCTAssertEqual(parsed.errorMessage, "Insufficient balance")
    }

    func testLocalAgentOutputParserExtractsSuccessfulResultText() {
        let output = """
        {"type":"result","is_error":false,"result":"VOXFLOW_SMOKE_OK"}
        """

        let parsed = LocalAgentCLIOutputParser.parse(output)

        XCTAssertEqual(parsed.text, "VOXFLOW_SMOKE_OK")
        XCTAssertNil(parsed.errorMessage)
    }

    func testLocalAgentOutputParserExtractsOpenCodeNDJSONTextEvents() {
        let output = """
        {"type":"step_start","part":{"type":"step-start"}}
        {"type":"text","part":{"type":"text","text":"VOXFLOW_SMOKE_OK"}}
        {"type":"step_finish","part":{"type":"step-finish"}}
        """

        let parsed = LocalAgentCLIOutputParser.parse(output)

        XCTAssertEqual(parsed.text, "VOXFLOW_SMOKE_OK")
        XCTAssertNil(parsed.errorMessage)
    }

    func testLocalAgentOutputParserPrefersCodeBuddyFinalResultOverPromptEcho() {
        let output = """
        [
          {"type":"message","role":"user","content":[{"type":"input_text","text":"do not return this prompt"}]},
          {"type":"message","role":"assistant","content":[{"type":"output_text","text":"VOXFLOW_SMOKE_OK"}]},
          {"type":"result","is_error":false,"result":"VOXFLOW_SMOKE_OK"}
        ]
        """

        let parsed = LocalAgentCLIOutputParser.parse(output)

        XCTAssertEqual(parsed.text, "VOXFLOW_SMOKE_OK")
        XCTAssertNil(parsed.errorMessage)
    }

    func testLocalAgentOutputParserPrefersFinalTurnOverIncrementalEvents() {
        let output = """
        {"type":"message_update","assistantMessageEvent":{"type":"text_delta","delta":"VO"},"message":{"role":"assistant","content":[{"type":"text","text":"VO"}]}}
        {"type":"message_update","assistantMessageEvent":{"type":"text_end","content":"VOXFLOW_SMOKE_OK"},"message":{"role":"assistant","content":[{"type":"text","text":"VOXFLOW_SMOKE_OK"}]}}
        {"type":"turn_end","message":{"role":"assistant","content":[{"type":"thinking","thinking":"hidden chain"},{"type":"text","text":"VOXFLOW_SMOKE_OK"}]}}
        """

        let parsed = LocalAgentCLIOutputParser.parse(output)

        XCTAssertEqual(parsed.text, "VOXFLOW_SMOKE_OK")
        XCTAssertNil(parsed.errorMessage)
    }

    func testLocalAgentOutputParserTreatsPiStopReasonErrorAsFailure() {
        let output = """
        {"type":"message_end","stopReason":"error","errorMessage":"Connection error.","message":{"role":"assistant","content":[]}}
        """

        let parsed = LocalAgentCLIOutputParser.parse(output)

        XCTAssertEqual(parsed.text, "Connection error.")
        XCTAssertEqual(parsed.errorMessage, "Connection error.")
    }

    func testLocalAgentOutputParserTreatsNestedPiStopReasonErrorAsFailure() {
        let output = """
        {"type":"message_end","message":{"role":"assistant","content":[],"stopReason":"error","errorMessage":"Connection error."}}
        {"type":"turn_end","message":{"role":"assistant","content":[],"stopReason":"error","errorMessage":"Connection error."},"toolResults":[]}
        {"type":"agent_end","messages":[{"role":"assistant","content":[],"stopReason":"error","errorMessage":"Connection error."}],"willRetry":false}
        {"type":"auto_retry_end","success":false,"attempt":3,"finalError":"Connection error."}
        """

        let parsed = LocalAgentCLIOutputParser.parse(output)

        XCTAssertEqual(parsed.text, "Connection error.")
        XCTAssertEqual(parsed.errorMessage, "Connection error.")
    }

    func testLocalAgentOutputParserDoesNotLetPiPromptEchoHideFinalError() {
        let output = """
        {"type":"session","id":"session-1","cwd":"/tmp/voxflow"}
        {"type":"message_start","message":{"role":"user","content":[{"type":"text","text":"你是 VoxFlow 触发的本机 Pi Agent runtime。用户语音指令：生成一个 HTML。"}]}}
        {"type":"message_end","message":{"role":"user","content":[{"type":"text","text":"你是 VoxFlow 触发的本机 Pi Agent runtime。用户语音指令：生成一个 HTML。"}]}}
        {"type":"message_end","message":{"role":"assistant","content":[],"stopReason":"error","errorMessage":"Connection error."}}
        {"type":"auto_retry_end","success":false,"attempt":3,"finalError":"Connection error."}
        """

        let parsed = LocalAgentCLIOutputParser.parse(output)

        XCTAssertEqual(parsed.text, "Connection error.")
        XCTAssertEqual(parsed.errorMessage, "Connection error.")
    }

    func testLocalAgentOutputParserKeepsSuccessfulTextWhenPiEmitsRecoverableErrorEvent() {
        let output = """
        {"type":"message_end","errorMessage":"Connection error.","message":{"role":"assistant","content":[]}}
        {"type":"text","text":"VOXFLOW_SMOKE_OK"}
        """

        let parsed = LocalAgentCLIOutputParser.parse(output)

        XCTAssertEqual(parsed.text, "VOXFLOW_SMOKE_OK")
        XCTAssertNil(parsed.errorMessage)
    }

    func testLocalAgentOutputParserPrefersPiAssistantMessageOverPromptEcho() {
        let output = """
        {"messages":[{"role":"user","content":[{"type":"text","text":"你是 VoxFlow runtime。用户语音指令：打开谷歌浏览器。"}]},{"role":"tool","name":"bash","content":[{"type":"text","text":"(no output)"}]},{"role":"assistant","content":[{"type":"thinking","thinking":"hidden"},{"type":"text","text":"已打开 Google Chrome 浏览器。"}],"provider":"tokenhub","model":"deepseek-v4-flash-202605"}],"stopReason":"stop"}
        """

        let parsed = LocalAgentCLIOutputParser.parse(output)

        XCTAssertEqual(parsed.text, "已打开 Google Chrome 浏览器。")
        XCTAssertNil(parsed.errorMessage)
    }

    func testLocalAgentCLIEventNormalizerConvertsPiNDJSONIntoTraceEvents() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let output = """
        {"type":"session","id":"session-1","cwd":"/tmp/voxflow"}
        {"type":"agent_start"}
        {"type":"message_start","message":{"role":"user","content":[{"type":"text","text":"你是 VoxFlow 触发的本机 pi agent runtime。用户语音指令：生成一个 HTML。"}]}}
        {"type":"message_end","message":{"role":"assistant","content":[{"type":"text","text":"已创建 index.html。"}]}}
        """
        let normalizer = LocalAgentCLIEventNormalizer(providerName: "Pi Agent", now: { start.addingTimeInterval(1) })

        let events = normalizer.normalize(stdout: output, stderr: "", startedAt: start)

        XCTAssertEqual(events.map(\.kind), [.toolProgress, .toolProgress, .modelDelta])
        XCTAssertEqual(events.last?.detail, "已创建 index.html。")
        XCTAssertFalse(events.contains { $0.detail?.contains("用户语音指令") == true })
    }

    func testLocalAgentRuntimeTraceIncludesParsedCLIEvents() async throws {
        let root = try makeTemporaryDirectory()
        let cli = root.appendingPathComponent("pi")
        try """
        #!/bin/sh
        cat >/dev/null
        echo '{"type":"session","id":"session-1","cwd":"\(root.path)"}'
        echo '{"type":"message_end","message":{"role":"assistant","content":[{"type":"text","text":"已创建 index.html。"}]}}'
        echo '{"type":"result","is_error":false,"result":"已创建 index.html。"}'
        exit 0
        """.write(to: cli, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: cli.path)
        let request = AgentRuntimeRequest(
            taskID: "task-1",
            instruction: "生成一个 HTML。",
            context: nil,
            target: nil,
            workspace: AgentRuntimeSessionWorkspace(
                taskID: "task-1",
                rootDirectory: root,
                sessionDirectory: root,
                screenshotsDirectory: root,
                tracesDirectory: root,
                temporaryDirectory: root
            ),
            screenContext: nil,
            model: "deepseek-v4-flash-202605"
        )
        let client = LocalAgentCLIRuntimeClient(descriptor: AgentProviderRegistry.pi)

        let result = try await client.run(
            request: request,
            cliPath: cli.path,
            cliVersion: nil,
            onEvent: { _ in }
        )

        XCTAssertEqual(result.summary, "已创建 index.html。")
        XCTAssertTrue(result.trace.events.count >= 4)
        XCTAssertTrue(result.trace.events.contains { $0.title == "Pi Agent 会话已创建" })
        XCTAssertTrue(result.trace.events.contains { $0.detail == "已创建 index.html。" })
    }

    func testPiRuntimeArgumentsInheritDefaultTools() {
        XCTAssertEqual(
            localAgentRuntimeArguments(
                for: AgentProviderRegistry.pi,
                model: "deepseek-v4-flash-202605"
            ),
            [
                "--print", "--mode", "json",
                "--model", "deepseek-v4-flash-202605"
            ]
        )
    }

    func testLocalAgentRuntimePromptRequiresArtifactsToBeWrittenToWorkspace() async throws {
        let root = try makeTemporaryDirectory()
        let cli = root.appendingPathComponent("pi")
        let promptFile = root.appendingPathComponent("prompt.txt")
        try """
        #!/bin/sh
        cat > "\(promptFile.path)"
        echo '{"type":"result","is_error":false,"result":"已完成"}'
        exit 0
        """.write(to: cli, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: cli.path)
        let workspace = AgentRuntimeSessionWorkspace(
            taskID: "task-1",
            rootDirectory: root,
            sessionDirectory: root,
            screenshotsDirectory: root,
            tracesDirectory: root,
            temporaryDirectory: root
        )
        let request = AgentRuntimeRequest(
            taskID: "task-1",
            instruction: "生成一个 HTML。",
            context: nil,
            target: nil,
            workspace: workspace,
            screenContext: nil,
            model: "deepseek-v4-flash-202605"
        )
        let client = LocalAgentCLIRuntimeClient(descriptor: AgentProviderRegistry.pi)

        let result = try await client.run(
            request: request,
            cliPath: cli.path,
            cliVersion: nil,
            onEvent: { _ in }
        )

        let prompt = try String(contentsOf: promptFile, encoding: .utf8)
        XCTAssertEqual(result.summary, "已完成")
        XCTAssertTrue(prompt.contains("必须在当前工作目录或其子目录落盘对应文件"))
        XCTAssertTrue(prompt.contains("不要只口头说明已完成"))
    }

    func testOpenCodeRuntimeArgumentsPinWorkingDirectory() {
        XCTAssertEqual(
            localAgentRuntimeArguments(
                for: AgentProviderRegistry.opencode,
                model: "opencode/deepseek-v4-flash-free",
                workingDirectory: "/tmp/voxflow-session"
            ),
            [
                "run", "--format", "json",
                "--dir", "/tmp/voxflow-session",
                "--model", "opencode/deepseek-v4-flash-free"
            ]
        )
    }

    func testCodeBuddyRuntimeArgumentsBypassNonInteractivePermissionPrompts() {
        XCTAssertEqual(
            localAgentRuntimeArguments(
                for: AgentProviderRegistry.codebuddy,
                model: "glm-5.2"
            ),
            [
                "--print", "-y", "--output-format", "json",
                "--model", "glm-5.2"
            ]
        )
    }

    func testClaudeRuntimeArgumentsUseCLISelectedDefaultModel() {
        XCTAssertEqual(
            localAgentRuntimeArguments(
                for: AgentProviderRegistry.claude,
                model: "sonnet"
            ),
            [
                "--print",
                "--output-format", "json",
                "--permission-mode", "bypassPermissions",
                "--disable-slash-commands",
                "--no-session-persistence"
            ]
        )
    }

    func testSelfTargetContextDoesNotCaptureRuntimeScreenshot() {
        let context = ContextSnapshot(
            windowTitle: "VoxFlow",
            targetAppBundleID: ProductBrand.bundleIdentifier + ".dev",
            targetAppName: "码上写 Dev",
            visualContentAvailable: false,
            sources: [.windowMetadata],
            warnings: ["self_target_context_skipped"]
        )
        let target = DictationTarget(
            bundleID: ProductBrand.bundleIdentifier + ".dev",
            appName: "码上写 Dev",
            pid: Int(ProcessInfo.processInfo.processIdentifier),
            windowTitle: "VoxFlow"
        )

        XCTAssertFalse(DefaultAgentRuntimeService.shouldCaptureScreenImage(context: context, target: target))
    }

    func testProxySensitiveLocalAgentChildEnvironmentDropsProxyVariables() {
        for descriptor in [AgentProviderRegistry.codebuddy, AgentProviderRegistry.pi] {
            let environment = localAgentChildEnvironment(
                for: descriptor,
                base: [
                    "PATH": "/usr/bin",
                    "HTTP_PROXY": "http://127.0.0.1:8080",
                    "HTTPS_PROXY": "http://127.0.0.1:8080",
                    "ALL_PROXY": "http://127.0.0.1:8080",
                    "NO_PROXY": "127.0.0.1",
                    "http_proxy": "http://127.0.0.1:8080"
                ]
            )

            XCTAssertEqual(environment["PATH"], "/usr/bin")
            XCTAssertNil(environment["HTTP_PROXY"])
            XCTAssertNil(environment["HTTPS_PROXY"])
            XCTAssertNil(environment["ALL_PROXY"])
            XCTAssertNil(environment["NO_PROXY"])
            XCTAssertNil(environment["http_proxy"])
        }
    }

    func testCodexRuntimeClientTimesOutWhenAppServerDoesNotRespond() async throws {
        let root = try makeTemporaryDirectory()
        let cli = root.appendingPathComponent("codex")
        try """
        #!/bin/sh
        if [ "$1" = "app-server" ] && [ "$2" = "--stdio" ]; then
          sleep 10
          exit 0
        fi
        exit 1
        """.write(to: cli, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: cli.path)
        let client = CodexRuntimeClient(timeoutSeconds: 0.1)
        let request = AgentRuntimeRequest(
            taskID: "timeout-task",
            instruction: "生成一个 HTML",
            context: nil,
            target: nil,
            workspace: AgentRuntimeSessionWorkspace(
                taskID: "timeout-task",
                rootDirectory: root,
                sessionDirectory: root,
                screenshotsDirectory: root,
                tracesDirectory: root,
                temporaryDirectory: root
            ),
            screenContext: nil,
            model: nil
        )

        let started = Date()
        do {
            _ = try await client.run(
                request: request,
                cliPath: cli.path,
                cliVersion: nil,
                onEvent: { _ in }
            )
            XCTFail("Expected Codex runtime timeout")
        } catch AgentRuntimeClientError.failed(let trace) {
            XCTAssertEqual(trace.status, .failed)
            XCTAssertTrue(trace.failureReason?.contains("timeout") == true)
        }
        XCTAssertLessThan(Date().timeIntervalSince(started), 2)
    }

    func testOtherLocalAgentChildEnvironmentPreservesProxyVariables() {
        let environment = localAgentChildEnvironment(
            for: AgentProviderRegistry.opencode,
            base: [
                "PATH": "/usr/bin",
                "HTTPS_PROXY": "http://127.0.0.1:8080"
            ]
        )

        XCTAssertEqual(environment["HTTPS_PROXY"], "http://127.0.0.1:8080")
    }

    func testLocalAgentRuntimeOutputTreatsEmptyStdoutWithStderrAsFailure() {
        XCTAssertThrowsError(
            try localAgentRuntimeOutputOrThrow(
                stdout: "",
                stderr: "502 unable to verify the first certificate",
                terminationStatus: 0
            )
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("unable to verify the first certificate"))
        }
    }

    func testLocalAgentRuntimeOutputRemovesEchoedPromptFromDisplayedResult() throws {
        let prompt = """
        你是 VoxFlow 触发的本机 pi agent runtime。

        用户语音指令：
        创建一个 HTML 文件。

        屏幕上下文：
        可见文本：
        Codex 对话和 diff

        完成后用一句话总结你实际完成了什么。
        """
        let output = "\(prompt)\n\n\(prompt)\n\n已创建 index.html。"

        let result = try localAgentRuntimeOutputOrThrow(
            stdout: output,
            stderr: "",
            terminationStatus: 0,
            prompt: prompt
        )

        XCTAssertEqual(result, "已创建 index.html。")
    }

    func testLocalAgentRuntimeOutputDoesNotDisplayPromptWhenOnlyEchoed() throws {
        let prompt = """
        你是 VoxFlow 触发的本机 pi agent runtime。

        用户语音指令：
        创建一个 HTML 文件。
        """

        let result = try localAgentRuntimeOutputOrThrow(
            stdout: "\(prompt)\n\n\(prompt)",
            stderr: "",
            terminationStatus: 0,
            prompt: prompt
        )

        XCTAssertEqual(result, "")
    }

    func testLocalAgentRuntimeOutputRejectsClarificationQuestion() {
        let output = """
        语音指令“生成一个 HTML”需要更具体的描述才能执行。请问你想生成什么样的 HTML?
        """

        XCTAssertThrowsError(
            try localAgentRuntimeOutputOrThrow(
                stdout: output,
                stderr: "",
                terminationStatus: 0
            )
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("请求澄清"))
            XCTAssertFalse(error.localizedDescription.contains("请问你想生成什么样"))
        }
    }

    func testLocalAgentRuntimeOutputClarificationDetectorAllowsCompletedQuestionContent() {
        XCTAssertFalse(localAgentRuntimeOutputRequestsClarification("已创建 faq.html，页面包含常见问题列表。"))
        XCTAssertTrue(localAgentRuntimeOutputRequestsClarification("需要更多信息。请告诉我你希望生成什么样的页面？"))
    }

    func testCodexRuntimeDetectorUsesSixtySecondCacheAndForceRefresh() async throws {
        let root = try makeTemporaryDirectory()
        let cli = root.appendingPathComponent("codex")
        let counter = root.appendingPathComponent("count")
        try """
        #!/bin/sh
        count=0
        if [ -f "\(counter.path)" ]; then
          count=$(cat "\(counter.path)")
        fi
        count=$((count + 1))
        echo "$count" > "\(counter.path)"
        if [ "$1" = "--version" ]; then
          echo "codex-cli 9.9.9"
          exit 0
        fi
        if [ "$1" = "app-server" ]; then
          echo "codex app-server"
          exit 0
        fi
        exit 1
        """.write(to: cli, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: cli.path)

        let clock = MutableAgentRuntimeClock(now: Date(timeIntervalSince1970: 1_800_000_000))
        let detector = CodexRuntimeAvailabilityDetector(
            configuration: CodexRuntimeDetectorConfiguration(
                providerID: "codex",
                cacheTTL: 60,
                candidateCLIPaths: [cli.path]
            ),
            clock: clock
        )

        let first = await detector.cachedOrDetect(forceRefresh: false)
        let second = await detector.cachedOrDetect(forceRefresh: false)
        XCTAssertTrue(first.isAvailable)
        XCTAssertEqual(second.cliVersion, "codex-cli 9.9.9")
        XCTAssertEqual(try String(contentsOf: counter, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines), "2")

        let refreshed = await detector.cachedOrDetect(forceRefresh: true)
        XCTAssertTrue(refreshed.isAvailable)
        XCTAssertEqual(try String(contentsOf: counter, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines), "4")

        clock.now = clock.now.addingTimeInterval(61)
        _ = await detector.cachedOrDetect(forceRefresh: false)
        XCTAssertEqual(try String(contentsOf: counter, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines), "6")
    }

    func testWorkspaceManagerCreatesSessionAndPreservesUserModifiedAgentsFile() throws {
        let root = try makeTemporaryDirectory()
        let manager = AgentRuntimeWorkspaceManager(rootDirectory: root)

        let workspace = try manager.prepareSession(taskID: "task-1")

        XCTAssertTrue(FileManager.default.fileExists(atPath: workspace.sessionDirectory.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: workspace.screenshotsDirectory.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: workspace.tracesDirectory.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: workspace.temporaryDirectory.path))
        let agents = root.appendingPathComponent("AGENTS.md")
        let sessionAgents = workspace.sessionDirectory.appendingPathComponent("AGENTS.md")
        let managedContent = try String(contentsOf: agents, encoding: .utf8)
        let sessionManagedContent = try String(contentsOf: sessionAgents, encoding: .utf8)
        XCTAssertTrue(managedContent.hasPrefix(AgentRuntimeWorkspaceManager.managedAgentsMarker))
        XCTAssertTrue(sessionManagedContent.hasPrefix(AgentRuntimeWorkspaceManager.managedAgentsMarker))
        XCTAssertFalse(managedContent.localizedCaseInsensitiveContains("delete禁止"))

        try "user notes".write(to: agents, atomically: true, encoding: .utf8)
        try manager.ensureManagedAgentsFile()

        XCTAssertEqual(try String(contentsOf: agents, encoding: .utf8), "user notes")
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("AGENTS.md.new").path))
    }

    func testWorkspaceManagerArtifactsAreScopedToCurrentSession() throws {
        let root = try makeTemporaryDirectory()
        let manager = AgentRuntimeWorkspaceManager(rootDirectory: root)
        let workspace = try manager.prepareSession(taskID: "task-1")
        let staleRootArtifact = root.appendingPathComponent("old.html")
        let ignoredScreenshot = workspace.screenshotsDirectory.appendingPathComponent("screen.png")
        try "<html>old</html>".write(to: staleRootArtifact, atomically: true, encoding: .utf8)

        let snapshot = manager.artifactSnapshot(workspace: workspace)

        try "png".write(to: ignoredScreenshot, atomically: true, encoding: .utf8)
        let sessionArtifact = workspace.sessionDirectory.appendingPathComponent("result.html")
        try "<html>new</html>".write(to: sessionArtifact, atomically: true, encoding: .utf8)
        let temporaryArtifact = workspace.temporaryDirectory.appendingPathComponent("index.html")
        try "<html>tmp</html>".write(to: temporaryArtifact, atomically: true, encoding: .utf8)

        let artifacts = manager.artifactsModified(since: snapshot, workspace: workspace)

        XCTAssertEqual(
            Set(artifacts.map { URL(fileURLWithPath: $0.path).resolvingSymlinksInPath().path }),
            Set([
                temporaryArtifact.resolvingSymlinksInPath().path,
                sessionArtifact.resolvingSymlinksInPath().path
            ])
        )
    }

    func testRuntimeServiceAttachesArtifactsToFailedTrace() async throws {
        let root = try makeTemporaryDirectory()
        let manager = AgentRuntimeWorkspaceManager(rootDirectory: root)
        let service = DefaultAgentRuntimeService(
            detector: StaticAgentRuntimeDetector(availability: AgentRuntimeAvailability(
                providerID: AgentProviderRegistry.codex.providerID,
                status: .available,
                detectedAt: Date(timeIntervalSince1970: 1_800_000_000),
                expiresAt: Date(timeIntervalSince1970: 1_800_000_060),
                cliPath: "/bin/echo",
                cliVersion: "echo"
            )),
            workspaceManager: manager,
            client: ArtifactWritingFailingRuntimeClient()
        )

        do {
            _ = try await service.runIfAvailable(
                taskID: "task-1",
                instruction: "生成一个 HTML",
                context: nil,
                target: nil,
                model: nil,
                onEvent: { _ in }
            )
            XCTFail("Expected runtime failure")
        } catch AgentRuntimeClientError.failed(let trace) {
            XCTAssertEqual(trace.status, .failed)
            XCTAssertEqual(trace.artifacts.map(\.summary), ["index.html"])
            let artifactPath = try XCTUnwrap(trace.artifacts.first?.path)
            XCTAssertTrue(FileManager.default.fileExists(atPath: artifactPath))
            XCTAssertTrue(artifactPath.contains("/tmp/index.html"))
        }
    }

    func testRuntimeServiceCleansManagedFilesBeforePreparingSession() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let root = try makeTemporaryDirectory()
        let manager = AgentRuntimeWorkspaceManager(rootDirectory: root, now: { now })
        try manager.prepareRoot()
        let sessions = root.appendingPathComponent("sessions", isDirectory: true)
        let staleSession = sessions.appendingPathComponent("stale-task", isDirectory: true)
        try FileManager.default.createDirectory(at: staleSession, withIntermediateDirectories: true)
        try FileManager.default.setAttributes(
            [.modificationDate: now.addingTimeInterval(-8 * 24 * 60 * 60)],
            ofItemAtPath: staleSession.path
        )
        let service = DefaultAgentRuntimeService(
            detector: StaticAgentRuntimeDetector(availability: AgentRuntimeAvailability(
                providerID: AgentProviderRegistry.codex.providerID,
                status: .available,
                detectedAt: now,
                expiresAt: now.addingTimeInterval(60),
                cliPath: "/bin/echo",
                cliVersion: "echo"
            )),
            workspaceManager: manager,
            client: SuccessfulRuntimeClient()
        )

        _ = try await service.runIfAvailable(
            taskID: "fresh-task",
            instruction: "整理文字",
            context: nil,
            target: nil,
            model: nil,
            onEvent: { _ in }
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: staleSession.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sessions.appendingPathComponent("fresh-task").path))
    }

    func testWorkspaceManagerCleansTemporaryFilesAndManagedRetention() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let root = try makeTemporaryDirectory()
        let manager = AgentRuntimeWorkspaceManager(rootDirectory: root, now: { now })
        let workspace = try manager.prepareSession(taskID: "task-1")
        let tempFile = workspace.temporaryDirectory.appendingPathComponent("scratch.txt")
        try "tmp".write(to: tempFile, atomically: true, encoding: .utf8)

        manager.cleanupSessionTemporaryFiles(workspace)

        XCTAssertFalse(FileManager.default.fileExists(atPath: tempFile.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: workspace.temporaryDirectory.path))

        let screenshots = root.appendingPathComponent("screenshots", isDirectory: true)
        let recent = screenshots.appendingPathComponent("recent.png")
        let old = screenshots.appendingPathComponent("old.png")
        try "recent".write(to: recent, atomically: true, encoding: .utf8)
        try "old".write(to: old, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: recent.path)
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-8 * 24 * 60 * 60)], ofItemAtPath: old.path)

        manager.cleanupManagedFiles(keepingRecent: 100, newerThan: 7 * 24 * 60 * 60)

        XCTAssertTrue(FileManager.default.fileExists(atPath: recent.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: old.path))
    }

    func testCodexModelListKeepsTextOnlySparkModels() throws {
        let data = """
        {"id":2,"result":{"data":[{"id":"gpt-5.5","hidden":false,"inputModalities":["text","image"]},{"id":"gpt-5.3-spark","hidden":false,"inputModalities":["text"]},{"id":"hidden-model","hidden":true,"inputModalities":["text"]}]}}
        """.data(using: .utf8)!

        let models = CodexRuntimeModelListProvider.parseModelList(from: data)

        XCTAssertEqual(models, ["gpt-5.5", "gpt-5.3-spark"])
    }

    func testSparkModelDoesNotReceiveImageInput() {
        XCTAssertFalse(CodexRuntimeClient.supportsImageInput(modelID: "gpt-5.3-spark"))
        XCTAssertTrue(CodexRuntimeClient.supportsImageInput(modelID: "gpt-5.5"))
        XCTAssertTrue(CodexRuntimeClient.supportsImageInput(modelID: nil))
    }

    func testCodexEventNormalizerMapsPermissionAndTokenEvents() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let normalizer = CodexEventNormalizer(now: { start.addingTimeInterval(0.25) })

        let permission = normalizer.normalize(
            CodexRuntimeRawEvent(
                method: "item/permissions/requestApproval",
                params: ["message": "需要打开浏览器", "tool": "open_url"]
            ),
            startedAt: start
        )
        XCTAssertEqual(permission?.title, "等待授权")
        XCTAssertEqual(normalizer.status(after: permission!), .waitingForPermission)
        XCTAssertEqual(normalizer.hudStage(after: permission!), .runtimeWaitingForPermission(summary: "需要打开浏览器"))

        let token = normalizer.normalize(
            CodexRuntimeRawEvent(
                method: "thread/tokenUsage/updated",
                params: ["summary": "输入 10 tokens，输出 2 tokens"]
            ),
            startedAt: start
        )
        XCTAssertEqual(token?.kind, .tokenUsageUpdated)
        XCTAssertEqual(token?.elapsedMS, 250)
        XCTAssertEqual(normalizer.hudStage(after: token!), .runtimeProcessing(summary: nil))
    }

    func testCodexEventNormalizerCarriesReadableHUDSummary() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let normalizer = CodexEventNormalizer(now: { start.addingTimeInterval(0.1) })

        let planning = normalizer.normalize(
            CodexRuntimeRawEvent(
                method: "turn/started",
                params: [:]
            ),
            startedAt: start
        )

        XCTAssertEqual(
            planning.map { normalizer.hudStage(after: $0) },
            .runtimeProcessing(summary: nil)
        )
    }

    func testCodexEventNormalizerTreatsRetryingErrorsAsWarningsAndCommandsAsToolEvents() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let normalizer = CodexEventNormalizer(now: { start })

        let retrying = normalizer.normalize(
            CodexRuntimeRawEvent(
                method: "error",
                params: ["message": "Reconnecting... 2/5", "willRetry": "true"]
            ),
            startedAt: start
        )
        XCTAssertEqual(retrying?.kind, .warning)
        XCTAssertEqual(normalizer.status(after: retrying!), .running)
        XCTAssertEqual(normalizer.hudStage(after: retrying!), .runtimeProcessing(summary: nil))

        let technicalPayload = normalizer.normalize(
            CodexRuntimeRawEvent(
                method: "item/agentMessage/delta",
                params: ["delta": #"{"message":"Reconnecting...","codexErrorInfo":{}}"#]
            ),
            startedAt: start
        )
        XCTAssertEqual(normalizer.hudStage(after: technicalPayload!), .runtimeProcessing(summary: nil))

        let pathDelta = normalizer.normalize(
            CodexRuntimeRawEvent(
                method: "item/agentMessage/delta",
                params: ["delta": "/Users/counter/Library/Application Support/VoxFlow/AgentRuntime/output.pptx"]
            ),
            startedAt: start
        )
        XCTAssertEqual(normalizer.hudStage(after: pathDelta!), .runtimeProcessing(summary: nil))

        let commandStarted = normalizer.normalize(
            CodexRuntimeRawEvent(
                method: "item/started",
                params: ["type": "commandExecution", "command": "echo hello"]
            ),
            startedAt: start
        )
        XCTAssertEqual(commandStarted?.kind, .toolRequested)
        XCTAssertEqual(commandStarted?.toolName, "shell")
        XCTAssertEqual(normalizer.hudStage(after: commandStarted!), .runtimeOperating(summary: nil))

        let commandCompleted = normalizer.normalize(
            CodexRuntimeRawEvent(
                method: "item/completed",
                params: [
                    "type": "commandExecution",
                    "status": "completed",
                    "aggregatedOutput": "hello\n"
                ]
            ),
            startedAt: start
        )
        XCTAssertEqual(commandCompleted?.kind, .toolResolved)
        XCTAssertEqual(commandCompleted?.detail, "hello\n")
    }

    func testCodexEventNormalizerMapsPermissionDenialToFailure() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let normalizer = CodexEventNormalizer(now: { start })

        let denied = normalizer.normalize(
            CodexRuntimeRawEvent(
                method: "serverRequest/resolved",
                params: ["tool": "shell", "result": "denied by user"]
            ),
            startedAt: start
        )

        XCTAssertEqual(denied?.kind, .error)
        XCTAssertEqual(denied?.title, "授权被拒绝")
        XCTAssertEqual(denied?.isFailure, true)
        XCTAssertEqual(normalizer.status(after: denied!), .failed)
    }

    func testAgentActionTraceCodableAndSafePersistenceAvoidsRawImagePayload() throws {
        let trace = AgentActionTrace(
            providerID: "codex",
            executionMode: .codexRuntime,
            status: .completed,
            userInstruction: "打开页面",
            screenContext: ScreenContextSnapshot(
                thumbnailPath: "/tmp/screen.png",
                imagePath: "/tmp/screen.png",
                appName: "Safari",
                bundleID: "com.apple.Safari",
                windowTitle: "Example",
                capturedAt: Date(timeIntervalSince1970: 1_800_000_000)
            ),
            events: [
                AgentActionEvent(
                    kind: .toolResolved,
                    title: "工具完成",
                    detail: "Opened URL",
                    timestamp: Date(timeIntervalSince1970: 1_800_000_001)
                )
            ],
            resultSummary: "已打开",
            model: "gpt-5.5",
            tokenUsage: AgentTokenUsage(inputTokens: 10, outputTokens: 2, totalTokens: 12),
            startedAt: Date(timeIntervalSince1970: 1_800_000_000),
            completedAt: Date(timeIntervalSince1970: 1_800_000_001)
        )

        let encoded = try JSONEncoder().encode(trace.safeForPersistence())
        let json = try XCTUnwrap(String(data: encoded, encoding: .utf8))
        let decoded = try JSONDecoder().decode(AgentActionTrace.self, from: encoded)

        XCTAssertEqual(decoded, trace)
        XCTAssertEqual(decoded.screenContext?.imagePath, "/tmp/screen.png")
        XCTAssertFalse(json.contains("data:image"))
        XCTAssertFalse(json.contains("base64"))
    }

    func testOldAgentActionTraceDecodesWithEmptyArtifacts() throws {
        let json = """
        {
          "schemaVersion": 1,
          "providerID": "codex",
          "executionMode": "codexRuntime",
          "status": "completed",
          "userInstruction": "打开页面",
          "events": [],
          "startedAt": "2027-01-15T08:00:00Z"
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let trace = try decoder.decode(AgentActionTrace.self, from: Data(json.utf8))

        XCTAssertEqual(trace.artifacts, [])
        XCTAssertEqual(trace.executionMode, .codexRuntime)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("voxflow-agent-runtime-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }

    private func waitUntilProcessExits(pid: Int32, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if kill(pid, 0) != 0 && errno == ESRCH {
                return true
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return kill(pid, 0) != 0 && errno == ESRCH
    }
}

private extension Optional {
    func unwrap(file: StaticString = #filePath, line: UInt = #line) throws -> Wrapped {
        guard let value = self else {
            XCTFail("Expected non-nil value", file: file, line: line)
            throw NSError(domain: "AgentRuntimeTests", code: 1)
        }
        return value
    }
}

private struct StaticAgentRuntimeDetector: AgentRuntimeAvailabilityDetecting {
    let availability: AgentRuntimeAvailability

    func cachedOrDetect(forceRefresh: Bool) async -> AgentRuntimeAvailability {
        availability
    }
}

private struct ArtifactWritingFailingRuntimeClient: AgentRuntimeClient {
    func run(
        request: AgentRuntimeRequest,
        cliPath: String,
        cliVersion: String?,
        onEvent: @escaping @Sendable (AgentActionEvent) -> Void
    ) async throws -> AgentRuntimeResult {
        let artifact = request.workspace.temporaryDirectory.appendingPathComponent("index.html")
        try "<html>created before timeout</html>".write(to: artifact, atomically: true, encoding: .utf8)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        throw AgentRuntimeClientError.failed(AgentActionTrace(
            providerID: AgentProviderRegistry.codex.providerID,
            executionMode: .codexRuntime,
            status: .failed,
            userInstruction: request.instruction,
            events: [
                AgentActionEvent(
                    kind: .error,
                    title: "Runtime failed",
                    detail: "runtime timed out",
                    timestamp: now,
                    isFailure: true
                )
            ],
            startedAt: now,
            completedAt: now,
            failureReason: "runtime timed out"
        ))
    }
}

private struct SuccessfulRuntimeClient: AgentRuntimeClient {
    func run(
        request: AgentRuntimeRequest,
        cliPath: String,
        cliVersion: String?,
        onEvent: @escaping @Sendable (AgentActionEvent) -> Void
    ) async throws -> AgentRuntimeResult {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        return AgentRuntimeResult(
            summary: "完成",
            status: .completed,
            trace: AgentActionTrace(
                providerID: AgentProviderRegistry.codex.providerID,
                executionMode: .codexRuntime,
                status: .completed,
                userInstruction: request.instruction,
                events: [],
                resultSummary: "完成",
                model: request.model,
                startedAt: now,
                completedAt: now
            )
        )
    }
}

private final class MutableAgentRuntimeClock: AppClock, @unchecked Sendable {
    var now: Date

    init(now: Date) {
        self.now = now
    }

    func sleep(nanoseconds: UInt64) async throws {}
}
