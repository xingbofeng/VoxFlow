import Foundation

enum LegacyConfigurationMigrator {
    static func migrate(
        defaults: UserDefaults,
        credentialStore: CredentialStore,
        llmProviderRepository: any LLMProviderRepository,
        styleRepository: any StyleRepository,
        clock: any AppClock
    ) throws {
        try migrateLLM(
            defaults: defaults,
            credentialStore: credentialStore,
            repository: llmProviderRepository,
            clock: clock
        )
        try migrateBuiltInPrompts(repository: styleRepository, clock: clock)
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

    private static func migrateBuiltInPrompts(
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
                    temperature: existing.temperature,
                    enabled: existing.enabled,
                    builtIn: true,
                    isDefault: existing.isDefault,
                    createdAt: existing.createdAt,
                    updatedAt: clock.now
                )
            )
        }
    }
}
