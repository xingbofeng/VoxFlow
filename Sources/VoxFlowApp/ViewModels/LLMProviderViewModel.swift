import Combine
import Foundation

extension Notification.Name {
    static let llmProviderSelectionDidChange = Notification.Name("VoxFlow.LLMProviderSelectionDidChange")
}

@MainActor
final class LLMProviderViewModel: ObservableObject {
    private static let logger = AppLogger.general

    @Published private(set) var providers: [LLMProviderRecord] = []
    @Published private(set) var modelIDsByProviderID: [String: [String]] = [:]
    @Published private(set) var lastConnectionResult: LLMProviderConnectionResult?
    @Published private(set) var lastError: String?
    @Published private(set) var lastActionMessage: String?
    @Published private(set) var testingProviderID: String?
    @Published private(set) var isTestingAllProviders = false
    @Published private(set) var isTestingDraftConnection = false
    @Published private(set) var isFetchingDraftModels = false
    @Published private(set) var codexRuntimeAvailability: AgentRuntimeAvailability?
    @Published private(set) var isCheckingCodexRuntime = false
    @Published private(set) var localAgentAvailabilities: [String: AgentRuntimeAvailability] = [:]
    @Published private(set) var checkingLocalAgentProviderIDs: Set<String> = []
    @Published private(set) var selectedAgentProviderID: String?

    private let environment: any AppServiceProviding
    private let client: any LLMProviderConnecting
    private let codexRuntimeDetector: any AgentRuntimeAvailabilityDetecting
    private let codexModelListProvider: any AgentRuntimeModelListing
    private let localAgentAdapters: [String: any LocalAgentProviderChecking]
    private var cancellables: Set<AnyCancellable> = []
    private var hasLoaded = false

    var defaultProvider: LLMProviderRecord? {
        providers.first {
            $0.isDefault && LLMProviderAvailability.isUsableProvider($0)
        }
    }

    var codexProvider: LLMProviderRecord? {
        providers.first {
            $0.id.caseInsensitiveCompare(AgentProviderRegistry.codex.providerID) == .orderedSame ||
                $0.providerType.caseInsensitiveCompare(AgentProviderRegistry.codex.providerID) == .orderedSame
        }
    }

    var codexEnabled: Bool {
        codexProvider?.enabled ?? false
    }

    var codexSelectedModel: String {
        codexProvider?.defaultModel ?? codexModelIDs.first ?? ""
    }

    var codexModelIDs: [String] {
        localAgentModelIDs(providerID: AgentProviderRegistry.codex.providerID)
    }

    init(
        environment: any AppServiceProviding,
        client: any LLMProviderConnecting = OpenAICompatibleClient(),
        codexRuntimeDetector: (any AgentRuntimeAvailabilityDetecting)? = nil,
        codexModelListProvider: (any AgentRuntimeModelListing)? = nil,
        localAgentAdapters: [String: any LocalAgentProviderChecking]? = nil
    ) {
        self.environment = environment
        self.client = client
        self.codexRuntimeDetector = codexRuntimeDetector ?? CodexRuntimeAvailabilityDetector(clock: environment.clock)
        self.codexModelListProvider = codexModelListProvider ?? CodexRuntimeModelListProvider()
        self.localAgentAdapters = localAgentAdapters ?? Self.defaultLocalAgentAdapters(clock: environment.clock)
        Self.logger.debug("llm_provider_vm_init")
        NotificationCenter.default.publisher(for: .llmProviderSelectionDidChange)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.load()
                }
            }
            .store(in: &cancellables)
        load()
    }

    func load() {
        Self.logger.debug("llm_provider_vm_load_start")
        do {
            try repairDefaultProviderSelectionIfNeeded()
            providers = try environment.llmProviderRepository.list()
            selectedAgentProviderID = try? RepositoryBackedLLMRefiner.agentProviderID(
                settingsRepository: environment.settingsRepository
            )
            hasLoaded = true
            lastError = nil
            Self.logger.info("llm_provider_vm_load_success providers=\(providers.count) defaultCount=\(providers.filter(\.isDefault).count)")
        } catch {
            lastError = error.localizedDescription
            Self.logger.error("llm_provider_vm_load_failed error=\(error.localizedDescription)")
        }
    }

    func detectCodexRuntime(forceRefresh: Bool = true) async {
        Self.logger.debug("llm_provider_vm_detect_codex_runtime_start force=\(forceRefresh)")
        isCheckingCodexRuntime = true
        checkingLocalAgentProviderIDs.insert(AgentProviderRegistry.codex.providerID)
        defer {
            isCheckingCodexRuntime = false
            checkingLocalAgentProviderIDs.remove(AgentProviderRegistry.codex.providerID)
        }
        let availability = await codexRuntimeDetector.cachedOrDetect(forceRefresh: forceRefresh)
        codexRuntimeAvailability = availability
        localAgentAvailabilities[AgentProviderRegistry.codex.providerID] = availability
        if availability.isAvailable {
            var detectedModels: [String] = []
            if let cliPath = availability.cliPath {
                let models = await codexModelListProvider.listModels(cliPath: cliPath)
                detectedModels = models
                if !models.isEmpty {
                    modelIDsByProviderID[AgentProviderRegistry.codex.providerID] = models
                }
            }
            persistDetectedLocalAgentProvider(
                descriptor: AgentProviderRegistry.codex,
                availability: availability,
                modelIDs: detectedModels
            )
            lastError = nil
            lastActionMessage = L10n.localize("model.llm_provider.codex.detect_available", comment: "Codex detect available")
        } else {
            persistUnavailableLocalAgentProvider(
                descriptor: AgentProviderRegistry.codex,
                availability: availability
            )
            lastError = availability.status.reason
        }
        Self.logger.info("llm_provider_vm_detect_codex_runtime_done available=\(availability.isAvailable)")
    }

    func detectLocalAgentProvider(providerID: String, forceRefresh: Bool = true) async {
        if providerID.caseInsensitiveCompare(AgentProviderRegistry.codex.providerID) == .orderedSame {
            await detectCodexRuntime(forceRefresh: forceRefresh)
            return
        }
        guard let descriptor = AgentProviderRegistry.localProvider(for: providerID),
              let adapter = localAgentAdapters[descriptor.providerID] else {
            lastError = LLMProviderViewModelError.providerNotFound.localizedDescription
            return
        }
        checkingLocalAgentProviderIDs.insert(descriptor.providerID)
        defer { checkingLocalAgentProviderIDs.remove(descriptor.providerID) }

        let availability = await adapter.cachedOrDetect(forceRefresh: forceRefresh)
        localAgentAvailabilities[descriptor.providerID] = availability
        if availability.isAvailable {
            var detectedModels: [String] = []
            if let cliPath = availability.cliPath {
                let models = await adapter.listModels(cliPath: cliPath)
                detectedModels = models
                if !models.isEmpty {
                    modelIDsByProviderID[descriptor.providerID] = models
                }
            }
            persistDetectedLocalAgentProvider(
                descriptor: descriptor,
                availability: availability,
                modelIDs: detectedModels
            )
            lastError = nil
            lastActionMessage = L10n.format("model.llm_provider.local_agent.detect_available_format", comment: "", descriptor.displayName)
        } else {
            persistUnavailableLocalAgentProvider(
                descriptor: descriptor,
                availability: availability
            )
            lastError = availability.status.reason
        }
    }

    func setCodexEnabled(_ enabled: Bool) {
        setLocalAgentProviderEnabled(providerID: AgentProviderRegistry.codex.providerID, enabled)
    }

    func setCodexEnabledAfterDetection(_ enabled: Bool) async {
        await setLocalAgentProviderEnabledAfterDetection(
            providerID: AgentProviderRegistry.codex.providerID,
            enabled
        )
    }

    func setLocalAgentProviderEnabledAfterDetection(providerID: String, _ enabled: Bool) async {
        guard enabled else {
            setLocalAgentProviderEnabled(providerID: providerID, false)
            return
        }

        if let provider = localAgentProviderRecord(providerID: providerID),
           provider.enabled,
           provider.lastHealthStatus == "ok",
           provider.hasRequiredLLMConfiguration {
            setLocalAgentProviderEnabled(providerID: providerID, true)
            return
        }

        await detectLocalAgentProvider(providerID: providerID, forceRefresh: true)
        guard localAgentAvailability(providerID: providerID)?.isAvailable == true else {
            return
        }
        setLocalAgentProviderEnabled(providerID: providerID, true)
    }

    func setLocalAgentProviderEnabled(providerID: String, _ enabled: Bool) {
        Self.logger.debug("llm_provider_vm_set_local_agent_enabled providerID=\(providerID) enabled=\(enabled)")
        do {
            guard let descriptor = AgentProviderRegistry.localProvider(for: providerID) else {
                throw LLMProviderViewModelError.providerNotFound
            }
            let selectedModel = localAgentSelectedModel(providerID: descriptor.providerID)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if enabled, selectedModel.isEmpty {
                throw LLMProviderViewModelError.modelRequired
            }
            let provider = try localAgentProviderForSaving(
                descriptor: descriptor,
                enabled: enabled,
                model: selectedModel
            )
            try environment.llmProviderRepository.save(provider)
            if !enabled {
                try clearAgentProviderSelectionIfNeeded(provider)
            } else {
                try setAgentProviderSelection(providerID: descriptor.providerID)
            }
            load()
            notifyProviderSelectionDidChange()
            lastError = nil
            lastActionMessage = enabled
                ? L10n.format("model.llm_provider.local_agent.enabled_format", comment: "", descriptor.displayName)
                : L10n.format("model.llm_provider.local_agent.disabled_format", comment: "", descriptor.displayName)
        } catch {
            report(error: error)
        }
    }

    func selectCodexModel(_ model: String) {
        selectLocalAgentModel(providerID: AgentProviderRegistry.codex.providerID, model: model)
    }

    func selectLocalAgentModel(providerID: String, model: String) {
        let normalized = SingleLineTextInput.normalized(model)
        guard !normalized.isEmpty else { return }
        do {
            guard let descriptor = AgentProviderRegistry.localProvider(for: providerID) else {
                throw LLMProviderViewModelError.providerNotFound
            }
            let provider = try localAgentProviderForSaving(
                descriptor: descriptor,
                enabled: localAgentProviderRecord(providerID: descriptor.providerID)?.enabled ?? false,
                model: normalized
            )
            try environment.llmProviderRepository.save(provider)
            load()
            notifyProviderSelectionDidChange()
            lastError = nil
            lastActionMessage = L10n.format("model.llm_provider.action_model_selected_format", comment: "", normalized)
        } catch {
            report(error: error)
        }
    }

    func localAgentAvailability(providerID: String) -> AgentRuntimeAvailability? {
        localAgentAvailabilities[providerID]
    }

    func localAgentProviderRecord(providerID: String) -> LLMProviderRecord? {
        providers.first {
            $0.id.caseInsensitiveCompare(providerID) == .orderedSame ||
                $0.providerType.caseInsensitiveCompare(providerID) == .orderedSame
        }
    }

    func isLocalAgentProviderSelected(providerID: String) -> Bool {
        guard let provider = localAgentProviderRecord(providerID: providerID) else {
            return false
        }
        return provider.enabled &&
            (provider.id.caseInsensitiveCompare(selectedAgentProviderID ?? "") == .orderedSame ||
             provider.providerType.caseInsensitiveCompare(selectedAgentProviderID ?? "") == .orderedSame)
    }

    func localAgentSelectedModel(providerID: String) -> String {
        localAgentProviderRecord(providerID: providerID)?.defaultModel ??
            localAgentModelIDs(providerID: providerID).first ?? ""
    }

    func localAgentModelIDs(providerID: String) -> [String] {
        let detected = modelIDsByProviderID[providerID] ?? []
        let configured = localAgentProviderRecord(providerID: providerID)?.defaultModel
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Self.uniqueModelIDs(detected + [configured].compactMap { $0?.isEmpty == false ? $0 : nil })
    }

    func loadIfNeeded() {
        guard !hasLoaded else {
            Self.logger.debug("llm_provider_vm_load_if_needed_skip")
            return
        }
        Self.logger.debug("llm_provider_vm_load_if_needed_execute")
        load()
    }

    private static func uniqueModelIDs(_ models: [String]) -> [String] {
        var merged: [String] = []
        for model in models {
            let normalized = OpenAICompatibleClient.normalizedModelID(model)
            guard !normalized.isEmpty, !merged.contains(normalized) else { continue }
            merged.append(normalized)
        }
        return merged
    }

    func saveProvider(
        id: String?,
        displayName: String,
        baseURL: String,
        model: String,
        apiKey: String,
        temperature: Double,
        timeoutSeconds: Double,
        enabled: Bool,
        isDefault: Bool,
        requiresAPIKey: Bool = true
    ) throws {
        Self.logger.debug("llm_provider_vm_save_provider_start isNew=\(id == nil) nameLen=\(displayName.count) modelLen=\(model.count) enabled=\(enabled) requestedDefault=\(isDefault)")
        let trimmedName = SingleLineTextInput.normalized(displayName)
        let trimmedURL = SingleLineTextInput.normalized(baseURL)
        let trimmedModel = OpenAICompatibleClient.normalizedModelID(
            SingleLineTextInput.normalized(model)
        )
        let providerID = id ?? UUID().uuidString
        let now = environment.clock.now
        let existing = try environment.llmProviderRepository.provider(id: providerID)
        let keyRef = existing?.apiKeyRef ?? "llm-provider-\(providerID)"
        let storedKey = try environment.credentialStore.readCredential(account: keyRef)
        let rawKey = SingleLineTextInput.normalized(apiKey)
        let trimmedKey = isMaskedAPIKey(providerID: id, text: rawKey) ? "" : rawKey
        var missingFields: [String] = []
        if trimmedName.isEmpty { missingFields.append(L10n.localize("model.llm_provider.validation_field_name", comment: "")) }
        if trimmedURL.isEmpty { missingFields.append(L10n.localize("model.llm_provider.validation_field_base_url", comment: "")) }
        if trimmedModel.isEmpty { missingFields.append(L10n.localize("model.llm_provider.validation_field_model", comment: "")) }
        if requiresAPIKey && trimmedKey.isEmpty && (storedKey?.isEmpty ?? true) { missingFields.append(L10n.localize("model.llm_provider.validation_field_api_key", comment: "")) }
        guard missingFields.isEmpty else {
            Self.logger.warning("llm_provider_vm_save_provider_rejected missingFields=\(missingFields.count)")
            throw LLMProviderViewModelError.requiredFields(missingFields)
        }
        let hasDefault = try environment.llmProviderRepository.list().contains {
            $0.id != providerID && $0.isDefault && LLMProviderAvailability.isUsableProvider($0)
        }
        if !trimmedKey.isEmpty {
            try environment.credentialStore.saveCredential(trimmedKey, account: keyRef)
        }

        let provider = LLMProviderRecord(
            id: providerID,
            displayName: trimmedName,
            providerType: requiresAPIKey ? LLMProviderProviderType.openAICompatible : LLMProviderProviderType.openAICompatibleNoKey,
            baseURL: try OpenAICompatibleClient.normalizedBaseURL(trimmedURL),
            defaultModel: trimmedModel,
            apiKeyRef: keyRef,
            temperature: temperature,
            timeoutSeconds: timeoutSeconds,
            enabled: enabled,
            isDefault: isDefault || !hasDefault,
            lastHealthStatus: existing?.lastHealthStatus,
            lastHealthMessage: existing?.lastHealthMessage,
            lastLatencyMS: existing?.lastLatencyMS,
            createdAt: existing?.createdAt ?? now,
            updatedAt: now
        )

        try environment.llmProviderRepository.save(provider)
        load()
        notifyProviderSelectionDidChange()
        lastError = nil
        lastActionMessage = L10n.localize("model.llm_provider.action_save_success", comment: "")
        Self.logger.info("llm_provider_vm_save_provider_success id=\(providerID) isDefault=\(provider.isDefault) enabled=\(provider.enabled)")
    }

    func hasStoredAPIKey(providerID: String?) -> Bool {
        guard let providerID,
              let provider = try? environment.llmProviderRepository.provider(id: providerID),
              let credential = try? environment.credentialStore.readCredential(account: provider.apiKeyRef) else {
            return false
        }
        return !credential.isEmpty
    }

    func APIKeyForEditing(providerID: String?) -> String {
        hasStoredAPIKey(providerID: providerID) ? String(repeating: "•", count: 12) : ""
    }

    func storedAPIKeyForEditing(providerID: String?) -> String {
        guard let providerID,
              let provider = try? environment.llmProviderRepository.provider(id: providerID),
              let credential = try? environment.credentialStore.readCredential(account: provider.apiKeyRef) else {
            return ""
        }
        return credential
    }

    /// Returns `true` when the text matches the stored masked representation,
    /// meaning the user did not type a new key.
    func isMaskedAPIKey(providerID: String?, text: String) -> Bool {
        guard let providerID, !text.isEmpty else { return false }
        return text == APIKeyForEditing(providerID: providerID)
    }

    func validationErrors(
        providerID: String?,
        displayName: String,
        baseURL: String,
        model: String,
        apiKey: String,
        requiresAPIKey: Bool = true
    ) -> [String: String] {
        Self.logger.debug("llm_provider_vm_validation_errors_start providerID=\(providerID ?? "nil") nameLen=\(displayName.count) modelLen=\(model.count)")
        var errors: [String: String] = [:]
        let normalizedName = SingleLineTextInput.normalized(displayName)
        let normalizedURL = SingleLineTextInput.normalized(baseURL)
        let normalizedModel = OpenAICompatibleClient.normalizedModelID(
            SingleLineTextInput.normalized(model)
        )
        let normalizedKey = SingleLineTextInput.normalized(apiKey)

        if normalizedName.isEmpty {
            errors["displayName"] = L10n.localize("model.llm_provider.error_name_required", comment: "")
        }
        if (try? OpenAICompatibleClient.normalizedBaseURL(normalizedURL)) == nil {
            errors["baseURL"] = L10n.localize("model.llm_provider.error_base_url_invalid", comment: "")
        }
        if normalizedModel.isEmpty {
            errors["model"] = L10n.localize("model.llm_provider.error_model_required", comment: "")
        }
        let isMasked = isMaskedAPIKey(providerID: providerID, text: normalizedKey)
        if requiresAPIKey && normalizedKey.isEmpty && !hasStoredAPIKey(providerID: providerID) {
            errors["apiKey"] = L10n.localize("model.llm_provider.error_api_key_required", comment: "")
        } else if !normalizedKey.isEmpty && !isMasked && normalizedKey.count < 8 {
            errors["apiKey"] = L10n.localize("model.llm_provider.error_api_key_too_short", comment: "")
        }
        Self.logger.debug("llm_provider_vm_validation_errors_done count=\(errors.count)")
        return errors
    }

    func testDraftConnection(
        providerID: String?,
        displayName: String,
        baseURL: String,
        model: String,
        apiKey: String,
        requiresAPIKey: Bool = true
    ) async {
        Self.logger.debug("llm_provider_vm_test_draft_connection_start providerID=\(providerID ?? "nil") nameLen=\(displayName.count) modelLen=\(model.count)")
        isTestingDraftConnection = true
        lastError = nil
        lastActionMessage = nil
        defer { isTestingDraftConnection = false }

        do {
            let trimmedName = SingleLineTextInput.normalized(displayName)
            let normalizedURL = try OpenAICompatibleClient.normalizedBaseURL(SingleLineTextInput.normalized(baseURL))
            let trimmedModel = OpenAICompatibleClient.normalizedModelID(
                SingleLineTextInput.normalized(model)
            )
            let resolvedKey = try resolvedAPIKey(providerID: providerID, text: apiKey)
            var missingFields: [String] = []
            if trimmedName.isEmpty { missingFields.append(L10n.localize("model.llm_provider.validation_field_name", comment: "")) }
            if trimmedModel.isEmpty { missingFields.append(L10n.localize("model.llm_provider.validation_field_model", comment: "")) }
            if requiresAPIKey && resolvedKey.isEmpty { missingFields.append(L10n.localize("model.llm_provider.validation_field_api_key", comment: "")) }
            guard missingFields.isEmpty else {
                throw LLMProviderViewModelError.requiredFields(missingFields)
            }
            let result = try await client.testConnection(
                baseURL: normalizedURL,
                apiKey: resolvedKey,
                model: trimmedModel,
                timeoutSeconds: 30
            )
            lastConnectionResult = result
            lastError = nil
            lastActionMessage = L10n.localize("model.llm_provider.action_connection_success", comment: "")
            Self.logger.info("llm_provider_vm_test_draft_connection_success latencyMS=\(result.latencyMS)")
        } catch {
            report(error: error)
        }
    }

    func fetchDraftModels(
        providerID: String?,
        baseURL: String,
        apiKey: String,
        requiresAPIKey: Bool = true,
        timeoutSeconds: Double = 30
    ) async -> [String] {
        Self.logger.debug("llm_provider_vm_fetch_draft_models_start providerID=\(providerID ?? "nil")")
        isFetchingDraftModels = true
        lastError = nil
        lastActionMessage = nil
        defer { isFetchingDraftModels = false }

        do {
            let normalizedURL = try OpenAICompatibleClient.normalizedBaseURL(SingleLineTextInput.normalized(baseURL))
            let resolvedKey = try resolvedAPIKey(providerID: providerID, text: apiKey)
            if requiresAPIKey && resolvedKey.isEmpty {
                throw LLMProviderViewModelError.requiredFields([
                    L10n.localize("model.llm_provider.validation_field_api_key", comment: "")
                ])
            }
            if LLMProviderTemplateCatalog.shouldPreferCatalog(baseURL: normalizedURL) {
                let catalogModels = Self.uniqueModelIDs(
                    LLMProviderTemplateCatalog.catalogModelIDs(baseURL: normalizedURL)
                )
                if !catalogModels.isEmpty {
                    if let providerID {
                        modelIDsByProviderID[providerID] = catalogModels
                    }
                    lastError = nil
                    lastActionMessage = L10n.localize("model.llm_provider.action_refresh_models_success", comment: "")
                    Self.logger.info("llm_provider_vm_fetch_draft_models_catalog_success count=\(catalogModels.count)")
                    return catalogModels
                }
            }
            let models: [String]
            do {
                models = try await client.listModels(
                    baseURL: normalizedURL,
                    apiKey: resolvedKey,
                    timeoutSeconds: timeoutSeconds
                )
            } catch {
                let fallbackModels = LLMProviderTemplateCatalog.fallbackModelIDs(baseURL: normalizedURL)
                guard !fallbackModels.isEmpty else { throw error }
                models = fallbackModels
            }
            let uniqueModels = Self.uniqueModelIDs(models)
            if let providerID {
                modelIDsByProviderID[providerID] = uniqueModels
            }
            lastError = nil
            lastActionMessage = L10n.localize("model.llm_provider.action_refresh_models_success", comment: "")
            Self.logger.info("llm_provider_vm_fetch_draft_models_success count=\(uniqueModels.count)")
            return uniqueModels
        } catch {
            report(error: error)
            return []
        }
    }

    func testConnection(id: String) async {
        Self.logger.debug("llm_provider_vm_test_connection_start id=\(id)")
        if id.caseInsensitiveCompare(AgentProviderRegistry.codex.providerID) == .orderedSame {
            await detectCodexRuntime(forceRefresh: true)
            return
        }
        testingProviderID = id
        lastError = nil
        lastActionMessage = nil
        defer {
            if testingProviderID == id {
                testingProviderID = nil
            }
        }

        do {
            let provider = try requireProvider(id: id)
            let result = try await performConnectionTest(provider: provider)
            lastError = nil
            lastActionMessage = L10n.localize("model.llm_provider.action_connection_success", comment: "")
            Self.logger.info("llm_provider_vm_test_connection_success id=\(id) latencyMS=\(result.latencyMS)")
        } catch {
            lastError = error.localizedDescription
            if let provider = try? environment.llmProviderRepository.provider(id: id) {
                try? saveHealth(provider: provider, status: "error", message: error.localizedDescription, latencyMS: nil)
            }
            Self.logger.error("llm_provider_vm_test_connection_failed id=\(id) error=\(error.localizedDescription)")
        }
    }

    func testAllConnections() async {
        Self.logger.debug("llm_provider_vm_test_all_connections_start")
        let providersToTest = providers.filter {
            !$0.isLocalAgentProvider && LLMProviderAvailability.isUsableProvider($0)
        }
        guard !providersToTest.isEmpty else {
            lastActionMessage = nil
            lastError = L10n.localize("model.llm_provider.test_all_empty", comment: "")
            Self.logger.warning("llm_provider_vm_test_all_connections_skipped empty=true")
            return
        }

        isTestingAllProviders = true
        lastError = nil
        lastActionMessage = nil
        var failureCount = 0
        defer {
            isTestingAllProviders = false
            testingProviderID = nil
        }

        for provider in providersToTest {
            testingProviderID = provider.id
            do {
                _ = try await performConnectionTest(provider: provider)
            } catch {
                failureCount += 1
                try? saveHealth(provider: provider, status: "error", message: error.localizedDescription, latencyMS: nil)
                Self.logger.error("llm_provider_vm_test_all_connection_failed id=\(provider.id) error=\(error.localizedDescription)")
            }
        }

        if failureCount == 0 {
            lastError = nil
            lastActionMessage = L10n.format(
                "model.llm_provider.test_all_success_format",
                comment: "",
                providersToTest.count
            )
        } else {
            lastActionMessage = nil
            lastError = L10n.format(
                "model.llm_provider.test_all_partial_failure_format",
                comment: "",
                providersToTest.count,
                failureCount
            )
        }
        Self.logger.info("llm_provider_vm_test_all_connections_done total=\(providersToTest.count) failures=\(failureCount)")
    }

    func refreshModelsAndMeasure(id: String) async {
        Self.logger.debug("llm_provider_vm_refresh_models_start id=\(id)")
        do {
            let provider = try requireProvider(id: id)
            let apiKey = try environment.credentialStore.readCredential(account: provider.apiKeyRef) ?? ""
            let models = try await client.listModels(
                baseURL: provider.baseURL,
                apiKey: apiKey,
                timeoutSeconds: provider.timeoutSeconds
            )
            modelIDsByProviderID[id] = models

            let result = try await client.testConnection(
                baseURL: provider.baseURL,
                apiKey: apiKey,
                model: OpenAICompatibleClient.normalizedModelID(provider.defaultModel),
                timeoutSeconds: provider.timeoutSeconds
            )
            lastConnectionResult = result
            let message = models.isEmpty
                ? result.message
                : L10n.format("model.llm_provider.refresh_models_count_format", comment: "", result.message, models.count)
            try saveHealth(provider: provider, status: "ok", message: message, latencyMS: result.latencyMS)
            lastError = nil
            lastActionMessage = L10n.localize("model.llm_provider.action_refresh_models_success", comment: "")
            Self.logger.info("llm_provider_vm_refresh_models_success id=\(id) models=\(models.count) latencyMS=\(result.latencyMS)")
        } catch {
            lastError = error.localizedDescription
            if let provider = try? environment.llmProviderRepository.provider(id: id) {
                try? saveHealth(provider: provider, status: "error", message: error.localizedDescription, latencyMS: nil)
            }
            Self.logger.error("llm_provider_vm_refresh_models_failed id=\(id) error=\(error.localizedDescription)")
        }
    }

    func selectModel(providerID: String, model: String) throws {
        Self.logger.debug("llm_provider_vm_select_model_start providerID=\(providerID) modelLen=\(model.count)")
        let provider = try requireProvider(id: providerID)
        let selectedModel = OpenAICompatibleClient.normalizedModelID(
            SingleLineTextInput.normalized(model)
        )
        guard !selectedModel.isEmpty else {
            Self.logger.warning("llm_provider_vm_select_model_rejected providerID=\(providerID) emptyModel=true")
            throw LLMProviderViewModelError.modelRequired
        }
        try environment.llmProviderRepository.save(
            LLMProviderRecord(
                id: provider.id,
                displayName: provider.displayName,
                providerType: provider.providerType,
                baseURL: provider.baseURL,
                defaultModel: selectedModel,
                apiKeyRef: provider.apiKeyRef,
                temperature: provider.temperature,
                timeoutSeconds: provider.timeoutSeconds,
                enabled: provider.enabled,
                isDefault: provider.isDefault,
                lastHealthStatus: provider.lastHealthStatus,
                lastHealthMessage: provider.lastHealthMessage,
                lastLatencyMS: provider.lastLatencyMS,
                createdAt: provider.createdAt,
                updatedAt: environment.clock.now
            )
        )
        load()
        notifyProviderSelectionDidChange()
        lastError = nil
        lastActionMessage = L10n.format("model.llm_provider.action_model_selected_format", comment: "", selectedModel)
        Self.logger.info("llm_provider_vm_select_model_success providerID=\(providerID) modelLen=\(selectedModel.count)")
    }

    func setDefaultProvider(id: String) throws {
        Self.logger.debug("llm_provider_vm_set_default_provider_start id=\(id)")
        let selectedProvider = try requireProvider(id: id)
        guard LLMProviderAvailability.isUsableProvider(selectedProvider) else {
            Self.logger.warning("llm_provider_vm_set_default_provider_rejected id=\(id) disabled=true")
            throw LLMProviderViewModelError.providerDisabled
        }
        let now = environment.clock.now
        let updatedProviders = providers.map { provider in
            LLMProviderRecord(
                id: provider.id,
                displayName: provider.displayName,
                providerType: provider.providerType,
                baseURL: provider.baseURL,
                defaultModel: provider.defaultModel,
                apiKeyRef: provider.apiKeyRef,
                temperature: provider.temperature,
                timeoutSeconds: provider.timeoutSeconds,
                enabled: provider.id == id ? true : provider.enabled,
                isDefault: provider.id == id,
                lastHealthStatus: provider.lastHealthStatus,
                lastHealthMessage: provider.lastHealthMessage,
                lastLatencyMS: provider.lastLatencyMS,
                createdAt: provider.createdAt,
                updatedAt: now
            )
        }
        for provider in updatedProviders {
            try environment.llmProviderRepository.save(provider)
        }
        load()
        notifyProviderSelectionDidChange()
        lastError = nil
        lastActionMessage = L10n.localize("model.llm_provider.action_set_default", comment: "")
        Self.logger.info("llm_provider_vm_set_default_provider_success id=\(id)")
    }

    func deleteProvider(id: String) {
        Self.logger.debug("llm_provider_vm_delete_provider_start id=\(id)")
        do {
            if let provider = try environment.llmProviderRepository.provider(id: id) {
                try environment.credentialStore.deleteCredential(account: provider.apiKeyRef)
            }
            try environment.llmProviderRepository.delete(id: id)
            modelIDsByProviderID.removeValue(forKey: id)
            let remaining = try environment.llmProviderRepository.list()
            if !remaining.contains(where: { $0.isDefault && LLMProviderAvailability.isUsableProvider($0) }),
               let fallback = remaining.first(where: LLMProviderAvailability.isUsableProvider) {
                try environment.llmProviderRepository.save(
                    LLMProviderRecord(
                        id: fallback.id,
                        displayName: fallback.displayName,
                        providerType: fallback.providerType,
                        baseURL: fallback.baseURL,
                        defaultModel: fallback.defaultModel,
                        apiKeyRef: fallback.apiKeyRef,
                        temperature: fallback.temperature,
                        timeoutSeconds: fallback.timeoutSeconds,
                        enabled: fallback.enabled,
                        isDefault: true,
                        lastHealthStatus: fallback.lastHealthStatus,
                        lastHealthMessage: fallback.lastHealthMessage,
                        lastLatencyMS: fallback.lastLatencyMS,
                        createdAt: fallback.createdAt,
                        updatedAt: environment.clock.now
                    )
                )
            }
            load()
            notifyProviderSelectionDidChange()
            lastError = nil
            lastActionMessage = L10n.localize("model.llm_provider.action_delete_success", comment: "")
            Self.logger.info("llm_provider_vm_delete_provider_success id=\(id) remaining=\(providers.count)")
        } catch {
            report(error: error)
        }
    }

    func report(error: Error) {
        lastError = error.localizedDescription
        lastActionMessage = nil
        Self.logger.error("llm_provider_vm_error error=\(error.localizedDescription)")
    }

    func clearFeedback() {
        lastError = nil
        lastActionMessage = nil
    }

    private func requireProvider(id: String) throws -> LLMProviderRecord {
        if let provider = try environment.llmProviderRepository.provider(id: id) {
            return provider
        }
        throw LLMProviderViewModelError.providerNotFound
    }

    private func repairDefaultProviderSelectionIfNeeded() throws {
        let providers = try environment.llmProviderRepository.list()
        let fallback = providers.first {
            $0.isDefault && LLMProviderAvailability.isUsableProvider($0)
        } ?? providers.first(where: LLMProviderAvailability.isUsableProvider)
        var changed = false
        for provider in providers {
            let shouldBeDefault = provider.id == fallback?.id
            guard provider.isDefault != shouldBeDefault else { continue }
            try environment.llmProviderRepository.save(
                LLMProviderRecord(
                    id: provider.id,
                    displayName: provider.displayName,
                    providerType: provider.providerType,
                    baseURL: provider.baseURL,
                    defaultModel: provider.defaultModel,
                    apiKeyRef: provider.apiKeyRef,
                    temperature: provider.temperature,
                    timeoutSeconds: provider.timeoutSeconds,
                    enabled: provider.enabled,
                    isDefault: shouldBeDefault,
                    lastHealthStatus: provider.lastHealthStatus,
                    lastHealthMessage: provider.lastHealthMessage,
                    lastLatencyMS: provider.lastLatencyMS,
                    createdAt: provider.createdAt,
                    updatedAt: environment.clock.now
                )
            )
            changed = true
        }
        if changed {
            Self.logger.info("llm_provider_vm_repaired_default_provider_selection")
        }
    }

    private static func defaultLocalAgentAdapters(clock: any AppClock) -> [String: any LocalAgentProviderChecking] {
        Dictionary(
            uniqueKeysWithValues: AgentProviderRegistry.enabledRuntimeProviders.map { descriptor in
                (
                    descriptor.providerID,
                    LocalAgentCLIAdapter(
                        descriptor: descriptor,
                        configuration: .default(for: descriptor),
                        clock: clock
                    ) as any LocalAgentProviderChecking
                )
            }
        )
    }

    private func persistDetectedLocalAgentProvider(
        descriptor: LocalAgentProviderDescriptor,
        availability: AgentRuntimeAvailability,
        modelIDs: [String]
    ) {
        do {
            let existing = try environment.llmProviderRepository.provider(id: descriptor.providerID)
                ?? localAgentProviderRecord(providerID: descriptor.providerID)
            let existingModel = existing?.defaultModel.trimmingCharacters(in: .whitespacesAndNewlines)
            let selectedModel: String
            if descriptor.providerID == AgentProviderRegistry.claude.providerID,
               let detectedModel = modelIDs.first?.trimmingCharacters(in: .whitespacesAndNewlines),
               !detectedModel.isEmpty {
                selectedModel = detectedModel
            } else if let existingModel, !existingModel.isEmpty {
                selectedModel = existingModel
            } else {
                selectedModel = modelIDs.first ?? ""
            }
            guard !selectedModel.isEmpty else { return }
            let now = environment.clock.now
            let provider = LLMProviderRecord(
                id: descriptor.providerID,
                displayName: descriptor.displayName,
                providerType: descriptor.providerID,
                baseURL: descriptor.baseURL,
                defaultModel: selectedModel,
                apiKeyRef: existing?.apiKeyRef ?? "\(descriptor.providerID)-local-runtime",
                temperature: existing?.temperature ?? 0,
                timeoutSeconds: existing?.timeoutSeconds ?? 120,
                enabled: existing?.enabled ?? false,
                isDefault: false,
                lastHealthStatus: "ok",
                lastHealthMessage: availability.cliVersion ?? availability.cliPath,
                lastLatencyMS: existing?.lastLatencyMS,
                createdAt: existing?.createdAt ?? now,
                updatedAt: now
            )
            try environment.llmProviderRepository.save(provider)
            load()
            notifyProviderSelectionDidChange()
        } catch {
            report(error: error)
        }
    }

    private func persistUnavailableLocalAgentProvider(
        descriptor: LocalAgentProviderDescriptor,
        availability: AgentRuntimeAvailability
    ) {
        do {
            guard let existing = try environment.llmProviderRepository.provider(id: descriptor.providerID)
                ?? localAgentProviderRecord(providerID: descriptor.providerID) else {
                return
            }
            try saveHealth(
                provider: existing,
                status: "error",
                message: availability.status.reason,
                latencyMS: nil,
                displayName: descriptor.displayName
            )
            load()
            notifyProviderSelectionDidChange()
        } catch {
            report(error: error)
        }
    }

    private func localAgentProviderForSaving(
        descriptor: LocalAgentProviderDescriptor,
        enabled: Bool,
        model: String
    ) throws -> LLMProviderRecord {
        let existing = try environment.llmProviderRepository.provider(id: descriptor.providerID)
            ?? localAgentProviderRecord(providerID: descriptor.providerID)
        let now = environment.clock.now
        let availability = localAgentAvailabilities[descriptor.providerID]
        return LLMProviderRecord(
            id: descriptor.providerID,
            displayName: descriptor.displayName,
            providerType: descriptor.providerID,
            baseURL: descriptor.baseURL,
            defaultModel: model,
            apiKeyRef: "\(descriptor.providerID)-local-runtime",
            temperature: 0,
            timeoutSeconds: 120,
            enabled: enabled,
            isDefault: false,
            lastHealthStatus: availability.map { $0.isAvailable ? "ok" : "error" } ?? existing?.lastHealthStatus,
            lastHealthMessage: availability?.status.reason ?? existing?.lastHealthMessage,
            lastLatencyMS: existing?.lastLatencyMS,
            createdAt: existing?.createdAt ?? now,
            updatedAt: now
        )
    }

    private func setAgentProviderSelection(providerID: String) throws {
        let data = try JSONEncoder().encode(providerID)
        guard let json = String(data: data, encoding: .utf8) else {
            throw LLMProviderViewModelError.providerNotFound
        }
        try environment.settingsRepository.set(
            RepositoryBackedLLMRefiner.agentProviderIDSettingsKey,
            jsonValue: json
        )
        selectedAgentProviderID = providerID
    }

    private func clearAgentProviderSelectionIfNeeded(_ provider: LLMProviderRecord) throws {
        guard provider.id.caseInsensitiveCompare(selectedAgentProviderID ?? "") == .orderedSame ||
            provider.providerType.caseInsensitiveCompare(selectedAgentProviderID ?? "") == .orderedSame else {
            return
        }
        try environment.settingsRepository.deleteValue(
            forKey: RepositoryBackedLLMRefiner.agentProviderIDSettingsKey
        )
        selectedAgentProviderID = nil
    }

    private func resolvedAPIKey(providerID: String?, text: String) throws -> String {
        let trimmed = SingleLineTextInput.normalized(text)
        guard let providerID,
              (trimmed.isEmpty || isMaskedAPIKey(providerID: providerID, text: trimmed)),
              let provider = try environment.llmProviderRepository.provider(id: providerID) else {
            return trimmed
        }
        return try environment.credentialStore.readCredential(account: provider.apiKeyRef) ?? ""
    }

    private func saveHealth(
        provider: LLMProviderRecord,
        status: String,
        message: String?,
        latencyMS: Int?,
        displayName: String? = nil
    ) throws {
        let updated = LLMProviderRecord(
            id: provider.id,
            displayName: displayName ?? provider.displayName,
            providerType: provider.providerType,
            baseURL: provider.baseURL,
            defaultModel: provider.defaultModel,
            apiKeyRef: provider.apiKeyRef,
            temperature: provider.temperature,
            timeoutSeconds: provider.timeoutSeconds,
            enabled: provider.enabled,
            isDefault: provider.isDefault,
            lastHealthStatus: status,
            lastHealthMessage: message,
            lastLatencyMS: latencyMS,
            createdAt: provider.createdAt,
            updatedAt: environment.clock.now
        )
        try environment.llmProviderRepository.save(updated)
        load()
    }

    private func performConnectionTest(provider: LLMProviderRecord) async throws -> LLMProviderConnectionResult {
        let apiKey = try environment.credentialStore.readCredential(account: provider.apiKeyRef) ?? ""
        let result = try await client.testConnection(
            baseURL: provider.baseURL,
            apiKey: apiKey,
            model: OpenAICompatibleClient.normalizedModelID(provider.defaultModel),
            timeoutSeconds: provider.timeoutSeconds
        )
        lastConnectionResult = result
        try saveHealth(provider: provider, status: "ok", message: result.message, latencyMS: result.latencyMS)
        return result
    }

    private func notifyProviderSelectionDidChange() {
        NotificationCenter.default.post(name: .llmProviderSelectionDidChange, object: nil)
    }
}

enum LLMProviderViewModelError: LocalizedError, Equatable {
    case providerNotFound
    case modelRequired
    case providerDisabled
    case requiredFields([String])

    var errorDescription: String? {
        switch self {
        case .providerNotFound:
            return L10n.localize("model.llm_provider.error_not_found", comment: "")
        case .modelRequired:
            return L10n.localize("model.llm_provider.error_model_name_required", comment: "")
        case .providerDisabled:
            return L10n.localize("model.llm_provider.error_provider_disabled", comment: "")
        case let .requiredFields(fields):
            let separator = L10n.localize("model.llm_provider.required_fields_separator", comment: "")
            return L10n.format("model.llm_provider.error_required_fields_format", comment: "", fields.joined(separator: separator))
        }
    }
}
