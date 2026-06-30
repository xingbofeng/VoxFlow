import Foundation
import VoxFlowProviderAliyunDashScope
import VoxFlowProviderCloudCore
import VoxFlowProviderGroq
import VoxFlowProviderTencentCloud
import VoxFlowProviderVolcengine

struct GroqASRConfigurationInputState {
    let apiKeyInput: String
    let baseURLInput: String
    let modelInput: String
}

struct TencentCloudASRConfigurationInputState {
    let appIDInput: String
    let secretIDInput: String
    let secretKeyInput: String
    let engineModelTypeInput: String
}

struct AliyunDashScopeASRConfigurationInputState {
    let apiKeyInput: String
    let modelInput: String
    let vocabularyIDInput: String
}

struct VolcengineASRConfigurationInputState {
    let appIDInput: String
    let accessTokenInput: String
    let secretKeyInput: String
}

@MainActor
final class ASRProviderConfigurationService {
    private let asrManager: ASRManager

    init(asrManager: ASRManager) {
        self.asrManager = asrManager
    }

    func saveGroqConfiguration(
        apiKeyInput: String,
        baseURLInput: String,
        modelInput: String,
        apiKeyMask: String,
        supportedModels: [GroqASRModelOption]
    ) throws -> GroqASRConfigurationInputState {
        let baseURL = baseURLInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: baseURL),
              components.scheme == "https",
              components.host != nil else {
            throw GroqASRConfigurationError.invalidHTTPSURL
        }
        let model = modelInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else {
            throw GroqASRConfigurationError.emptyModel
        }
        guard supportedModels.contains(where: { $0.id == model }) else {
            throw GroqASRConfigurationError.unsupportedModel
        }
        let key = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if !key.isEmpty && key != apiKeyMask {
            try asrManager.saveGroqAPIKey(key)
        } else if !asrManager.isGroqConfigured {
            throw CloudASRClientError.missingCredential
        }
        asrManager.groqBaseURL = baseURL
        asrManager.groqModel = model
        return GroqASRConfigurationInputState(
            apiKeyInput: apiKeyMask,
            baseURLInput: baseURL,
            modelInput: model
        )
    }

    func testGroqConnection() async throws -> ASRProviderHealthResult {
        try await asrManager.testGroqConnection()
    }

    func deleteGroqAPIKey() throws {
        try asrManager.saveGroqAPIKey("")
    }

    func saveTencentCloudConfiguration(
        appIDInput: String,
        secretIDInput: String,
        secretKeyInput: String,
        secretMask: String
    ) throws -> TencentCloudASRConfigurationInputState {
        let stored = asrManager.storedTencentCloudCredentials()
        let appID = try resolvedTencentValue(
            input: appIDInput,
            stored: stored.appID,
            secretMask: secretMask,
            missingError: TencentCloudASRConfigurationError.emptyAppID
        )
        let secretID = try resolvedTencentValue(
            input: secretIDInput,
            stored: stored.secretID,
            secretMask: secretMask,
            missingError: TencentCloudASRConfigurationError.emptySecretID
        )
        let secretKey = try resolvedTencentValue(
            input: secretKeyInput,
            stored: stored.secretKey,
            secretMask: secretMask,
            missingError: TencentCloudASRConfigurationError.emptySecretKey
        )
        try asrManager.saveTencentCloudCredentials(
            appID: appID,
            secretID: secretID,
            secretKey: secretKey
        )
        asrManager.tencentRealtimeEngineModelType = TencentRealtimeASRConfiguration.defaultEngineModelType
        return TencentCloudASRConfigurationInputState(
            appIDInput: appID,
            secretIDInput: secretID,
            secretKeyInput: secretMask,
            engineModelTypeInput: TencentRealtimeASRConfiguration.defaultEngineModelType
        )
    }

    func testTencentCloudConnection() async throws -> ASRProviderHealthResult {
        try await asrManager.testTencentCloudConnection()
    }

    func deleteTencentCloudCredentials() throws {
        try asrManager.deleteTencentCloudCredentials()
    }

    func saveAliyunDashScopeConfiguration(
        apiKeyInput: String,
        apiKeyMask: String,
        vocabularyIDInput: String = ""
    ) throws -> AliyunDashScopeASRConfigurationInputState {
        let key = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if !key.isEmpty && key != apiKeyMask {
            try asrManager.saveAliyunDashScopeAPIKey(key)
        } else if !asrManager.isAliyunDashScopeConfigured {
            throw AliyunDashScopeASRConfigurationError.emptyAPIKey
        }
        asrManager.aliyunDashScopeModel = AliyunDashScopeRealtimeASRConfiguration.defaultModel
        asrManager.aliyunDashScopeVocabularyID = vocabularyIDInput
        return AliyunDashScopeASRConfigurationInputState(
            apiKeyInput: apiKeyMask,
            modelInput: AliyunDashScopeRealtimeASRConfiguration.defaultModel,
            vocabularyIDInput: asrManager.aliyunDashScopeVocabularyID
        )
    }

    func testAliyunDashScopeConnection() async throws -> ASRProviderHealthResult {
        try await asrManager.testAliyunDashScopeConnection()
    }

    func deleteAliyunDashScopeAPIKey() throws {
        try asrManager.saveAliyunDashScopeAPIKey("")
    }

    func saveVolcengineConfiguration(
        appIDInput: String,
        accessTokenInput: String,
        secretKeyInput: String,
        secretMask: String
    ) throws -> VolcengineASRConfigurationInputState {
        let stored = asrManager.storedVolcengineCredentials()
        let appID = try resolvedCloudCredentialValue(
            input: appIDInput,
            stored: stored.appID,
            secretMask: secretMask,
            missingError: VolcengineASRConfigurationError.emptyAppID
        )
        let accessToken = try resolvedCloudCredentialValue(
            input: accessTokenInput,
            stored: stored.accessToken,
            secretMask: secretMask,
            missingError: VolcengineASRConfigurationError.emptyAccessToken
        )
        let secretKey = try resolvedCloudCredentialValue(
            input: secretKeyInput,
            stored: stored.secretKey,
            secretMask: secretMask,
            missingError: VolcengineASRConfigurationError.emptySecretKey
        )
        try asrManager.saveVolcengineCredentials(
            appID: appID,
            accessToken: accessToken,
            secretKey: secretKey
        )
        return VolcengineASRConfigurationInputState(
            appIDInput: appID,
            accessTokenInput: secretMask,
            secretKeyInput: secretMask
        )
    }

    func testVolcengineConnection() async throws -> ASRProviderHealthResult {
        try await asrManager.testVolcengineConnection()
    }

    func deleteVolcengineCredentials() throws {
        try asrManager.deleteVolcengineCredentials()
    }

    private func resolvedTencentValue(
        input: String,
        stored: String,
        secretMask: String,
        missingError: TencentCloudASRConfigurationError
    ) throws -> String {
        try resolvedCloudCredentialValue(
            input: input,
            stored: stored,
            secretMask: secretMask,
            missingError: missingError
        )
    }

    private func resolvedCloudCredentialValue<E: Error>(
        input: String,
        stored: String,
        secretMask: String,
        missingError: E
    ) throws -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == secretMask, !stored.isEmpty {
            return stored
        }
        if !trimmed.isEmpty {
            return trimmed
        }
        if !stored.isEmpty {
            return stored
        }
        throw missingError
    }
}
