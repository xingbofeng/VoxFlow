import Combine
import Foundation

@MainActor
final class StyleViewModel: ObservableObject {
    @Published private(set) var profiles: [StyleProfileRecord] = []
    @Published private(set) var defaultProfile: StyleProfileRecord?
    @Published private(set) var selectedProfile: StyleProfileRecord?
    @Published private(set) var appStyleRules: [AppStyleRule] = []
    @Published private(set) var lastError: String?
    @Published private(set) var lastActionMessage: String?

    private let environment: AppEnvironment
    private let appStyleRuleStore: AppStyleRuleStore
    private let smartConfigurationAppProvider: any InstalledApplicationProviding
    private let smartConfigurationClassifierFactory: @MainActor (AppEnvironment) -> (any BatchApplicationClassifying)?

    init(
        environment: AppEnvironment,
        smartConfigurationAppProvider: any InstalledApplicationProviding = FileSystemInstalledApplicationProvider(),
        smartConfigurationClassifierFactory: @escaping @MainActor (AppEnvironment) -> (any BatchApplicationClassifying)? = StyleViewModel.makeDefaultSmartConfigurationClassifier
    ) {
        self.environment = environment
        self.appStyleRuleStore = AppStyleRuleStore(settingsRepository: environment.settingsRepository)
        self.smartConfigurationAppProvider = smartConfigurationAppProvider
        self.smartConfigurationClassifierFactory = smartConfigurationClassifierFactory
        load()
    }

    func load() {
        do {
            let selectedID = selectedProfile?.id
            profiles = try environment.styleRepository.list(category: nil)
            defaultProfile = try environment.styleRepository.defaultProfile()
            selectedProfile = profiles.first { $0.id == selectedID }
                ?? defaultProfile
                ?? profiles.first
            appStyleRules = try appStyleRuleStore.list()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func updateProfile(
        id: String,
        prompt: String
    ) throws {
        let existing = try requireProfile(id: id)
        let normalizedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedPrompt.isEmpty else {
            throw StyleViewModelError.promptRequired
        }
        try environment.styleRepository.save(
            StyleProfileRecord(
                id: existing.id,
                name: existing.name,
                category: existing.category,
                subtitle: existing.subtitle,
                mode: existing.mode,
                prompt: normalizedPrompt,
                sampleInput: existing.sampleInput,
                sampleOutput: existing.sampleOutput,
                llmProviderID: existing.llmProviderID,
                model: existing.model,
                temperature: existing.temperature,
                enabled: existing.enabled,
                builtIn: existing.builtIn,
                isDefault: existing.isDefault,
                createdAt: existing.createdAt,
                updatedAt: environment.clock.now
            )
        )
        load()
        lastError = nil
        lastActionMessage = "已保存风格"
    }

    func setDefaultProfile(id: String) throws {
        let existing = try requireProfile(id: id)
        try environment.styleRepository.save(
            StyleProfileRecord(
                id: existing.id,
                name: existing.name,
                category: existing.category,
                subtitle: existing.subtitle,
                mode: existing.mode,
                prompt: existing.prompt,
                sampleInput: existing.sampleInput,
                sampleOutput: existing.sampleOutput,
                llmProviderID: existing.llmProviderID,
                model: existing.model,
                temperature: existing.temperature,
                enabled: existing.enabled,
                builtIn: existing.builtIn,
                isDefault: true,
                createdAt: existing.createdAt,
                updatedAt: environment.clock.now
            )
        )
        load()
        lastError = nil
        lastActionMessage = "已设为默认风格"
    }

    func selectProfile(id: String) throws {
        try setDefaultProfile(id: id)
        selectedProfile = profiles.first { $0.id == id }
        lastActionMessage = nil
    }

    func resetBuiltInPrompt(id: String) throws {
        let existing = try requireProfile(id: id)
        guard existing.builtIn,
              let catalog = BuiltInStyleCatalog.profile(id: id, now: existing.createdAt) else {
            return
        }

        try environment.styleRepository.save(
            StyleProfileRecord(
                id: existing.id,
                name: catalog.name,
                category: catalog.category,
                subtitle: catalog.subtitle,
                mode: catalog.mode,
                prompt: catalog.prompt,
                sampleInput: catalog.sampleInput,
                sampleOutput: catalog.sampleOutput,
                llmProviderID: catalog.llmProviderID,
                model: catalog.model,
                temperature: catalog.temperature,
                enabled: existing.enabled,
                builtIn: true,
                isDefault: existing.isDefault,
                createdAt: existing.createdAt,
                updatedAt: environment.clock.now
            )
        )
        load()
        lastError = nil
        lastActionMessage = "已重置内置提示词"
    }

    func saveAppStyleRule(
        id: String?,
        bundleID: String,
        appName: String,
        styleID: String
    ) throws {
        _ = try requireProfile(id: styleID)
        let normalizedBundleID = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedAppName = appName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedBundleID.isEmpty || !normalizedAppName.isEmpty else {
            throw StyleViewModelError.applicationIdentityRequired
        }
        let rule = AppStyleRule(
            id: id ?? UUID().uuidString,
            bundleID: normalizedBundleID,
            appName: normalizedAppName,
            styleID: styleID
        )
        try appStyleRuleStore.save(rule)
        load()
        lastError = nil
        lastActionMessage = "已保存应用规则"
    }

    func deleteAppStyleRule(id: String) {
        do {
            try appStyleRuleStore.delete(id: id)
            load()
            lastError = nil
            lastActionMessage = "已删除应用规则"
        } catch {
            report(error: error)
        }
    }

    func report(error: Error) {
        lastError = error.localizedDescription
        lastActionMessage = nil
    }

    func clearFeedback() {
        lastError = nil
        lastActionMessage = nil
    }

    func makeSmartConfigurationViewModel() -> SmartConfigurationViewModel {
        SmartConfigurationViewModel(
            environment: environment,
            appProvider: smartConfigurationAppProvider,
            batchClassifier: smartConfigurationClassifierFactory(environment)
        )
    }

    private static func makeDefaultSmartConfigurationClassifier(
        environment: AppEnvironment
    ) -> (any BatchApplicationClassifying)? {
        let refiner = RepositoryBackedLLMRefiner(
            providerRepository: environment.llmProviderRepository,
            credentialStore: environment.credentialStore
        )
        return LLMBatchApplicationClassifier(refiner: refiner)
    }

    private func requireProfile(id: String) throws -> StyleProfileRecord {
        if let profile = try environment.styleRepository.profile(id: id) {
            return profile
        }
        throw StyleViewModelError.profileNotFound
    }

}

enum StyleViewModelError: LocalizedError {
    case profileNotFound
    case applicationIdentityRequired
    case promptRequired

    var errorDescription: String? {
        switch self {
        case .profileNotFound:
            return "风格不存在。"
        case .applicationIdentityRequired:
            return "Bundle ID 和应用名称至少填写一项。"
        case .promptRequired:
            return "提示词不能为空。"
        }
    }
}
