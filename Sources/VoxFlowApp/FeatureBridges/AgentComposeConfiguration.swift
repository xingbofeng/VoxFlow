import Foundation

enum AgentComposeConfiguration {
    @MainActor
    static func isConfigured(
        llmRefinerConfigured: Bool,
        environment: AppEnvironment
    ) -> Bool {
        let refiner = RepositoryBackedLLMRefiner(
            providerRepository: environment.llmProviderRepository,
            credentialStore: environment.credentialStore,
            settingsRepository: environment.settingsRepository
        )
        let runtimeSelection = AppRuntime.selectedAgentRuntimeProvider(environment: environment)
        return llmRefinerConfigured ||
            refiner.isAgentComposeConfigured ||
            runtimeSelection?.isAgentComposeRuntimeEligible == true
    }
}
