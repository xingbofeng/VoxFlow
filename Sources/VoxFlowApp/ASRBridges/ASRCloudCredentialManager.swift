import Foundation

final class ASRCloudCredentialManager: CredentialStore, @unchecked Sendable {
    private let credentialStore: any CredentialStore
    private let settingsRepository: (any SettingsRepository)?

    init(
        credentialStore: any CredentialStore,
        settingsRepository: (any SettingsRepository)?
    ) {
        self.credentialStore = credentialStore
        self.settingsRepository = settingsRepository
    }

    func isConfigured(account: String) -> Bool {
        !storedCredential(account: account)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
    }

    func storedCredential(account: String) -> String {
        if let storedValue = try? credentialStore.readCredential(account: account) {
            let value = storedValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty {
                AppLogger.general.debug("Read ASR credential from credential store: account=\(account)")
                return value
            }
        }

        AppLogger.general.debug("Read ASR credential from legacy settings: account=\(account)")
        return legacySettingsCredential(account: account)
    }

    func readCredential(account: String) throws -> String? {
        AppLogger.general.debug("Read ASR credential request: account=\(account)")
        let value = storedCredential(account: account)
        return value.isEmpty ? nil : value
    }

    func saveCredential(_ value: String, account: String) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            try credentialStore.deleteCredential(account: account)
            AppLogger.general.info("Cleared ASR credential: account=\(account)")
        } else {
            try credentialStore.saveCredential(trimmed, account: account)
            AppLogger.general.info("Saved ASR credential: account=\(account), hasValue=true")
        }
        try settingsRepository?.deleteValue(forKey: Self.settingsKey(account: account))
    }

    func deleteCredential(account: String) throws {
        AppLogger.general.info("Delete ASR credential: account=\(account)")
        try saveCredential("", account: account)
    }

    private func legacySettingsCredential(account: String) -> String {
        guard let settingsRepository,
              let json = try? settingsRepository.value(forKey: Self.settingsKey(account: account)),
              let data = json.data(using: .utf8),
              let credential = try? JSONDecoder().decode(StoredCloudCredential.self, from: data) else {
            return ""
        }
        return credential.value
    }

    static func settingsKey(account: String) -> String {
        "ASRManager.cloudCredential.\(account)"
    }

    private struct StoredCloudCredential: Codable {
        let value: String
    }
}
