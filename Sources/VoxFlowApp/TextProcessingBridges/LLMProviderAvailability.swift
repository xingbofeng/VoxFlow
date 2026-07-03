import Foundation

enum LLMProviderAvailability {
    static func hasUsableProvider(in providers: [LLMProviderRecord]) -> Bool {
        providers.contains(where: isUsableProvider)
    }

    static func isUsableProvider(_ provider: LLMProviderRecord) -> Bool {
        provider.enabled &&
            provider.isOpenAICompatibleProvider &&
            provider.hasRequiredLLMConfiguration
    }
}

extension LLMProviderRecord {
    var isCodexLLMProvider: Bool {
        id.caseInsensitiveCompare(AgentProviderRegistry.codex.providerID) == .orderedSame ||
            providerType.caseInsensitiveCompare(AgentProviderRegistry.codex.providerID) == .orderedSame
    }

    var isLocalAgentProvider: Bool {
        AgentProviderRegistry.localProvider(for: id) != nil ||
            AgentProviderRegistry.localProvider(for: providerType) != nil ||
            AgentProviderRegistry.enabledRuntimeProviders.contains {
                baseURL.caseInsensitiveCompare($0.baseURL) == .orderedSame
            }
    }

    var localAgentDisplayName: String {
        AgentProviderRegistry.localProvider(for: id)?.displayName ??
            AgentProviderRegistry.localProvider(for: providerType)?.displayName ??
            AgentProviderRegistry.enabledRuntimeProviders.first {
                baseURL.caseInsensitiveCompare($0.baseURL) == .orderedSame
            }?.displayName ??
            displayName
    }

    var isCodexRuntimeProvider: Bool {
        isCodexLLMProvider
    }

    var isOpenAICompatibleProvider: Bool {
        !isLocalAgentProvider
    }

    var hasRequiredLLMConfiguration: Bool {
        !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !defaultModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
