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

    /// 自动匹配 Sheet 状态 (OpenSpec §4.5/§4.6)。普通 UI 只读显示摘要；编辑态
    /// 在 Sheet 内完成。`globalAutoMatchEnabled` 控制全局 AI 智能挑选，关闭时
    /// 所有 style 都不进入 router 候选（Phase 5 起在 selector 中生效）。
    @Published private(set) var autoMatchSettings: StyleAutoMatchSettings = .init()
    @Published var isGeneratingAutoMatchDescription = false

    private let environment: any AppServiceProviding
    private let appStyleRuleStore: AppStyleRuleStore
    private let autoMatchSettingsStore: StyleAutoMatchSettingsStore
    private let smartConfigurationAppProvider: any InstalledApplicationProviding
    private let smartConfigurationClassifierFactory: @MainActor (any AppServiceProviding) -> (any BatchApplicationClassifying)?
    private let autoMatchDescriptionGeneratorFactory: @MainActor (any AppServiceProviding) -> (any PromptAwareTextRefining)?
    private var hasLoaded = false

    init(
        environment: any AppServiceProviding,
        smartConfigurationAppProvider: any InstalledApplicationProviding = FileSystemInstalledApplicationProvider(),
        smartConfigurationClassifierFactory: @escaping @MainActor (any AppServiceProviding) -> (any BatchApplicationClassifying)? = StyleViewModel.makeDefaultSmartConfigurationClassifier,
        autoMatchDescriptionGeneratorFactory: @escaping @MainActor (any AppServiceProviding) -> (any PromptAwareTextRefining)? = StyleViewModel.makeDefaultAutoMatchDescriptionRefiner
    ) {
        self.environment = environment
        self.appStyleRuleStore = AppStyleRuleStore(settingsRepository: environment.settingsRepository)
        self.autoMatchSettingsStore = StyleAutoMatchSettingsStore(settingsRepository: environment.settingsRepository)
        self.smartConfigurationAppProvider = smartConfigurationAppProvider
        self.smartConfigurationClassifierFactory = smartConfigurationClassifierFactory
        self.autoMatchDescriptionGeneratorFactory = autoMatchDescriptionGeneratorFactory
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
            autoMatchSettings = autoMatchSettingsStore.load()
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
                updatedAt: environment.clock.now,
                outputFormat: existing.outputFormat,
                allowAutoMatch: existing.allowAutoMatch,
                autoMatchDescription: existing.autoMatchDescription
            )
        )
        load()
        lastError = nil
        lastActionMessage = L10n.localize("style.feedback.saved", comment: "")
    }

    /// 保存某个 style 的自动匹配设置（OpenSpec §4.4）：是否允许 AI 自动选中此
    /// style，以及供 router 理解的一句话简介。`autoMatchDescription` 允许为空，
    /// 但只有非空简介 + `allowAutoMatch=true` 才会让该 style 进入 router 候选。
    func updateAutoMatchSettings(
        id: String,
        allowAutoMatch: Bool,
        autoMatchDescription: String?
    ) throws {
        let existing = try requireProfile(id: id)
        let trimmedDescription = autoMatchDescription?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedDescription = (trimmedDescription?.isEmpty ?? true) ? nil : trimmedDescription
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
                isDefault: existing.isDefault,
                createdAt: existing.createdAt,
                updatedAt: environment.clock.now,
                outputFormat: existing.outputFormat,
                allowAutoMatch: allowAutoMatch,
                autoMatchDescription: normalizedDescription
            )
        )
        load()
        lastError = nil
        lastActionMessage = L10n.localize("style.feedback.auto_match_saved", comment: "")
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
                updatedAt: environment.clock.now,
                outputFormat: existing.outputFormat,
                allowAutoMatch: existing.allowAutoMatch,
                autoMatchDescription: existing.autoMatchDescription
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
                updatedAt: environment.clock.now,
                outputFormat: catalog.outputFormat,
                allowAutoMatch: existing.allowAutoMatch,
                autoMatchDescription: existing.autoMatchDescription
            )
        )
        try restoreBuiltInDefaultAppRules(styleID: id)
        load()
        lastError = nil
        lastActionMessage = L10n.localize("style.feedback.reset_prompt", comment: "")
    }

    func updateOutputFormat(
        id: String,
        outputFormat: StyleOutputFormat
    ) throws {
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
                isDefault: existing.isDefault,
                createdAt: existing.createdAt,
                updatedAt: environment.clock.now,
                outputFormat: outputFormat,
                allowAutoMatch: existing.allowAutoMatch,
                autoMatchDescription: existing.autoMatchDescription
            )
        )
        load()
        lastError = nil
        lastActionMessage = L10n.localize("style.feedback.output_format_saved", comment: "")
    }

    /// 保存全局 AI 智能挑选开关 (OpenSpec §4.6)。
    func saveGlobalAutoMatchEnabled(_ enabled: Bool) {
        autoMatchSettings.globalEnabled = enabled
        do {
            try autoMatchSettingsStore.save(autoMatchSettings)
            lastError = nil
            lastActionMessage = L10n.localize(
                enabled ? "style.feedback.auto_match_global_on" : "style.feedback.auto_match_global_off",
                comment: ""
            )
        } catch {
            report(error: error)
        }
    }

    func updateAutoMatchConfiguration(
        profileID id: String,
        contextRounds: ContextRoundsSettings,
        autoMatchDescription: String?
    ) throws {
        var settings = autoMatchSettings
        settings.contextRounds = contextRounds
        try autoMatchSettingsStore.save(settings)
        autoMatchSettings = settings
        let existing = try requireProfile(id: id)
        try updateAutoMatchSettings(
            id: id,
            allowAutoMatch: existing.allowAutoMatch,
            autoMatchDescription: autoMatchDescription
        )
    }

    /// 调用 LLM 为指定 style 生成一句话简介 (OpenSpec §4.6 — "AI 生成入口")。
    /// 失败、未配置 LLM 或空返回都会回写 `lastError`，并保留用户已有简介。
    /// 成功时把生成结果写入 style 持久化并刷新 `profiles`。
    func generateAutoMatchDescription(forProfileID id: String) async {
        guard let profile = try? requireProfile(id: id) else {
            report(error: StyleViewModelError.profileNotFound)
            return
        }
        guard let refiner = autoMatchDescriptionGeneratorFactory(environment) else {
            report(error: StyleViewModelError.autoMatchDescriptionUnavailable)
            return
        }
        isGeneratingAutoMatchDescription = true
        defer { isGeneratingAutoMatchDescription = false }
        do {
            guard let generated = try await StyleAutoMatchDescriptionGenerator(refiner: refiner)
                .generate(for: profile) else {
                report(error: StyleViewModelError.autoMatchDescriptionUnavailable)
                return
            }
            try updateAutoMatchSettings(
                id: id,
                allowAutoMatch: profile.allowAutoMatch,
                autoMatchDescription: generated
            )
        } catch {
            report(error: error)
        }
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

    func refreshAfterSmartConfigurationApplied(primaryStyleID: String?) {
        load()
        guard
            let primaryStyleID,
            let appliedProfile = profiles.first(where: { $0.id == primaryStyleID })
        else {
            return
        }
        selectedProfile = appliedProfile
    }

    var canLaunchSmartConfiguration: Bool {
        smartConfigurationClassifierFactory(environment)?.isConfigured == true
    }

    func reportSmartConfigurationConfigurationRequired() {
        lastError = L10n.localize("smart.config.error_llm_required", comment: "")
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

    private static func makeDefaultAutoMatchDescriptionRefiner(
        environment: any AppServiceProviding
    ) -> (any PromptAwareTextRefining)? {
        RepositoryBackedLLMRefiner(
            providerRepository: environment.llmProviderRepository,
            credentialStore: environment.credentialStore
        )
    }

    private func requireProfile(id: String) throws -> StyleProfileRecord {
        if let profile = try environment.styleRepository.profile(id: id) {
            return profile
        }
        throw StyleViewModelError.profileNotFound
    }

    private func restoreBuiltInDefaultAppRules(styleID: String) throws {
        let installedAppsByBundleID = Dictionary(
            smartConfigurationAppProvider.scanInstalledApplications().compactMap { app -> (String, InstalledApplication)? in
                guard let bundleID = Self.normalizedIdentity(app.bundleID) else { return nil }
                return (bundleID, app)
            },
            uniquingKeysWith: { first, _ in first }
        )
        let builtInEntries = KnownApplicationRegistry.builtIn().entries.filter { $0.suggestedStyleID == styleID }
        let builtInBundleIDs = Set(builtInEntries.compactMap { Self.normalizedIdentity($0.bundleID) })
        var restoredRules = try appStyleRuleStore.list().filter { rule in
            if rule.styleID == styleID {
                return false
            }
            guard let bundleID = Self.normalizedIdentity(rule.bundleID) else {
                return true
            }
            return !builtInBundleIDs.contains(bundleID)
        }

        for entry in builtInEntries {
            guard
                let key = Self.normalizedIdentity(entry.bundleID),
                let app = installedAppsByBundleID[key]
            else {
                continue
            }

            restoredRules.append(
                AppStyleRule(
                    id: UUID().uuidString,
                    bundleID: entry.bundleID,
                    appName: app.name,
                    styleID: styleID
                )
            )
        }
        try appStyleRuleStore.replaceAll(restoredRules)
        try autoMatchSettingsStore.update { settings in
            settings.routeCache = settings.routeCache.filter { key, entry in
                if entry.styleID == styleID {
                    return false
                }
                guard let bundleID = Self.normalizedRouteCacheBundleID(key) else {
                    return true
                }
                return !builtInBundleIDs.contains(bundleID)
            }
        }
    }

    private static func normalizedIdentity(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else { return nil }
        return trimmed.lowercased()
    }

    private static func normalizedRouteCacheBundleID(_ key: String) -> String? {
        guard key.hasPrefix("bundle:") else { return nil }
        return normalizedIdentity(String(key.dropFirst("bundle:".count)))
    }

}

enum StyleViewModelError: LocalizedError {
    case profileNotFound
    case applicationIdentityRequired
    case promptRequired
    case autoMatchDescriptionUnavailable

    var errorDescription: String? {
        switch self {
        case .profileNotFound:
            return L10n.localize("style.error.not_found", comment: "")
        case .applicationIdentityRequired:
            return L10n.localize("style.error.application_identity_required", comment: "")
        case .promptRequired:
            return L10n.localize("style.error.prompt_required", comment: "")
        case .autoMatchDescriptionUnavailable:
            return L10n.localize("style.error.auto_match_description_unavailable", comment: "")
        }
    }
}
