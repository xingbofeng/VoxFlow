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

    func testPipelineBuildsPromptWithDefaultStyleAndGlossaryTerms() async throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        try GlossaryViewModel(environment: environment).saveTerm(
            id: nil,
            term: "Python",
            aliasesText: "配森",
            category: "coding",
            enabled: true,
            priority: 1,
            notes: nil
        )
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
            glossaryRepository: environment.glossaryRepository,
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
        XCTAssertTrue(refiner.requests.first?.systemPrompt.contains("Python") == true)
        XCTAssertTrue(refiner.requests.first?.systemPrompt.contains("配森") == true)
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
            glossaryRepository: environment.glossaryRepository,
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

    func testPipelineRetriesWhenStyledModelEchoesInput() async throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let refiner = SequencedPromptAwareRefiner(
            results: [
                "小兔子乖乖把门开开快点开开我要进来",
                "小兔子乖乖，把门开开，快点开开，我要进来！",
            ]
        )
        let pipeline = DefaultTextProcessingPipeline(
            refiner: refiner,
            styleRepository: environment.styleRepository
        )

        let result = await pipeline.process("小兔子乖乖把门开开快点开开我要进来")

        XCTAssertEqual(result.finalText, "小兔子乖乖，把门开开，快点开开，我要进来！")
        XCTAssertEqual(refiner.requests.count, 2)
        XCTAssertTrue(refiner.requests.last?.systemPrompt.contains("上一次输出与输入完全相同") == true)
        XCTAssertFalse(refiner.requests.last?.systemPrompt.contains("必须真正执行文本整理") == true)
        XCTAssertTrue(refiner.requests.last?.text.contains("待处理原文") == true)
        XCTAssertTrue(result.warnings.contains("llm_echo_retry"))
    }

    private enum TestError: Error {
        case expected
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
