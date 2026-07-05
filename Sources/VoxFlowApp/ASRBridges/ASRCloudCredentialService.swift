import Foundation

final class ASRCloudCredentialService {
    static let groqAPIKeyAccount = "asr.groq.api-key"
    static let legacyGroqAPIKeyAccounts = ["groq-key"]
    static let tencentAppIDAccount = "asr.tencent.app-id"
    static let tencentSecretIDAccount = "asr.tencent.secret-id"
    static let tencentSecretKeyAccount = "asr.tencent.secret-key"
    static let aliyunDashScopeAPIKeyAccount = "asr.aliyun-dashscope.api-key"
    static let volcengineAppIDAccount = "asr.volcengine.app-id"
    static let volcengineAccessTokenAccount = "asr.volcengine.access-token"
    static let volcengineSecretKeyAccount = "asr.volcengine.secret-key"

    private let cloudCredentials: ASRCloudCredentialManager

    init(
        credentialStore: any CredentialStore,
        settingsRepository: (any SettingsRepository)?
    ) {
        cloudCredentials = ASRCloudCredentialManager(
            credentialStore: credentialStore,
            settingsRepository: settingsRepository,
            legacyAccountAliases: [
                Self.groqAPIKeyAccount: Self.legacyGroqAPIKeyAccounts,
            ]
        )
    }

    var credentialStore: any CredentialStore {
        cloudCredentials
    }

    var isGroqConfigured: Bool {
        cloudCredentials.isConfigured(account: Self.groqAPIKeyAccount)
    }

    func storedGroqAPIKey() -> String {
        cloudCredentials.storedCredential(account: Self.groqAPIKeyAccount)
    }

    func saveGroqAPIKey(_ apiKey: String) throws {
        try cloudCredentials.saveCredential(apiKey, account: Self.groqAPIKeyAccount)
    }

    var isTencentCloudConfigured: Bool {
        cloudCredentials.isConfigured(account: Self.tencentAppIDAccount)
            && cloudCredentials.isConfigured(account: Self.tencentSecretIDAccount)
            && cloudCredentials.isConfigured(account: Self.tencentSecretKeyAccount)
    }

    func storedTencentCloudCredentials() -> (appID: String, secretID: String, secretKey: String) {
        (
            cloudCredentials.storedCredential(account: Self.tencentAppIDAccount),
            cloudCredentials.storedCredential(account: Self.tencentSecretIDAccount),
            cloudCredentials.storedCredential(account: Self.tencentSecretKeyAccount)
        )
    }

    func saveTencentCloudCredentials(appID: String, secretID: String, secretKey: String) throws {
        try cloudCredentials.saveCredential(appID, account: Self.tencentAppIDAccount)
        try cloudCredentials.saveCredential(secretID, account: Self.tencentSecretIDAccount)
        try cloudCredentials.saveCredential(secretKey, account: Self.tencentSecretKeyAccount)
    }

    func deleteTencentCloudCredentials() throws {
        try cloudCredentials.deleteCredential(account: Self.tencentAppIDAccount)
        try cloudCredentials.deleteCredential(account: Self.tencentSecretIDAccount)
        try cloudCredentials.deleteCredential(account: Self.tencentSecretKeyAccount)
    }

    var isAliyunDashScopeConfigured: Bool {
        cloudCredentials.isConfigured(account: Self.aliyunDashScopeAPIKeyAccount)
    }

    func storedAliyunDashScopeAPIKey() -> String {
        cloudCredentials.storedCredential(account: Self.aliyunDashScopeAPIKeyAccount)
    }

    func saveAliyunDashScopeAPIKey(_ apiKey: String) throws {
        try cloudCredentials.saveCredential(apiKey, account: Self.aliyunDashScopeAPIKeyAccount)
    }

    var isVolcengineConfigured: Bool {
        cloudCredentials.isConfigured(account: Self.volcengineAppIDAccount)
            && cloudCredentials.isConfigured(account: Self.volcengineAccessTokenAccount)
            && cloudCredentials.isConfigured(account: Self.volcengineSecretKeyAccount)
    }

    func storedVolcengineCredentials() -> (appID: String, accessToken: String, secretKey: String) {
        (
            cloudCredentials.storedCredential(account: Self.volcengineAppIDAccount),
            cloudCredentials.storedCredential(account: Self.volcengineAccessTokenAccount),
            cloudCredentials.storedCredential(account: Self.volcengineSecretKeyAccount)
        )
    }

    func saveVolcengineCredentials(appID: String, accessToken: String, secretKey: String) throws {
        try cloudCredentials.saveCredential(appID, account: Self.volcengineAppIDAccount)
        try cloudCredentials.saveCredential(accessToken, account: Self.volcengineAccessTokenAccount)
        try cloudCredentials.saveCredential(secretKey, account: Self.volcengineSecretKeyAccount)
    }

    func deleteVolcengineCredentials() throws {
        try cloudCredentials.deleteCredential(account: Self.volcengineAppIDAccount)
        try cloudCredentials.deleteCredential(account: Self.volcengineAccessTokenAccount)
        try cloudCredentials.deleteCredential(account: Self.volcengineSecretKeyAccount)
    }
}
