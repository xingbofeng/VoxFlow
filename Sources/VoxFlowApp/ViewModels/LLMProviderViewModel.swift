import Combine
import Foundation

@MainActor
final class LLMProviderViewModel: ObservableObject {
    @Published private(set) var providers: [LLMProviderRecord] = []
    @Published private(set) var modelIDsByProviderID: [String: [String]] = [:]
    @Published private(set) var lastConnectionResult: LLMProviderConnectionResult?
    @Published private(set) var lastError: String?
    @Published private(set) var lastActionMessage: String?
    @Published private(set) var testingProviderID: String?
    @Published private(set) var isTestingDraftConnection = false

    private let environment: any AppServiceProviding
    private let client: any LLMProviderConnecting

    var defaultProvider: LLMProviderRecord? {
        providers.first(where: \.isDefault)
    }

    init(
        environment: any AppServiceProviding,
        client: any LLMProviderConnecting = OpenAICompatibleClient()
    ) {
        self.environment = environment
        self.client = client
        load()
    }

    func load() {
        do {
            providers = try environment.llmProviderRepository.list()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
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
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let providerID = id ?? UUID().uuidString
        let now = environment.clock.now
        let existing = try environment.llmProviderRepository.provider(id: providerID)
        let keyRef = existing?.apiKeyRef ?? "llm-provider-\(providerID)"
        let storedKey = try environment.credentialStore.readCredential(account: keyRef)
        let rawKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedKey = isMaskedAPIKey(providerID: id, text: rawKey) ? "" : rawKey
        var missingFields: [String] = []
        if trimmedName.isEmpty { missingFields.append("名称") }
        if trimmedURL.isEmpty { missingFields.append("Base URL") }
        if trimmedModel.isEmpty { missingFields.append("Model") }
        if trimmedKey.isEmpty && (storedKey?.isEmpty ?? true) { missingFields.append("API Key") }
        guard missingFields.isEmpty else {
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
        lastActionMessage = "已保存 Provider"
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
        var errors: [String: String] = [:]
        if displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors["displayName"] = "请输入名称"
        }
        if (try? OpenAICompatibleClient.normalizedBaseURL(baseURL)) == nil {
            errors["baseURL"] = "请输入有效的 HTTP 或 HTTPS 地址"
        }
        if model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors["model"] = "请输入模型名称"
        }
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let isMasked = isMaskedAPIKey(providerID: providerID, text: trimmedKey)
        if trimmedKey.isEmpty && !hasStoredAPIKey(providerID: providerID) {
            errors["apiKey"] = "请输入 API Key"
        } else if !trimmedKey.isEmpty && !isMasked && trimmedKey.count < 8 {
            errors["apiKey"] = "API Key 长度不足"
        }
        return errors
    }

    func testDraftConnection(
        providerID: String?,
        displayName: String,
        baseURL: String,
        model: String,
        apiKey: String
    ) async {
        isTestingDraftConnection = true
        lastError = nil
        lastActionMessage = nil
        defer { isTestingDraftConnection = false }

        do {
            let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedURL = try OpenAICompatibleClient.normalizedBaseURL(baseURL)
            let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedKey = try resolvedAPIKey(providerID: providerID, text: apiKey)
            var missingFields: [String] = []
            if trimmedName.isEmpty { missingFields.append("名称") }
            if trimmedModel.isEmpty { missingFields.append("Model") }
            if resolvedKey.isEmpty { missingFields.append("API Key") }
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
            lastActionMessage = "连接测试成功"
        } catch {
            report(error: error)
        }
    }

    func testConnection(id: String) async {
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
            lastActionMessage = "连接测试成功"
        } catch {
            lastError = error.localizedDescription
            if let provider = try? environment.llmProviderRepository.provider(id: id) {
                try? saveHealth(provider: provider, status: "error", message: error.localizedDescription, latencyMS: nil)
            }
        }
    }

    func refreshModelsAndMeasure(id: String) async {
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
                : "\(result.message) · \(models.count) 个模型"
            try saveHealth(provider: provider, status: "ok", message: message, latencyMS: result.latencyMS)
            lastError = nil
            lastActionMessage = "已刷新模型并完成测速"
        } catch {
            lastError = error.localizedDescription
            if let provider = try? environment.llmProviderRepository.provider(id: id) {
                try? saveHealth(provider: provider, status: "error", message: error.localizedDescription, latencyMS: nil)
            }
        }
    }

    func selectModel(providerID: String, model: String) throws {
        let provider = try requireProvider(id: providerID)
        let selectedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !selectedModel.isEmpty else {
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
        lastActionMessage = "已选择全局模型 \(selectedModel)"
    }

    func setDefaultProvider(id: String) throws {
        let selectedProvider = try requireProvider(id: id)
        guard selectedProvider.enabled else {
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
        lastActionMessage = "已设为全局默认模型"
    }

    func deleteProvider(id: String) {
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
            lastActionMessage = "已删除 Provider"
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

    private func requireProvider(id: String) throws -> LLMProviderRecord {
        if let provider = try environment.llmProviderRepository.provider(id: id) {
            return provider
        }
        throw LLMProviderViewModelError.providerNotFound
    }

    private func resolvedAPIKey(providerID: String?, text: String) throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
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
            return "LLM Provider 不存在。"
        case .modelRequired:
            return "模型名称不能为空。"
        case .providerDisabled:
            return "请先启用该 Provider。"
        case let .requiredFields(fields):
            return "请填写必填字段：\(fields.joined(separator: "、"))。"
        }
    }
}
