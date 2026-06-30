import XCTest
@testable import VoxFlowApp

/// Phase 4 验证 (OpenSpec `style-auto-routing` §4.1–§4.7)：
/// - 既有 style profile 在新 schema 上保持完整，prompt / 样例 / 默认值不丢失
/// - 新增 `allow_auto_match` / `auto_match_description` 列默认值符合 spec
/// - 风格候选条件 `isEligibleForAutoRouter` 与 spec 一致
final class StyleAutoMatchSchemaTests: XCTestCase {
    private var queue: DatabaseQueue!
    private var styles: SQLiteStyleRepository!

    private struct FixedClock: AppClock {
        let now: Date

        func sleep(nanoseconds: UInt64) async throws {}
    }

    override func setUpWithError() throws {
        try super.setUpWithError()
        queue = try DatabaseQueue(connection: .inMemory())
        try AppDatabase.migrator().migrate(queue)
        styles = SQLiteStyleRepository(databaseQueue: queue)
    }

    override func tearDown() {
        styles = nil
        queue = nil
        super.tearDown()
    }

    func testMigrationPreservesExistingStylePromptAndFields() throws {
        // 模拟一个老库已经写入的 style：手动 INSERT 不带新列。
        try queue.write { connection in
            try connection.execute(
                """
                INSERT INTO style_profiles (
                    id, name, category, subtitle, mode, prompt, sample_input,
                    sample_output, llm_provider_id, model, temperature, enabled,
                    built_in, is_default, created_at, updated_at
                )
                VALUES ('user-custom', '我的风格', 'work', '副标题', 'conservative',
                        '用户辛苦写好的提示词', '样例输入', '样例输出', NULL, NULL,
                        0.3, 1, 0, 0, '2026-06-01T00:00:00Z', '2026-06-01T00:00:00Z')
                """
            )
        }

        let saved = try XCTUnwrap(try styles.profile(id: "user-custom"))
        XCTAssertEqual(saved.prompt, "用户辛苦写好的提示词")
        XCTAssertEqual(saved.subtitle, "副标题")
        XCTAssertEqual(saved.sampleInput, "样例输入")
        XCTAssertEqual(saved.sampleOutput, "样例输出")
        XCTAssertEqual(saved.temperature, 0.3, accuracy: 0.0001)
        XCTAssertTrue(saved.enabled)
        // spec §4.2：既有 style 默认 allowAutoMatch=false，autoMatchDescription 为 nil。
        XCTAssertFalse(saved.allowAutoMatch)
        XCTAssertNil(saved.autoMatchDescription)
        XCTAssertEqual(saved.outputFormat, StyleOutputFormat.systemDefault)
    }

    func testSaveAndReadAutoMatchFields() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        try styles.save(
            StyleProfileRecord(
                id: "auto-match",
                name: "自动匹配风格",
                category: "work",
                subtitle: nil,
                mode: "conservative",
                prompt: "p",
                sampleInput: nil,
                sampleOutput: nil,
                llmProviderID: nil,
                model: nil,
                temperature: 0.2,
                enabled: true,
                builtIn: false,
                isDefault: false,
                createdAt: now,
                updatedAt: now,
                allowAutoMatch: true,
                autoMatchDescription: "适合技术评审和代码讨论"
            )
        )

        let saved = try XCTUnwrap(try styles.profile(id: "auto-match"))
        XCTAssertTrue(saved.allowAutoMatch)
        XCTAssertEqual(saved.autoMatchDescription, "适合技术评审和代码讨论")
    }

    func testSaveAndReadOutputFormatJSON() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let format = StyleOutputFormat(
            punctuation: .less,
            capitalization: .relaxed,
            tone: .natural,
            emoji: .natural
        )
        try styles.save(
            StyleProfileRecord(
                id: "chat-format",
                name: "聊天格式",
                category: "chat",
                subtitle: nil,
                mode: "chat",
                prompt: "p",
                sampleInput: nil,
                sampleOutput: nil,
                llmProviderID: nil,
                model: nil,
                temperature: 0.2,
                enabled: true,
                builtIn: false,
                isDefault: false,
                createdAt: now,
                updatedAt: now,
                outputFormat: format
            )
        )

        let saved = try XCTUnwrap(try styles.profile(id: "chat-format"))
        XCTAssertEqual(saved.outputFormat, format)
    }

    func testBuiltInSeederBackfillsOutputFormatDefaults() throws {
        try BuiltInStyleSeeder.seed(styleRepository: styles, clock: FixedClock(now: Date(timeIntervalSince1970: 1_800_000_000)))

        let chat = try XCTUnwrap(try styles.profile(id: "builtin.chat"))
        XCTAssertEqual(chat.outputFormat, StyleOutputFormat.builtInDefault(for: "builtin.chat"))
        let formal = try XCTUnwrap(try styles.profile(id: "builtin.formal"))
        XCTAssertEqual(formal.outputFormat, StyleOutputFormat.builtInDefault(for: "builtin.formal"))
    }

    func testIsEligibleForAutoRouterMatchesSpec() {
        let base = StyleProfileRecord(
            id: "x", name: "x", category: "c", subtitle: nil, mode: "conservative",
            prompt: "p", sampleInput: nil, sampleOutput: nil, llmProviderID: nil,
            model: nil, temperature: 0.2, enabled: true, builtIn: false,
            isDefault: false,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )

        // enabled=false 即使开启自动匹配也不进入候选。
        XCTAssertFalse(Self.variant(base, enabled: false, allowAutoMatch: true, description: "ok").isEligibleForAutoRouter)
        // allowAutoMatch=false 不进入候选。
        XCTAssertFalse(Self.variant(base, enabled: true, allowAutoMatch: false, description: "ok").isEligibleForAutoRouter)
        // 简介为空不进入候选。
        XCTAssertFalse(Self.variant(base, enabled: true, allowAutoMatch: true, description: nil).isEligibleForAutoRouter)
        XCTAssertFalse(Self.variant(base, enabled: true, allowAutoMatch: true, description: "   ").isEligibleForAutoRouter)
        // 全部满足才进入候选。
        XCTAssertTrue(Self.variant(base, enabled: true, allowAutoMatch: true, description: "适合邮件和工作消息").isEligibleForAutoRouter)
    }

    func testAutoMatchSettingsStoreDefaultsGlobalEnabled() throws {
        let store = StyleAutoMatchSettingsStore(
            settingsRepository: SQLiteSettingsRepository(databaseQueue: queue)
        )
        XCTAssertEqual(store.load(), StyleAutoMatchSettings())
        var settings = StyleAutoMatchSettings()
        settings.globalEnabled = true
        try store.save(settings)
        XCTAssertEqual(store.load(), settings)
    }

    private static func variant(
        _ base: StyleProfileRecord,
        enabled: Bool,
        allowAutoMatch: Bool,
        description: String?
    ) -> StyleProfileRecord {
        StyleProfileRecord(
            id: base.id, name: base.name, category: base.category, subtitle: base.subtitle,
            mode: base.mode, prompt: base.prompt, sampleInput: base.sampleInput,
            sampleOutput: base.sampleOutput, llmProviderID: base.llmProviderID,
            model: base.model, temperature: base.temperature, enabled: enabled,
            builtIn: base.builtIn, isDefault: base.isDefault, createdAt: base.createdAt,
            updatedAt: base.updatedAt, allowAutoMatch: allowAutoMatch,
            autoMatchDescription: description
        )
    }
}
