import Foundation

enum LLMProviderAvailability {
    static func hasUsableProvider(in providers: [LLMProviderRecord]) -> Bool {
        providers.contains(where: isUsableProvider)
    }

    static func isUsableProvider(_ provider: LLMProviderRecord) -> Bool {
        provider.enabled && provider.hasRequiredLLMConfiguration
    }
}

extension LLMProviderRecord {
    var hasRequiredLLMConfiguration: Bool {
        !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !defaultModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
