import Foundation

enum LegacyConfigurationMigrator {
    private static let bundleDefaultsMigrationKey = "VoxFlow_BundleDefaultsMigrated_V1"

    static func migrateBundleDefaults(
        fromDomain legacyDomain: String = ProductBrand.legacyBundleIdentifier,
        toDomain currentDomain: String = ProductBrand.bundleIdentifier
    ) {
        guard legacyDomain != currentDomain else {
            return
        }
        let currentDefaults = UserDefaults(suiteName: currentDomain) ?? .standard
        guard currentDefaults.bool(forKey: bundleDefaultsMigrationKey) == false,
              let legacyValues = UserDefaults.standard.persistentDomain(forName: legacyDomain),
              legacyValues.isEmpty == false else {
            currentDefaults.set(true, forKey: bundleDefaultsMigrationKey)
            return
        }

        var currentValues = UserDefaults.standard.persistentDomain(forName: currentDomain) ?? [:]
        for (key, value) in legacyValues where shouldMigrateBundleDefaultKey(key) {
            guard currentValues[key] == nil else {
                continue
            }
            currentValues[key] = value
        }
        currentValues[bundleDefaultsMigrationKey] = true
        UserDefaults.standard.setPersistentDomain(currentValues, forName: currentDomain)
        currentDefaults.synchronize()
    }

    static func migrate(
        defaults: UserDefaults,
        credentialStore: CredentialStore,
        llmProviderRepository: any LLMProviderRepository,
        styleRepository: any StyleRepository,
        settingsRepository: any SettingsRepository,
        clock: any AppClock
    ) throws {
        try migrateLLM(
            defaults: defaults,
            credentialStore: credentialStore,
            repository: llmProviderRepository,
            clock: clock
        )
        try migrateBuiltInPrompts(repository: styleRepository, clock: clock)
        try migrateAppStyleRules(
            settingsRepository: settingsRepository,
            clock: clock
        )
    }

    private static func migrateLLM(
        defaults: UserDefaults,
        credentialStore: CredentialStore,
        repository: any LLMProviderRepository,
        clock: any AppClock
    ) throws {
        guard try repository.list().isEmpty,
              let baseURL = defaults.string(forKey: "LLMRefiner_BaseURL"),
              let model = defaults.string(forKey: "LLMRefiner_Model"),
              let key = try credentialStore.readCredential(account: "llm-api-key"),
              !baseURL.isEmpty,
              !model.isEmpty,
              !key.isEmpty else {
            return
        }
        let now = clock.now
        try repository.save(
            LLMProviderRecord(
                id: "legacy-openai-compatible",
                displayName: "OpenAI 兼容配置",
                providerType: "openaiCompatible",
                baseURL: try OpenAICompatibleClient.normalizedBaseURL(baseURL),
                defaultModel: model,
                apiKeyRef: "llm-api-key",
                temperature: 0,
                timeoutSeconds: 15,
                enabled: true,
                isDefault: true,
                lastHealthStatus: nil,
                lastHealthMessage: "已从旧版设置迁移",
                lastLatencyMS: nil,
                createdAt: now,
                updatedAt: now
            )
        )
    }

    static func migrateBuiltInPrompts(
        repository: any StyleRepository,
        clock: any AppClock
    ) throws {
        for id in BuiltInStyleCatalog.legacyPrompts.keys {
            guard let existing = try repository.profile(id: id),
                  existing.builtIn,
                  BuiltInStyleCatalog.shouldUpgradeLegacyPrompt(
                      existing.prompt,
                      profileID: id
                  ),
                  let current = BuiltInStyleCatalog.profile(id: id, now: existing.createdAt) else {
                continue
            }
            try repository.save(
                StyleProfileRecord(
                    id: existing.id,
                    name: current.name,
                    category: current.category,
                    subtitle: current.subtitle,
                    mode: current.mode,
                    prompt: current.prompt,
                    sampleInput: current.sampleInput,
                    sampleOutput: current.sampleOutput,
                    llmProviderID: existing.llmProviderID,
                    model: existing.model,
                    temperature: current.temperature,
                    enabled: existing.enabled,
                    builtIn: true,
                    isDefault: existing.isDefault,
                    createdAt: existing.createdAt,
                    updatedAt: clock.now
                )
            )
        }
    }

    static func migrateAppStyleRules(
        settingsRepository: any SettingsRepository,
        clock: any AppClock
    ) throws {
        let store = AppStyleRuleStore(settingsRepository: settingsRepository)
        let rules = try store.list()
        let energeticCount = rules.filter { $0.styleID == "builtin.energetic" }.count
        guard energeticCount >= 10, energeticCount * 2 >= rules.count else {
            return
        }

        let registry = KnownApplicationRegistry.builtIn()
        let migrated = rules.compactMap { rule -> AppStyleRule? in
            if rule.bundleID.caseInsensitiveCompare("com.google.Chrome") == .orderedSame,
               rule.styleID == "builtin.email" {
                return corrected(rule, styleID: "builtin.casual")
            }
            guard rule.styleID == "builtin.energetic" else {
                return rule
            }
            guard let entry = registry.lookup(bundleID: rule.bundleID),
                  entry.suggestedStyleID != "builtin.energetic" else {
                return nil
            }
            return corrected(rule, styleID: entry.suggestedStyleID)
        }

        try store.replaceAll(migrated)
        _ = clock
    }

    private static func corrected(
        _ rule: AppStyleRule,
        styleID: String
    ) -> AppStyleRule {
        AppStyleRule(
            id: rule.id,
            bundleID: rule.bundleID,
            appName: rule.appName,
            styleID: styleID
        )
    }

    private static func shouldMigrateBundleDefaultKey(_ key: String) -> Bool {
        guard key.hasPrefix("NSStatusItem ") == false else {
            return false
        }
        guard key.hasPrefix("NSWindow Frame ") == false else {
            return false
        }
        guard key.hasPrefix("NSNavPanel") == false else {
            return false
        }
        guard key.hasPrefix("NSOSPLast") == false else {
            return false
        }
        return true
    }
}
