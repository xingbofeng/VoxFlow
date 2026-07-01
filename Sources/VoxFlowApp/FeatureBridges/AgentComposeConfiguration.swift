import Foundation

enum AgentComposeConfiguration {
    @MainActor
    static func isConfigured(
        llmRefinerConfigured: Bool,
        environment: AppEnvironment
    ) -> Bool {
        llmRefinerConfigured || AppRuntime.selectedAgentRuntimeProvider(environment: environment) != nil
    }
}
