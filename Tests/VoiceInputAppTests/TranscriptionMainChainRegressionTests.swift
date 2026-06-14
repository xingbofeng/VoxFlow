import XCTest
@testable import VoiceInputApp

@MainActor
final class TranscriptionMainChainRegressionTests: XCTestCase {

    // MARK: - 1. LLM disabled: pipeline returns raw text unchanged

    func testPipelineReturnsRawTextWhenRefinerIsDisabled() async {
        let refiner = StubTextRefiner(isEnabled: false, isConfigured: true)
        let pipeline = DefaultTextProcessingPipeline(refiner: refiner)

        let result = await pipeline.process("hello world")

        XCTAssertEqual(result.rawText, "hello world")
        XCTAssertEqual(result.finalText, "hello world")
        XCTAssertEqual(result.warnings, [])
        XCTAssertNil(result.llmProviderID)
        XCTAssertNil(result.styleID)
    }

    func testPipelineReturnsRawTextWhenRefinerIsNotConfigured() async {
        let refiner = StubTextRefiner(isEnabled: true, isConfigured: false)
        let pipeline = DefaultTextProcessingPipeline(refiner: refiner)

        let result = await pipeline.process("some text")

        XCTAssertEqual(result.rawText, "some text")
        XCTAssertEqual(result.finalText, "some text")
        XCTAssertEqual(result.warnings, [])
    }

    func testPipelineDoesNotCallRefineWhenDisabled() async {
        let refiner = CountingStubTextRefiner(isEnabled: false, isConfigured: true)
        let pipeline = DefaultTextProcessingPipeline(refiner: refiner)

        _ = await pipeline.process("text")

        XCTAssertEqual(refiner.refineCallCount, 0)
    }

    // MARK: - 2. LLM failure fallback: raw text preserved with warning

    func testPipelineFallsBackToRawTextOnLLMError() async {
        let refiner = StubTextRefiner(
            isEnabled: true,
            isConfigured: true,
            result: .failure(RefineError.networkTimeout)
        )
        let pipeline = DefaultTextProcessingPipeline(refiner: refiner)

        let result = await pipeline.process("important text")

        XCTAssertEqual(result.rawText, "important text")
        XCTAssertEqual(result.finalText, "important text")
        XCTAssertTrue(result.warnings.contains("llm_refinement_failed"))
    }

    func testPipelineFallsBackToRawTextOnLLMCrash() async {
        let refiner = StubTextRefiner(
            isEnabled: true,
            isConfigured: true,
            result: .failure(RefineError.unexpectedCrash)
        )
        let pipeline = DefaultTextProcessingPipeline(refiner: refiner)

        let result = await pipeline.process("do not lose this")

        XCTAssertEqual(result.finalText, "do not lose this")
        XCTAssertTrue(result.warnings.contains("llm_refinement_failed"))
    }

    // MARK: - 3. Empty LLM response: falls back to raw text

    func testPipelineUsesRawTextWhenLLMReturnsEmptyString() async {
        let refiner = StubTextRefiner(
            isEnabled: true,
            isConfigured: true,
            result: .success("")
        )
        let pipeline = DefaultTextProcessingPipeline(refiner: refiner)

        let result = await pipeline.process("keep this")

        XCTAssertEqual(result.rawText, "keep this")
        XCTAssertEqual(result.finalText, "keep this")
    }

    func testPipelineUsesRawTextWhenLLMReturnsWhitespaceOnly() async {
        let refiner = StubTextRefiner(
            isEnabled: true,
            isConfigured: true,
            result: .success("   \n\t  ")
        )
        let pipeline = DefaultTextProcessingPipeline(refiner: refiner)

        let result = await pipeline.process("original")

        XCTAssertEqual(result.rawText, "original")
        XCTAssertEqual(result.finalText, "original")
    }

    func testPipelineTrimsValidLLMResponse() async {
        let refiner = StubTextRefiner(
            isEnabled: true,
            isConfigured: true,
            result: .success("  refined text  ")
        )
        let pipeline = DefaultTextProcessingPipeline(refiner: refiner)

        let result = await pipeline.process("raw")

        XCTAssertEqual(result.finalText, "refined text")
    }

    // MARK: - 4. Replacement rules ordering: before-LLM then after-LLM

    func testBeforeLLMRulesApplyBeforeRefinerAndAfterLLMRulesApplyAfter() async throws {
        let container = try DependencyContainer.inMemory()
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        // Before-LLM rule: "Type Script" -> "TypeScript"
        try container.replacementRuleRepository.save(
            replacementRule(
                id: "before-1",
                source: "Type Script",
                target: "TypeScript",
                mode: .contains,
                stage: .beforeLLM,
                priority: 1,
                now: now
            )
        )
        // After-LLM rule: "杰森" -> "JSON"
        try container.replacementRuleRepository.save(
            replacementRule(
                id: "after-1",
                source: "杰森",
                target: "JSON",
                mode: .contains,
                stage: .afterLLM,
                priority: 1,
                now: now
            )
        )

        // The refiner receives the before-LLM-applied text and returns it with extra content
        let refiner = CapturingStubTextRefiner(result: .success("TypeScript and 杰森 data"))
        let pipeline = DefaultTextProcessingPipeline(
            refiner: refiner,
            replacementRuleRepository: container.replacementRuleRepository
        )

        let result = await pipeline.process("Type Script and 杰森 data")

        // Before-LLM replaced "Type Script" -> "TypeScript" before refiner was called
        XCTAssertEqual(refiner.lastInputText, "TypeScript and 杰森 data")
        // After-LLM replaced "杰森" -> "JSON" after refiner returned
        XCTAssertEqual(result.finalText, "TypeScript and JSON data")
    }

    func testBeforeLLMRulesApplyEvenWhenRefinerIsDisabled() async throws {
        let container = try DependencyContainer.inMemory()
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        try container.replacementRuleRepository.save(
            replacementRule(
                id: "before-only",
                source: "hello",
                target: "goodbye",
                mode: .contains,
                stage: .beforeLLM,
                priority: 1,
                now: now
            )
        )

        let refiner = StubTextRefiner(isEnabled: false, isConfigured: true)
        let pipeline = DefaultTextProcessingPipeline(
            refiner: refiner,
            replacementRuleRepository: container.replacementRuleRepository
        )

        let result = await pipeline.process("hello world")

        // Before-LLM rule ran, LLM skipped, after-LLM has no rules
        XCTAssertEqual(result.finalText, "goodbye world")
    }

    func testAfterLLMRulesApplyOnLLMFailureFallback() async throws {
        let container = try DependencyContainer.inMemory()
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        try container.replacementRuleRepository.save(
            replacementRule(
                id: "after-fallback",
                source: "bad",
                target: "good",
                mode: .contains,
                stage: .afterLLM,
                priority: 1,
                now: now
            )
        )

        let refiner = StubTextRefiner(
            isEnabled: true,
            isConfigured: true,
            result: .failure(RefineError.networkTimeout)
        )
        let pipeline = DefaultTextProcessingPipeline(
            refiner: refiner,
            replacementRuleRepository: container.replacementRuleRepository
        )

        let result = await pipeline.process("this is bad")

        // LLM failed, but after-LLM rules still apply to the raw text
        XCTAssertEqual(result.finalText, "this is good")
        XCTAssertTrue(result.warnings.contains("llm_refinement_failed"))
    }

    // MARK: - 5. PromptBuilder conservative prompt contains key instructions

    func testConservativePromptContainsHomophoneCorrection() {
        let prompt = PromptBuilder.conservativeSystemPrompt

        XCTAssertTrue(
            prompt.contains("同音"),
            "Conservative prompt must mention homophone correction"
        )
    }

    func testConservativePromptContainsNoRewritingInstruction() {
        let prompt = PromptBuilder.conservativeSystemPrompt

        XCTAssertTrue(
            (prompt.contains("不要添加") || prompt.contains("不要补充"))
                && (prompt.contains("用户没有说过") || prompt.contains("用户没有表达")),
            "Conservative prompt must forbid rewriting"
        )
    }

    func testConservativePromptContainsOutputOnlyInstruction() {
        let prompt = PromptBuilder.conservativeSystemPrompt

        XCTAssertTrue(
            prompt.contains("只输出处理后的正文"),
            "Conservative prompt must instruct output-only (no explanations)"
        )
    }

    func testConservativePromptContainsFillerWordRemoval() {
        let prompt = PromptBuilder.conservativeSystemPrompt

        XCTAssertTrue(
            prompt.contains("语气填充词"),
            "Conservative prompt must address filler word removal"
        )
    }

    func testConservativePromptMentionsChineseAndEnglish() {
        let prompt = PromptBuilder.conservativeSystemPrompt

        XCTAssertTrue(
            prompt.contains("中文") && prompt.contains("英文"),
            "Conservative prompt must mention both Chinese and English"
        )
    }

    func testBuildWithNoStyleAndNoGlossaryReturnsBasePrompt() {
        let builder = PromptBuilder()

        let result = builder.build(style: nil, glossaryTerms: [])

        XCTAssertEqual(result.systemPrompt, PromptBuilder.conservativeSystemPrompt)
        XCTAssertNil(result.styleID)
        XCTAssertNil(result.model)
        XCTAssertNil(result.temperature)
    }

    func testBuildWithDisabledStyleExcludesStylePrompt() throws {
        let style = try XCTUnwrap(BuiltInStyleCatalog.profile(id: "builtin.coding"))
        let disabledStyle = StyleProfileRecord(
            id: style.id,
            name: style.name,
            category: style.category,
            subtitle: style.subtitle,
            mode: style.mode,
            prompt: style.prompt,
            sampleInput: style.sampleInput,
            sampleOutput: style.sampleOutput,
            llmProviderID: nil,
            model: nil,
            temperature: 0.2,
            enabled: false,
            builtIn: style.builtIn,
            isDefault: false,
            createdAt: style.createdAt,
            updatedAt: style.updatedAt
        )
        let builder = PromptBuilder()

        let result = builder.build(style: disabledStyle, glossaryTerms: [])

        XCTAssertEqual(result.systemPrompt, PromptBuilder.conservativeSystemPrompt)
        XCTAssertNil(result.styleID)
    }

    // MARK: - 6. DatabaseMigrator idempotency

    func testMigratorIdempotencyRunningTwiceDoesNotFailOrDuplicate() throws {
        let queue = try DatabaseQueue(connection: .inMemory())
        let callCounter = MigrationCallCounter()
        let migrator = DatabaseMigrator(migrations: [
            DatabaseMigration(id: 1, name: "create_test_table") { connection in
                callCounter.count += 1
                try connection.execute(
                    "CREATE TABLE test_items (id TEXT PRIMARY KEY, value TEXT NOT NULL)"
                )
            },
            DatabaseMigration(id: 2, name: "insert_seed_data") { connection in
                callCounter.count += 1
                let stmt = try connection.prepare(
                    "INSERT INTO test_items (id, value) VALUES (?, ?)"
                )
                try stmt.bind("seed-1", at: 1)
                try stmt.bind("hello", at: 2)
                _ = try stmt.step()
            },
        ])

        // First migration
        try migrator.migrate(queue)

        XCTAssertEqual(callCounter.count, 2, "Both migrations should run on first pass")

        // Verify data was inserted
        let firstCount = try queue.read { connection in
            try countRows(in: "test_items", on: connection)
        }
        XCTAssertEqual(firstCount, 1)

        // Second migration (idempotent)
        try migrator.migrate(queue)

        XCTAssertEqual(callCounter.count, 2, "No migration should run again on second pass")

        // Verify data was NOT duplicated
        let secondCount = try queue.read { connection in
            try countRows(in: "test_items", on: connection)
        }
        XCTAssertEqual(secondCount, 1, "Seed data must not be duplicated")
    }

    func testAppDatabaseMigratorIsIdempotent() throws {
        let queue = try DatabaseQueue(connection: .inMemory())
        let migrator = AppDatabase.migrator()

        try migrator.migrate(queue)
        try migrator.migrate(queue)

        // Verify schema_migrations has exactly the expected number of entries
        let migrationCount = try queue.read { connection in
            try countRows(in: "schema_migrations", on: connection)
        }
        XCTAssertEqual(migrationCount, 3, "AppDatabase has 3 migrations; running twice must not create duplicates")
    }

    func testAppDatabaseMigratorCreatesAllExpectedTables() throws {
        let queue = try DatabaseQueue(connection: .inMemory())
        try AppDatabase.migrator().migrate(queue)

        let tables = try queue.read { connection -> Set<String> in
            let statement = try connection.prepare(
                """
                SELECT name FROM sqlite_master
                WHERE type = 'table' AND name NOT LIKE 'sqlite_%'
                """
            )
            var names = Set<String>()
            while try statement.step() {
                if let name = statement.columnString(at: 0) {
                    names.insert(name)
                }
            }
            return names
        }

        let expectedTables: Set<String> = [
            "schema_migrations",
            "dictation_history",
            "glossary_terms",
            "replacement_rules",
            "style_profiles",
            "asr_providers",
            "llm_providers",
            "transcription_jobs",
            "notes",
            "app_settings",
            "voice_tasks",
        ]
        XCTAssertTrue(
            tables.isSuperset(of: expectedTables),
            "Missing tables: \(expectedTables.subtracting(tables))"
        )
    }

    // MARK: - Helpers

    private enum RefineError: Error {
        case networkTimeout
        case unexpectedCrash
    }

    private final class StubTextRefiner: TextRefining, @unchecked Sendable {
        var isEnabled: Bool
        var isConfigured: Bool
        var result: Result<String, Error>

        init(
            isEnabled: Bool = true,
            isConfigured: Bool = true,
            result: Result<String, Error> = .success("refined")
        ) {
            self.isEnabled = isEnabled
            self.isConfigured = isConfigured
            self.result = result
        }

        func refine(_ text: String) async throws -> String {
            try result.get()
        }
    }

    private final class CountingStubTextRefiner: TextRefining, @unchecked Sendable {
        var isEnabled: Bool
        var isConfigured: Bool
        private(set) var refineCallCount = 0
        private let result: Result<String, Error>

        init(
            isEnabled: Bool = true,
            isConfigured: Bool = true,
            result: Result<String, Error> = .success("refined")
        ) {
            self.isEnabled = isEnabled
            self.isConfigured = isConfigured
            self.result = result
        }

        func refine(_ text: String) async throws -> String {
            refineCallCount += 1
            return try result.get()
        }
    }

    private final class CapturingStubTextRefiner: TextRefining, @unchecked Sendable {
        var isEnabled = true
        var isConfigured = true
        private(set) var lastInputText: String?
        private let result: Result<String, Error>

        init(result: Result<String, Error>) {
            self.result = result
        }

        func refine(_ text: String) async throws -> String {
            lastInputText = text
            return try result.get()
        }
    }

    private final class MigrationCallCounter {
        var count = 0
    }

    private func replacementRule(
        id: String,
        source: String,
        target: String,
        mode: ReplacementMatchMode,
        stage: ReplacementApplyStage,
        priority: Int,
        now: Date
    ) -> ReplacementRule {
        ReplacementRule(
            id: id,
            source: source,
            target: target,
            matchMode: mode,
            applyStage: stage,
            category: "general",
            enabled: true,
            priority: priority,
            createdAt: now,
            updatedAt: now
        )
    }

    private func countRows(in table: String, on connection: SQLiteConnection) throws -> Int {
        let statement = try connection.prepare("SELECT COUNT(*) FROM \(table)")
        _ = try statement.step()
        return statement.columnInt(at: 0)
    }
}
