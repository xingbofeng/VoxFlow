import XCTest
@testable import VoxFlowApp

@MainActor
final class TextProcessingPipelineTests: XCTestCase {
    func testDisabledRefinerReturnsOriginalText() async {
        let refiner = StubTextRefiner(isEnabled: false, isConfigured: true)
        let pipeline = DefaultTextProcessingPipeline(refiner: refiner)

        let result = await pipeline.process("原始文本")

        XCTAssertEqual(result.rawText, "原始文本")
        XCTAssertEqual(result.finalText, "原始文本")
        XCTAssertEqual(result.warnings, [])
    }

    func testRefinerFailureFallsBackToOriginalText() async {
        let refiner = StubTextRefiner(
            isEnabled: true,
            isConfigured: true,
            result: .failure(TestError.expected)
        )
        let pipeline = DefaultTextProcessingPipeline(refiner: refiner)

        let result = await pipeline.process("不要丢失")

        XCTAssertEqual(result.finalText, "不要丢失")
        XCTAssertEqual(result.warnings, ["llm_refinement_failed"])
    }

    func testConfiguredRefinerReturnsRefinedText() async {
        let refiner = StubTextRefiner(
            isEnabled: true,
            isConfigured: true,
            result: .success("修正文本")
        )
        let pipeline = DefaultTextProcessingPipeline(refiner: refiner)

        let result = await pipeline.process("原始文本")

        XCTAssertEqual(result.finalText, "修正文本")
        XCTAssertEqual(result.warnings, [])
    }

    func testPipelineBuildsPromptWithDefaultStyle() async throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let style = try XCTUnwrap(try environment.styleRepository.profile(id: "builtin.coding"))
        try environment.styleRepository.save(
            StyleProfileRecord(
                id: style.id,
                name: style.name,
                category: style.category,
                subtitle: style.subtitle,
                mode: style.mode,
                prompt: style.prompt,
                sampleInput: style.sampleInput,
                sampleOutput: style.sampleOutput,
                llmProviderID: "provider",
                model: "model-a",
                temperature: 0.2,
                enabled: style.enabled,
                builtIn: style.builtIn,
                isDefault: true,
                createdAt: style.createdAt,
                updatedAt: style.updatedAt
            )
        )
        let refiner = PromptAwareStubTextRefiner(result: .success("Python"))
        let pipeline = DefaultTextProcessingPipeline(
            refiner: refiner,
            styleRepository: environment.styleRepository,
            promptBuilder: PromptBuilder()
        )

        let result = await pipeline.process("配森")

        XCTAssertEqual(result.finalText, "Python")
        XCTAssertNil(result.llmProviderID)
        XCTAssertEqual(result.styleID, "builtin.coding")
        XCTAssertEqual(refiner.requests.map(\.text), ["配森"])
        XCTAssertEqual(refiner.requests.first?.model, "model-a")
        XCTAssertEqual(refiner.requests.first?.temperature, 0.2)
        XCTAssertTrue(refiner.requests.first?.systemPrompt.contains("编程") == true)
    }

    func testPipelineSelectsStyleByTargetApplicationRule() async throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        try StyleViewModel(environment: environment).saveAppStyleRule(
            id: nil,
            bundleID: "com.example.editor",
            appName: "Editor",
            styleID: "builtin.email"
        )
        let refiner = PromptAwareStubTextRefiner(result: .success("邮件文本"))
        let pipeline = DefaultTextProcessingPipeline(
            refiner: refiner,
            styleSelector: SettingsBackedStyleSelector(
                styleRepository: environment.styleRepository,
                settingsRepository: environment.settingsRepository
            ),
            promptBuilder: PromptBuilder()
        )

        let result = await pipeline.process(
            "邮件文本",
            target: DictationTarget(bundleID: "com.example.editor", appName: "Editor")
        )

        XCTAssertEqual(result.styleID, "builtin.email")
        XCTAssertTrue(refiner.requests.first?.systemPrompt.contains("邮件") == true)
    }

    func testPipelineUsesRequestLocalTraceWhenRefinerProvidesIt() async {
        let localTrace = Self.trace(providerID: "local-provider", model: "local-model")
        let refiner = TraceablePromptAwareStubTextRefiner(
            result: .success(
                TextRefinementTraceResult(
                    text: "修正文本",
                    providerID: "local-provider",
                    trace: localTrace
                )
            ),
            lastTrace: Self.trace(providerID: "poison-provider", model: "poison-model")
        )
        let pipeline = DefaultTextProcessingPipeline(refiner: refiner)

        let result = await pipeline.process("原始文本")

        XCTAssertEqual(result.finalText, "修正文本")
        XCTAssertEqual(result.llmProviderID, "local-provider")
        XCTAssertEqual(result.trace?.llm?.providerID, "local-provider")
        XCTAssertEqual(result.trace?.llm?.model, "local-model")
    }

    func testPipelineUsesRequestLocalTraceWhenStreamingRefinerProvidesIt() async {
        let localTrace = Self.trace(providerID: "stream-local-provider", model: "stream-local-model")
        let refiner = TraceableStreamingPromptAwareStubTextRefiner(
            snapshots: ["修", "修正文本"],
            providerID: "stream-local-provider",
            trace: localTrace,
            lastTrace: Self.trace(providerID: "poison-provider", model: "poison-model")
        )
        let pipeline = DefaultTextProcessingPipeline(refiner: refiner)

        let result = await pipeline.process("原始文本")

        XCTAssertEqual(result.finalText, "修正文本")
        XCTAssertEqual(result.llmProviderID, "stream-local-provider")
        XCTAssertEqual(result.trace?.llm?.providerID, "stream-local-provider")
        XCTAssertEqual(result.trace?.llm?.model, "stream-local-model")
    }

    func testPipelineAcceptsUnchangedStyledOutputWithoutRetry() async throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let refiner = SequencedPromptAwareRefiner(
            results: [
                "小兔子乖乖把门开开快点开开我要进来",
            ]
        )
        let pipeline = DefaultTextProcessingPipeline(
            refiner: refiner,
            styleRepository: environment.styleRepository
        )

        let result = await pipeline.process("小兔子乖乖把门开开快点开开我要进来")

        XCTAssertEqual(result.finalText, "小兔子乖乖把门开开快点开开我要进来")
        XCTAssertEqual(refiner.requests.count, 1)
        XCTAssertFalse(result.warnings.contains("llm_echo_retry"))
    }

    private enum TestError: Error {
        case expected
    }

    private static func trace(providerID: String, model: String) -> LLMRefinementTrace {
        LLMRefinementTrace(
            providerID: providerID,
            providerName: "Provider \(providerID)",
            endpoint: "https://api.example.com/v1/chat/completions",
            model: model,
            temperature: 0.2,
            timeoutSeconds: 13,
            requestBodyJSON: "{}",
            responseText: nil,
            statusCode: 200,
            durationMS: 10,
            errorMessage: nil,
            completedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
    }

    private final class StubTextRefiner: TextRefining, @unchecked Sendable {
        var isEnabled: Bool
        var isConfigured: Bool
        var result: Result<String, Error>

        init(
            isEnabled: Bool,
            isConfigured: Bool,
            result: Result<String, Error> = .success("unused")
        ) {
            self.isEnabled = isEnabled
            self.isConfigured = isConfigured
            self.result = result
        }

        func refine(_ text: String) async throws -> String {
            try result.get()
        }
    }

    private final class PromptAwareStubTextRefiner: TextRefining, PromptAwareTextRefining, @unchecked Sendable {
        var isEnabled = true
        var isConfigured = true
        var result: Result<String, Error>
        private(set) var requests: [TextRefinementRequest] = []

        init(result: Result<String, Error>) {
            self.result = result
        }

        func refine(_ text: String) async throws -> String {
            try await refine(
                TextRefinementRequest(
                    text: text,
                    systemPrompt: PromptBuilder.conservativeSystemPrompt,
                    model: nil,
                    temperature: nil
                )
            )
        }

        func refine(_ request: TextRefinementRequest) async throws -> String {
            requests.append(request)
            return try result.get()
        }
    }

    private final class TraceablePromptAwareStubTextRefiner: TextRefining, TraceablePromptAwareTextRefining, RefinementTraceProviding, @unchecked Sendable {
        var isEnabled = true
        var isConfigured = true
        var result: Result<TextRefinementTraceResult, Error>
        private(set) var requests: [TextRefinementRequest] = []
        private(set) var lastTrace: LLMRefinementTrace?

        init(
            result: Result<TextRefinementTraceResult, Error>,
            lastTrace: LLMRefinementTrace?
        ) {
            self.result = result
            self.lastTrace = lastTrace
        }

        func refine(_ text: String) async throws -> String {
            try await refine(
                TextRefinementRequest(
                    text: text,
                    systemPrompt: PromptBuilder.conservativeSystemPrompt,
                    model: nil,
                    temperature: nil
                )
            )
        }

        func refine(_ request: TextRefinementRequest) async throws -> String {
            try await refineWithTrace(request).text
        }

        func refineWithTrace(_ request: TextRefinementRequest) async throws -> TextRefinementTraceResult {
            requests.append(request)
            return try result.get()
        }

        func clearLastTrace() {}
    }

    private final class TraceableStreamingPromptAwareStubTextRefiner: TextRefining, TraceableStreamingPromptAwareTextRefining, RefinementTraceProviding, @unchecked Sendable {
        var isEnabled = true
        var isConfigured = true
        private let snapshots: [String]
        private let providerID: String
        private let trace: LLMRefinementTrace
        private(set) var lastTrace: LLMRefinementTrace?

        init(
            snapshots: [String],
            providerID: String,
            trace: LLMRefinementTrace,
            lastTrace: LLMRefinementTrace?
        ) {
            self.snapshots = snapshots
            self.providerID = providerID
            self.trace = trace
            self.lastTrace = lastTrace
        }

        func refine(_ text: String) async throws -> String {
            try await refine(
                TextRefinementRequest(
                    text: text,
                    systemPrompt: PromptBuilder.conservativeSystemPrompt,
                    model: nil,
                    temperature: nil
                )
            )
        }

        func refine(_ request: TextRefinementRequest) async throws -> String {
            var finalText = ""
            let result = refineStreamWithTrace(request)
            for try await snapshot in result.stream {
                finalText = snapshot
            }
            return finalText
        }

        func refineStream(_ request: TextRefinementRequest) -> AsyncThrowingStream<String, Error> {
            refineStreamWithTrace(request).stream
        }

        func refineStreamWithTrace(_ request: TextRefinementRequest) -> TextRefinementStreamTraceResult {
            let traceHandle = TextRefinementTraceHandle()
            let stream = AsyncThrowingStream<String, Error> { continuation in
                for snapshot in snapshots {
                    continuation.yield(snapshot)
                }
                traceHandle.complete(trace)
                continuation.finish()
            }
            return TextRefinementStreamTraceResult(stream: stream, providerID: providerID, trace: traceHandle)
        }

        func clearLastTrace() {}
    }

    private final class SequencedPromptAwareRefiner: TextRefining, PromptAwareTextRefining, @unchecked Sendable {
        var isEnabled = true
        var isConfigured = true
        private var results: [String]
        private(set) var requests: [TextRefinementRequest] = []

        init(results: [String]) {
            self.results = results
        }

        func refine(_ text: String) async throws -> String {
            try await refine(
                TextRefinementRequest(
                    text: text,
                    systemPrompt: PromptBuilder.conservativeSystemPrompt,
                    model: nil,
                    temperature: nil
                )
            )
        }

        func refine(_ request: TextRefinementRequest) async throws -> String {
            requests.append(request)
            return results.removeFirst()
        }
    }
}
