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

    private let environment: any AppServiceProviding
    private let appStyleRuleStore: AppStyleRuleStore
    private let smartConfigurationAppProvider: any InstalledApplicationProviding
    private let smartConfigurationClassifierFactory: @MainActor (any AppServiceProviding) -> (any BatchApplicationClassifying)?
    private var hasLoaded = false

    init(
        environment: any AppServiceProviding,
        smartConfigurationAppProvider: any InstalledApplicationProviding = FileSystemInstalledApplicationProvider(),
        smartConfigurationClassifierFactory: @escaping @MainActor (any AppServiceProviding) -> (any BatchApplicationClassifying)? = StyleViewModel.makeDefaultSmartConfigurationClassifier
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
            hasLoaded = true
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func loadIfNeeded() {
        guard !hasLoaded else {
            return
        }
        load()
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
        lastActionMessage = L10n.localize("style.feedback.saved", comment: "")
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
        lastActionMessage = L10n.localize("style.feedback.set_default", comment: "")
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
        lastActionMessage = L10n.localize("style.feedback.reset_prompt", comment: "")
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
        lastActionMessage = L10n.localize("style.feedback.app_rule_saved", comment: "")
    }

    func deleteAppStyleRule(id: String) {
        do {
            try appStyleRuleStore.delete(id: id)
            load()
            lastError = nil
            lastActionMessage = L10n.localize("style.feedback.app_rule_deleted", comment: "")
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
        environment: any AppServiceProviding
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
            return L10n.localize("style.error.not_found", comment: "")
        case .applicationIdentityRequired:
            return L10n.localize("style.error.application_identity_required", comment: "")
        case .promptRequired:
            return L10n.localize("style.error.prompt_required", comment: "")
        }
    }
}
