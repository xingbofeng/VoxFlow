import XCTest
@testable import VoxFlowApp

final class AgentRuntimeTests: XCTestCase {
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
        let managedContent = try String(contentsOf: agents, encoding: .utf8)
        XCTAssertTrue(managedContent.hasPrefix(AgentRuntimeWorkspaceManager.managedAgentsMarker))
        XCTAssertFalse(managedContent.localizedCaseInsensitiveContains("delete禁止"))

        try "user notes".write(to: agents, atomically: true, encoding: .utf8)
        try manager.ensureManagedAgentsFile()

        XCTAssertEqual(try String(contentsOf: agents, encoding: .utf8), "user notes")
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("AGENTS.md.new").path))
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

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("voxflow-agent-runtime-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }
}

private final class MutableAgentRuntimeClock: AppClock, @unchecked Sendable {
    var now: Date

    init(now: Date) {
        self.now = now
    }

    func sleep(nanoseconds: UInt64) async throws {}
}
