import Combine
import Foundation

@MainActor
final class LLMProviderViewModel: ObservableObject {
    private static let logger = AppLogger.general

    @Published private(set) var providers: [LLMProviderRecord] = []
    @Published private(set) var modelIDsByProviderID: [String: [String]] = [:]
    @Published private(set) var lastConnectionResult: LLMProviderConnectionResult?
    @Published private(set) var lastError: String?
    @Published private(set) var lastActionMessage: String?
    @Published private(set) var testingProviderID: String?
    @Published private(set) var isTestingDraftConnection = false

    private let environment: any AppServiceProviding
    private let client: any LLMProviderConnecting
    private var hasLoaded = false

    var defaultProvider: LLMProviderRecord? {
        providers.first(where: \.isDefault)
    }

    init(
        environment: any AppServiceProviding,
        client: any LLMProviderConnecting = OpenAICompatibleClient()
    ) {
        self.environment = environment
        self.client = client
        Self.logger.debug("llm_provider_vm_init")
        load()
    }

    func load() {
        Self.logger.debug("llm_provider_vm_load_start")
        do {
            providers = try environment.llmProviderRepository.list()
            hasLoaded = true
            lastError = nil
            Self.logger.info("llm_provider_vm_load_success providers=\(providers.count) defaultCount=\(providers.filter(\.isDefault).count)")
        } catch {
            lastError = error.localizedDescription
            Self.logger.error("llm_provider_vm_load_failed error=\(error.localizedDescription)")
        }
    }

    func loadIfNeeded() {
        guard !hasLoaded else {
            Self.logger.debug("llm_provider_vm_load_if_needed_skip")
            return
        }
        Self.logger.debug("llm_provider_vm_load_if_needed_execute")
        load()
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
        isDefault: Bool
    ) throws {
        Self.logger.debug("llm_provider_vm_save_provider_start isNew=\(id == nil) nameLen=\(displayName.count) modelLen=\(model.count) enabled=\(enabled) requestedDefault=\(isDefault)")
        let trimmedName = SingleLineTextInput.normalized(displayName)
        let trimmedURL = SingleLineTextInput.normalized(baseURL)
        let trimmedModel = SingleLineTextInput.normalized(model)
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
        if trimmedKey.isEmpty && (storedKey?.isEmpty ?? true) { missingFields.append(L10n.localize("model.llm_provider.validation_field_api_key", comment: "")) }
        guard missingFields.isEmpty else {
            Self.logger.warning("llm_provider_vm_save_provider_rejected missingFields=\(missingFields.count)")
            throw LLMProviderViewModelError.requiredFields(missingFields)
        }
        let hasDefault = try environment.llmProviderRepository.list().contains {
            $0.isDefault && $0.id != providerID
        }
        if !trimmedKey.isEmpty {
            try environment.credentialStore.saveCredential(trimmedKey, account: keyRef)
        }

        let provider = LLMProviderRecord(
            id: providerID,
            displayName: trimmedName,
            providerType: "openaiCompatible",
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
        apiKey: String
    ) -> [String: String] {
        Self.logger.debug("llm_provider_vm_validation_errors_start providerID=\(providerID ?? "nil") nameLen=\(displayName.count) modelLen=\(model.count)")
        var errors: [String: String] = [:]
        let normalizedName = SingleLineTextInput.normalized(displayName)
        let normalizedURL = SingleLineTextInput.normalized(baseURL)
        let normalizedModel = SingleLineTextInput.normalized(model)
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
        if normalizedKey.isEmpty && !hasStoredAPIKey(providerID: providerID) {
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
        apiKey: String
    ) async {
        Self.logger.debug("llm_provider_vm_test_draft_connection_start providerID=\(providerID ?? "nil") nameLen=\(displayName.count) modelLen=\(model.count)")
        isTestingDraftConnection = true
        lastError = nil
        lastActionMessage = nil
        defer { isTestingDraftConnection = false }

        do {
            let trimmedName = SingleLineTextInput.normalized(displayName)
            let normalizedURL = try OpenAICompatibleClient.normalizedBaseURL(SingleLineTextInput.normalized(baseURL))
            let trimmedModel = SingleLineTextInput.normalized(model)
            let resolvedKey = try resolvedAPIKey(providerID: providerID, text: apiKey)
            var missingFields: [String] = []
            if trimmedName.isEmpty { missingFields.append(L10n.localize("model.llm_provider.validation_field_name", comment: "")) }
            if trimmedModel.isEmpty { missingFields.append(L10n.localize("model.llm_provider.validation_field_model", comment: "")) }
            if resolvedKey.isEmpty { missingFields.append(L10n.localize("model.llm_provider.validation_field_api_key", comment: "")) }
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

    func testConnection(id: String) async {
        Self.logger.debug("llm_provider_vm_test_connection_start id=\(id)")
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
            let apiKey = try environment.credentialStore.readCredential(account: provider.apiKeyRef) ?? ""
            let result = try await client.testConnection(
                baseURL: provider.baseURL,
                apiKey: apiKey,
                model: provider.defaultModel,
                timeoutSeconds: provider.timeoutSeconds
            )
            lastConnectionResult = result
            try saveHealth(provider: provider, status: "ok", message: result.message, latencyMS: result.latencyMS)
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
                model: provider.defaultModel,
                timeoutSeconds: provider.timeoutSeconds
            )
            lastConnectionResult = result
            let message = models.isEmpty
                ? result.message
                : String(format: L10n.localize("model.llm_provider.refresh_models_count_format", comment: ""), result.message, models.count)
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
        let selectedModel = SingleLineTextInput.normalized(model)
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
        lastError = nil
        lastActionMessage = String(format: L10n.localize("model.llm_provider.action_model_selected_format", comment: ""), selectedModel)
        Self.logger.info("llm_provider_vm_select_model_success providerID=\(providerID) modelLen=\(selectedModel.count)")
    }

    func setDefaultProvider(id: String) throws {
        Self.logger.debug("llm_provider_vm_set_default_provider_start id=\(id)")
        let selectedProvider = try requireProvider(id: id)
        guard selectedProvider.enabled else {
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
                enabled: provider.enabled,
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
            if !remaining.contains(where: \.isDefault),
               let fallback = remaining.first(where: \.enabled) {
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
        latencyMS: Int?
    ) throws {
        let updated = LLMProviderRecord(
            id: provider.id,
            displayName: provider.displayName,
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
            return String(format: L10n.localize("model.llm_provider.error_required_fields_format", comment: ""), fields.joined(separator: separator))
        }
    }
}
