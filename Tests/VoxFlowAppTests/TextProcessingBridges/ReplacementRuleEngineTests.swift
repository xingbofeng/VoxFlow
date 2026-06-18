import XCTest
@testable import VoxFlowApp

@MainActor
final class ReplacementRuleEngineTests: XCTestCase {
    func testAppliesExactContainsAndRegexRulesByPriority() {
        let engine = ReplacementRuleEngine()
        let result = engine.apply(
            [
                rule(id: "exact", source: "hello world", target: "你好世界", mode: .exact, priority: 1),
                rule(id: "contains", source: "Type Script", target: "TypeScript", mode: .contains, priority: 2),
                rule(id: "regex", source: #"版本(\d+)"#, target: "v$1", mode: .regex, priority: 3),
            ],
            to: "hello world"
        )

        XCTAssertEqual(result.text, "你好世界")

        let mixed = engine.apply(
            [
                rule(id: "contains", source: "Type Script", target: "TypeScript", mode: .contains, priority: 1),
                rule(id: "regex", source: #"版本(\d+)"#, target: "v$1", mode: .regex, priority: 2),
            ],
            to: "Type Script 版本3"
        )

        XCTAssertEqual(mixed.text, "TypeScript v3")
        XCTAssertEqual(mixed.warnings, [])
    }

    func testInvalidRegexIsSkippedWithWarning() {
        let engine = ReplacementRuleEngine()

        let result = engine.apply(
            [rule(id: "bad", source: #"("#, target: "x", mode: .regex, priority: 1)],
            to: "keep"
        )

        XCTAssertEqual(result.text, "keep")
        XCTAssertEqual(result.warnings, ["replacement_rule_invalid_regex:bad"])
    }

    func testPipelineAppliesBeforeAndAfterLLMRules() async throws {
        let container = try DependencyContainer.inMemory()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        try container.replacementRuleRepository.save(
            rule(
                id: "before",
                source: "Type Script",
                target: "TypeScript",
                mode: .contains,
                stage: .beforeLLM,
                priority: 1,
                now: now
            )
        )
        try container.replacementRuleRepository.save(
            rule(
                id: "after",
                source: "杰森",
                target: "JSON",
                mode: .contains,
                stage: .afterLLM,
                priority: 1,
                now: now
            )
        )
        let refiner = StubRefiner(result: .success("TypeScript 和 杰森"))
        let pipeline = DefaultTextProcessingPipeline(
            refiner: refiner,
            replacementRuleRepository: container.replacementRuleRepository
        )

        let result = await pipeline.process("Type Script 和 杰森")

        XCTAssertEqual(result.finalText, "TypeScript 和 JSON")
    }

    private func rule(
        id: String,
        source: String,
        target: String,
        mode: ReplacementMatchMode,
        stage: ReplacementApplyStage = .beforeLLM,
        priority: Int,
        now: Date = Date(timeIntervalSince1970: 1_800_000_000)
    ) -> ReplacementRule {
        ReplacementRule(
            id: id,
            source: source,
            target: target,
            matchMode: mode,
            applyStage: stage,
            category: "coding",
            enabled: true,
            priority: priority,
            createdAt: now,
            updatedAt: now
        )
    }

    private final class StubRefiner: TextRefining, @unchecked Sendable {
        var isEnabled = true
        var isConfigured = true
        let result: Result<String, Error>

        init(result: Result<String, Error>) {
            self.result = result
        }

        func refine(_ text: String) async throws -> String {
            try result.get()
        }
    }
}
