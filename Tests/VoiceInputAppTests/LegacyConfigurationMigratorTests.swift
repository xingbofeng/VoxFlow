import XCTest
@testable import VoiceInputApp

final class LegacyConfigurationMigratorTests: XCTestCase {
    func testMigratesBundleDefaultsFromLegacyDomainWithoutStatusItemCache() {
        let legacyDomain = "LegacyDefaultsMigration.legacy.\(UUID().uuidString)"
        let currentDomain = "LegacyDefaultsMigration.current.\(UUID().uuidString)"
        let legacyDefaults = UserDefaults(suiteName: legacyDomain)!
        let currentDefaults = UserDefaults(suiteName: currentDomain)!
        defer {
            legacyDefaults.removePersistentDomain(forName: legacyDomain)
            currentDefaults.removePersistentDomain(forName: currentDomain)
        }
        legacyDefaults.set("deepseek-v4-flash-202605", forKey: "LLMRefiner_Model")
        legacyDefaults.set("https://tokenhub.tencentmaas.com/v1", forKey: "LLMRefiner_BaseURL")
        legacyDefaults.set(54, forKey: "DictationShortcutKeyCode")
        legacyDefaults.set(300, forKey: "NSStatusItem Preferred Position VoxFlowStatusItemV2")
        legacyDefaults.set(true, forKey: "NSStatusItem VisibleCC VoxFlowStatusItemV2")
        currentDefaults.set(61, forKey: "DictationShortcutKeyCode")

        LegacyConfigurationMigrator.migrateBundleDefaults(
            fromDomain: legacyDomain,
            toDomain: currentDomain
        )

        XCTAssertEqual(currentDefaults.string(forKey: "LLMRefiner_Model"), "deepseek-v4-flash-202605")
        XCTAssertEqual(currentDefaults.string(forKey: "LLMRefiner_BaseURL"), "https://tokenhub.tencentmaas.com/v1")
        XCTAssertEqual(currentDefaults.integer(forKey: "DictationShortcutKeyCode"), 61)
        XCTAssertNil(currentDefaults.object(forKey: "NSStatusItem Preferred Position VoxFlowStatusItemV2"))
        XCTAssertNil(currentDefaults.object(forKey: "NSStatusItem VisibleCC VoxFlowStatusItemV2"))
        XCTAssertTrue(currentDefaults.bool(forKey: "VoxFlow_BundleDefaultsMigrated_V1"))
    }

    func testMigratesLegacyLLMSettingsAndBuiltInPrompts() throws {
        let suiteName = "LegacyConfigurationMigratorTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("https://api.example.com/v1", forKey: "LLMRefiner_BaseURL")
        defaults.set("legacy-model", forKey: "LLMRefiner_Model")
        let credentials = MigratorCredentialStore()
        try credentials.saveCredential("secret", account: "llm-api-key")
        let container = try DependencyContainer.inMemory(
            credentialStore: credentials,
            defaults: defaults
        )

        let provider = try XCTUnwrap(container.llmProviderRepository.list().first)
        XCTAssertTrue(provider.isDefault)
        XCTAssertEqual(provider.defaultModel, "legacy-model")
        XCTAssertEqual(provider.apiKeyRef, "llm-api-key")
        XCTAssertEqual(
            try container.styleRepository.profile(id: "builtin.coding")?.prompt,
            BuiltInStyleCatalog.profile(id: "builtin.coding")?.prompt
        )
    }

    func testBuiltInPromptMigrationUpdatesEnergeticTemperature() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let clock = LegacyMigratorTestClock(now: now)
        let databaseQueue = try DatabaseQueue(connection: .inMemory())
        try AppDatabase.migrator(clock: clock).migrate(databaseQueue)
        let repository = SQLiteStyleRepository(databaseQueue: databaseQueue)
        let current = try XCTUnwrap(BuiltInStyleCatalog.profile(id: "builtin.energetic", now: now))
        let legacyPrompt = try XCTUnwrap(
            BuiltInStyleCatalog.legacyPrompts["builtin.energetic"]?.first {
                $0.contains("根据语境自行判断")
            }
        )

        try repository.save(
            StyleProfileRecord(
                id: current.id,
                name: current.name,
                category: current.category,
                subtitle: current.subtitle,
                mode: current.mode,
                prompt: legacyPrompt,
                sampleInput: current.sampleInput,
                sampleOutput: current.sampleOutput,
                llmProviderID: nil,
                model: nil,
                temperature: 0.2,
                enabled: true,
                builtIn: true,
                isDefault: false,
                createdAt: now,
                updatedAt: now
            )
        )

        try LegacyConfigurationMigrator.migrateBuiltInPrompts(
            repository: repository,
            clock: clock
        )

        let migrated = try XCTUnwrap(repository.profile(id: current.id))
        XCTAssertEqual(migrated.prompt, current.prompt)
        XCTAssertEqual(migrated.temperature, 0.6)
    }

    func testMigratesLargeErroneousEnergeticRuleBatchToRegistrySuggestions() throws {
        let clock = LegacyMigratorTestClock(now: Date(timeIntervalSince1970: 1_800_000_000))
        let databaseQueue = try DatabaseQueue(connection: .inMemory())
        try AppDatabase.migrator(clock: clock).migrate(databaseQueue)
        let settingsRepository = SQLiteSettingsRepository(databaseQueue: databaseQueue, clock: clock)
        let store = AppStyleRuleStore(settingsRepository: settingsRepository)
        let knownRules = [
            ("chatgpt", "com.openai.chat", "ChatGPT"),
            ("claude", "com.anthropic.claudefordesktop", "Claude"),
            ("codex", "com.openai.codex", "Codex"),
            ("qoder", "com.qoder.work.cn", "QoderWork CN"),
            ("kiro", "dev.kiro.desktop", "Kiro"),
            ("zed", "dev.zed.Zed", "Zed"),
            ("postman", "com.postmanlabs.mac", "Postman"),
            ("tableplus", "com.tinyapp.TablePlus", "TablePlus"),
            ("ghostty", "com.mitchellh.ghostty", "Ghostty"),
            ("raycast", "com.raycast.macos", "Raycast"),
        ]
        for (id, bundleID, appName) in knownRules {
            try store.save(
                AppStyleRule(
                    id: id,
                    bundleID: bundleID,
                    appName: appName,
                    styleID: "builtin.energetic"
                )
            )
        }
        try store.save(
            AppStyleRule(
                id: "unknown",
                bundleID: "com.example.unknown",
                appName: "Unknown",
                styleID: "builtin.energetic"
            )
        )
        try store.save(
            AppStyleRule(
                id: "chrome",
                bundleID: "com.google.Chrome",
                appName: "Chrome",
                styleID: "builtin.email"
            )
        )
        try store.save(
            AppStyleRule(
                id: "manual",
                bundleID: "com.example.manual",
                appName: "Manual",
                styleID: "builtin.formal"
            )
        )

        try LegacyConfigurationMigrator.migrateAppStyleRules(
            settingsRepository: settingsRepository,
            clock: clock
        )

        let migrated = try store.list()
        let stylesByBundleID = Dictionary(
            migrated.map { ($0.bundleID, $0.styleID) },
            uniquingKeysWith: { first, _ in first }
        )
        XCTAssertEqual(stylesByBundleID["com.openai.chat"], "builtin.original")
        XCTAssertEqual(stylesByBundleID["com.openai.codex"], "builtin.coding")
        XCTAssertEqual(stylesByBundleID["com.mitchellh.ghostty"], "builtin.coding")
        XCTAssertEqual(stylesByBundleID["com.raycast.macos"], "builtin.casual")
        XCTAssertEqual(stylesByBundleID["com.google.Chrome"], "builtin.casual")
        XCTAssertEqual(stylesByBundleID["com.example.manual"], "builtin.formal")
        XCTAssertNil(stylesByBundleID["com.example.unknown"])
    }

    func testDoesNotRewriteSmallIntentionalEnergeticRuleSet() throws {
        let clock = LegacyMigratorTestClock(now: Date(timeIntervalSince1970: 1_800_000_000))
        let databaseQueue = try DatabaseQueue(connection: .inMemory())
        try AppDatabase.migrator(clock: clock).migrate(databaseQueue)
        let settingsRepository = SQLiteSettingsRepository(databaseQueue: databaseQueue, clock: clock)
        let store = AppStyleRuleStore(settingsRepository: settingsRepository)
        try store.save(
            AppStyleRule(
                id: "intentional",
                bundleID: "com.openai.chat",
                appName: "ChatGPT",
                styleID: "builtin.energetic"
            )
        )

        try LegacyConfigurationMigrator.migrateAppStyleRules(
            settingsRepository: settingsRepository,
            clock: clock
        )

        XCTAssertEqual(try store.list().first?.styleID, "builtin.energetic")
    }
}

private struct LegacyMigratorTestClock: AppClock {
    let now: Date

    func sleep(nanoseconds: UInt64) async throws {}
}

private final class MigratorCredentialStore: CredentialStore {
    private var values: [String: String] = [:]
    func readCredential(account: String) throws -> String? { values[account] }
    func saveCredential(_ value: String, account: String) throws { values[account] = value }
    func deleteCredential(account: String) throws { values.removeValue(forKey: account) }
}
