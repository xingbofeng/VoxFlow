import VoxFlowASRCore
import VoxFlowAudio
@testable import VoxFlowProviderR2T2
import XCTest

/// R2T2 稳定前缀会话的行为测试。
///
/// 全部使用确定性 fake engine，不加载真实模型：R2T2 的产品契约是“只把已确认文本交给 HUD”，
/// 这一契约由 session 对 engine 增量的映射决定，与模型权重无关。
final class R2T2ASRSessionTests: XCTestCase {
    /// R2T2 每一步只提交解码结果去掉 `unfixedTokens` 个 token 之后的部分，扣下的尾巴过去完全不出
    /// driver，HUD 因此恒定落后一个 token（中文表现为「最后一个字不显示，也不实时更新」）。
    ///
    /// 现在这条尾巴走 `unstableSuffix` 实时预览：`stablePrefix` 仍然只增长、不回滚，尾巴只是预览，
    /// 可以被下一步改写。
    func testPartialEventsCarryThePendingTailAsUnstableSuffix() async throws {
        let engine = ScriptedR2T2Stream(
            pushResults: [["你好"], ["，世界"]],
            finishResult: "！",
            pendingResults: ["好", "界"]
        )
        let session = Self.makeSession(engine: engine)
        let collector = Self.collectEvents(from: session)

        try await session.start()
        try await session.accept(Self.frame(sequenceNumber: 1))
        try await session.accept(Self.frame(sequenceNumber: 2))
        try await session.finish()

        let events = await collector.value
        let partials = events.compactMap(\.partialTranscript)
        XCTAssertEqual(
            partials.map(\.stablePrefix),
            ["你好", "你好，世界"],
            "stablePrefix 必须是截至当前的完整已确认文本，且单调增长"
        )
        XCTAssertEqual(
            partials.map(\.unstableSuffix),
            ["好", "界"],
            "被回滚、尚未确认的尾巴必须走 unstableSuffix 交给 HUD 预览"
        )
        XCTAssertEqual(partials.map(\.revision), partials.map(\.revision).sorted(), "revision 必须单调递增")
    }

    /// 待定尾巴只是预览：它永远不能进入最终文本。
    func testThePendingTailNeverReachesTheFinalText() async throws {
        let engine = ScriptedR2T2Stream(
            pushResults: [["你好"]],
            finishResult: "！",
            pendingResults: ["好"]
        )
        let session = Self.makeSession(engine: engine)
        let collector = Self.collectEvents(from: session)

        try await session.start()
        try await session.accept(Self.frame(sequenceNumber: 1))
        try await session.finish()

        let events = await collector.value
        XCTAssertEqual(
            events.compactMap(\.finalText),
            ["你好！"],
            "final 必须只包含已确认文本，待定尾巴不得渗入"
        )
    }

    /// 说话人正停在待定尾巴上时 `push` 不再产生新的已确认增量，但尾巴本身仍在推进——预览必须跟着更新，
    /// 否则 HUD 仍会「不实时更新」。
    func testAPendingTailChangeAloneStillUpdatesThePreview() async throws {
        let engine = ScriptedR2T2Stream(
            pushResults: [[], []],
            finishResult: "你好",
            pendingResults: ["你", "你好"]
        )
        let session = Self.makeSession(engine: engine)
        let collector = Self.collectEvents(from: session)

        try await session.start()
        try await session.accept(Self.frame(sequenceNumber: 1))
        try await session.accept(Self.frame(sequenceNumber: 2))
        try await session.finish()

        let events = await collector.value
        let partials = events.compactMap(\.partialTranscript)
        XCTAssertEqual(partials.map(\.stablePrefix), ["", ""], "这两帧没有新的已确认文本")
        XCTAssertEqual(
            partials.map(\.unstableSuffix),
            ["你", "你好"],
            "没有新确认文本时，待定尾巴的变化也必须刷新预览"
        )
    }

    func testFinishEmitsExactlyOneFinalWithFullCommittedText() async throws {
        let engine = ScriptedR2T2Stream(pushResults: [["你好"], ["，世界"]], finishResult: "！")
        let session = Self.makeSession(engine: engine)
        let collector = Self.collectEvents(from: session)

        try await session.start()
        try await session.accept(Self.frame(sequenceNumber: 1))
        try await session.accept(Self.frame(sequenceNumber: 2))
        try await session.finish()

        let events = await collector.value
        let finals = events.compactMap(\.finalText)
        XCTAssertEqual(finals, ["你好，世界！"], "finish 必须且只能产生一个 final，文本为全部已确认内容")
    }

    func testCancelEmitsCancelledFailureWithoutFinalOrText() async throws {
        let engine = ScriptedR2T2Stream(pushResults: [["你好"]], finishResult: "！")
        let session = Self.makeSession(engine: engine)
        let collector = Self.collectEvents(from: session)

        try await session.start()
        try await session.accept(Self.frame(sequenceNumber: 1))
        await session.cancel()

        let events = await collector.value
        XCTAssertTrue(events.compactMap(\.finalText).isEmpty, "cancel 不得产生 final 文本")
        XCTAssertEqual(engine.cancelCount, 1, "cancel 必须停止上游 core")
        let failures = events.compactMap(\.failureCategory)
        XCTAssertEqual(failures, [.cancelled])
    }

    /// `start()` 要等模型加载完才挂载 driver。加载期间被取消时，driver 不能留在 session 里，
    /// 也不能在 cancellation 之后补发 ready。
    func testCancelDuringStartupDiscardsTheDriverAndNeverEmitsReady() async {
        let engine = ScriptedR2T2Stream(pushResults: [], finishResult: "")
        let factory = GatedR2T2StreamFactory(engine: engine)
        let session = Self.makeSession(streamFactory: factory)
        let collector = Self.collectEvents(from: session)

        let start = Task { try await session.start() }
        await factory.waitUntilEntered()
        await session.cancel()
        factory.release()
        _ = try? await start.value

        let events = await collector.value
        XCTAssertFalse(
            events.contains { if case .ready = $0 { return true } else { return false } },
            "启动期间被取消的 session 不得发出 ready"
        )
        XCTAssertEqual(engine.cancelCount, 1, "在途 driver 必须被取消，不能泄漏在 session 里")
        XCTAssertEqual(events.compactMap(\.failureCategory), [.cancelled])
    }

    /// final 之后 session 仍需释放 driver（上游 stream 连同 KV cache 一起释放），
    /// 因此随后的 cancel 只做清理，不再产生第二个事件。
    func testFinishReleasesTheDriverSoCancelStopsTheCoreExactlyOnce() async throws {
        let engine = ScriptedR2T2Stream(pushResults: [["你好"]], finishResult: "！")
        let session = Self.makeSession(engine: engine)
        let collector = Self.collectEvents(from: session)

        try await session.start()
        try await session.accept(Self.frame(sequenceNumber: 1))
        try await session.finish()
        await session.cancel()

        let events = await collector.value
        XCTAssertEqual(events.compactMap(\.finalText), ["你好！"])
        XCTAssertEqual(engine.cancelCount, 1, "driver 必须被释放一次，且只释放一次")
        XCTAssertTrue(
            events.compactMap(\.failureCategory).isEmpty,
            "已经发过 final 的 session 不再发 cancellation"
        )
    }

    func testContextPromptIsForwardedToStreamFactory() async throws {        let factory = CapturingR2T2StreamFactory(
            engine: ScriptedR2T2Stream(pushResults: [], finishResult: "")
        )
        let session = R2T2ASRSession(
            sessionID: ASRSessionID(rawValue: "r2t2-context"),
            modelURL: URL(fileURLWithPath: "/tmp/r2t2", isDirectory: true),
            languageHint: "zh",
            streamFactory: factory
        )
        try await session.configurePrompt("码上写, VoxFlow")
        try await session.start()

        let prompts = factory.contextPrompts
        XCTAssertEqual(prompts, ["码上写, VoxFlow"])
    }

    func testEmptyFinalTranscriptEmitsFailureInsteadOfBlankFinal() async throws {
        let engine = ScriptedR2T2Stream(pushResults: [], finishResult: "   ")
        let session = Self.makeSession(engine: engine)
        let collector = Self.collectEvents(from: session)

        try await session.start()
        await XCTAssertThrowsErrorAsync { try await session.finish() }

        let events = await collector.value
        XCTAssertTrue(events.compactMap(\.finalText).isEmpty, "空结果不得产生 final")
        XCTAssertEqual(events.compactMap(\.failureCategory), [.emptyTranscript])
    }

    func testStreamCreationFailureEmitsFailureAndNeverBecomesReady() async {
        let session = Self.makeSession(
            streamFactory: FailingR2T2StreamFactory(error: R2T2ProviderError.modelNotInstalled)
        )
        let collector = Self.collectEvents(from: session)

        await XCTAssertThrowsErrorAsync { try await session.start() }

        let events = await collector.value
        XCTAssertEqual(events.compactMap(\.failureCategory), [.modelNotInstalled])
        XCTAssertFalse(
            events.contains { if case .ready = $0 { return true } else { return false } },
            "模型加载失败时不得发出 ready"
        )
    }

    // MARK: - Helpers

    private static func makeSession(engine: any R2T2StreamingEngine) -> R2T2ASRSession {
        makeSession(streamFactory: CapturingR2T2StreamFactory(engine: engine))
    }

    private static func makeSession(streamFactory: any R2T2StreamMaking) -> R2T2ASRSession {
        R2T2ASRSession(
            sessionID: ASRSessionID(rawValue: "r2t2-test"),
            modelURL: URL(fileURLWithPath: "/tmp/r2t2", isDirectory: true),
            languageHint: "zh",
            streamFactory: streamFactory
        )
    }

    private static func collectEvents(from session: any ASRSession) -> Task<[ASREvent], Never> {
        Task {
            var events: [ASREvent] = []
            for await event in session.events {
                events.append(event)
            }
            return events
        }
    }

    private static func frame(sequenceNumber: UInt64) -> AudioFrame {
        AudioFrame(
            sequenceNumber: sequenceNumber,
            startSample: 0,
            samples: ContiguousArray(repeating: 0.1, count: 32_000),
            sampleRate: 16_000,
            capturedAt: ContinuousClock.now
        )
    }
}

// MARK: - Fakes

/// 按脚本返回确定增量的 fake engine，用于验证 session 的映射行为。
final class ScriptedR2T2Stream: R2T2StreamingEngine, @unchecked Sendable {
    private let pushResults: [[String]]
    private let pendingResults: [String]
    private let finishResult: String
    private let lock = NSLock()
    private var pushIndex = 0
    private var committed = ""
    private var pending = ""
    private var cancels = 0

    init(pushResults: [[String]], finishResult: String, pendingResults: [String] = []) {
        self.pushResults = pushResults
        self.pendingResults = pendingResults
        self.finishResult = finishResult
    }

    var committedText: String { lock.withLock { committed } }

    var pendingText: String { lock.withLock { pending } }

    var detectedLanguage: String { "Chinese" }

    var cancelCount: Int { lock.withLock { cancels } }

    func push(_ samples: [Float]) -> [String] {
        lock.withLock {
            guard pushIndex < pushResults.count else { return [] }
            defer { pushIndex += 1 }
            let deltas = pushResults[pushIndex]
            committed += deltas.joined()
            if pushIndex < pendingResults.count { pending = pendingResults[pushIndex] }
            return deltas
        }
    }

    func finish() -> String {
        lock.withLock {
            // 冲刷尾部：final 会把待定尾巴一并确认掉，因此不再有待定内容。
            pending = ""
            committed += finishResult
            return finishResult
        }
    }

    func cancel() {
        lock.withLock { cancels += 1 }
    }
}

final class CapturingR2T2StreamFactory: R2T2StreamMaking, @unchecked Sendable {
    private let engine: any R2T2StreamingEngine
    private let lock = NSLock()
    private var recordedContextPrompts: [String?] = []
    private var recordedModelURLs: [URL] = []
    private var recordedLanguageHints: [String?] = []

    init(engine: any R2T2StreamingEngine) {
        self.engine = engine
    }

    var contextPrompts: [String?] { lock.withLock { recordedContextPrompts } }

    var modelURLs: [URL] { lock.withLock { recordedModelURLs } }

    var languageHints: [String?] { lock.withLock { recordedLanguageHints } }

    func makeStream(
        modelURL: URL,
        languageHint: String?,
        contextPrompt: String?
    ) async throws -> any R2T2StreamingEngine {
        lock.withLock {
            recordedModelURLs.append(modelURL)
            recordedLanguageHints.append(languageHint)
            recordedContextPrompts.append(contextPrompt)
        }
        return engine
    }
}

/// `makeStream` 一直挂起直到测试放行，用来把 `start()` 的 await 窗口拉长到可操作的宽度。
final class GatedR2T2StreamFactory: R2T2StreamMaking, @unchecked Sendable {
    private let engine: any R2T2StreamingEngine
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Never>?
    private var hasEntered = false

    init(engine: any R2T2StreamingEngine) {
        self.engine = engine
    }

    func waitUntilEntered() async {
        while !lock.withLock({ hasEntered }) {
            await Task.yield()
        }
    }

    func release() {
        let waiting = lock.withLock { () -> CheckedContinuation<Void, Never>? in
            let waiting = continuation
            continuation = nil
            return waiting
        }
        waiting?.resume()
    }

    func makeStream(
        modelURL: URL,
        languageHint: String?,
        contextPrompt: String?
    ) async throws -> any R2T2StreamingEngine {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.withLock {
                self.continuation = continuation
                hasEntered = true
            }
        }
        return engine
    }
}

// MARK: - Assertion helpers
extension ASREvent {
    var partialTranscript: PartialTranscript? {
        guard case .partial(_, let transcript) = self else { return nil }
        return transcript
    }

    var finalText: String? {
        guard case .final(_, _, let text) = self else { return nil }
        return text
    }

    var failureCategory: ASRErrorCategory? {
        guard case .failure(_, _, let error) = self else { return nil }
        return error.category
    }
}

func XCTAssertThrowsErrorAsync(
    _ expression: () async throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await expression()
        XCTFail("Expected an error to be thrown", file: file, line: line)
    } catch {
        // expected
    }
}

/// 模拟模型加载失败：makeStream 直接抛错。
final class FailingR2T2StreamFactory: R2T2StreamMaking, @unchecked Sendable {
    private let error: R2T2ProviderError

    init(error: R2T2ProviderError) {
        self.error = error
    }

    func makeStream(
        modelURL: URL,
        languageHint: String?,
        contextPrompt: String?
    ) async throws -> any R2T2StreamingEngine {
        throw error
    }
}
