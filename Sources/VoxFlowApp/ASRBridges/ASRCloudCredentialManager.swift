import Foundation

final class ASRCloudCredentialManager: CredentialStore, @unchecked Sendable {
    private let credentialStore: any CredentialStore
    private let settingsRepository: (any SettingsRepository)?
    private let legacyAccountAliases: [String: [String]]

    init(
        credentialStore: any CredentialStore,
        settingsRepository: (any SettingsRepository)?,
        legacyAccountAliases: [String: [String]] = [:]
    ) {
        self.credentialStore = credentialStore
        self.settingsRepository = settingsRepository
        self.legacyAccountAliases = legacyAccountAliases
    }

    func isConfigured(account: String) -> Bool {
        !storedCredential(account: account)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
    }

    func storedCredential(account: String) -> String {
        for candidateAccount in credentialAccounts(for: account) {
            if let storedValue = try? credentialStore.readCredential(account: candidateAccount) {
                let value = storedValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty {
                    AppLogger.general.debug(
                        "Read ASR credential from credential store: account=\(account), sourceAccount=\(candidateAccount)"
                    )
                    return value
                }
            }
        }

        for candidateAccount in credentialAccounts(for: account) {
            let value = legacySettingsCredential(account: candidateAccount)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty {
                AppLogger.general.debug(
                    "Read ASR credential from legacy settings: account=\(account), sourceAccount=\(candidateAccount)"
                )
                return value
            }
        }

        return ""
    }

    func readCredential(account: String) throws -> String? {
        AppLogger.general.debug("Read ASR credential request: account=\(account)")
        let value = storedCredential(account: account)
        return value.isEmpty ? nil : value
    }

    func saveCredential(_ value: String, account: String) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            for candidateAccount in credentialAccounts(for: account) {
                try credentialStore.deleteCredential(account: candidateAccount)
                try settingsRepository?.deleteValue(forKey: Self.settingsKey(account: candidateAccount))
            }
            AppLogger.general.info("Cleared ASR credential: account=\(account)")
        } else {
            try credentialStore.saveCredential(trimmed, account: account)
            for legacyAccount in legacyAccountAliases[account, default: []] {
                try credentialStore.deleteCredential(account: legacyAccount)
                try settingsRepository?.deleteValue(forKey: Self.settingsKey(account: legacyAccount))
            }
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

    private func credentialAccounts(for account: String) -> [String] {
        var accounts = [account]
        for alias in legacyAccountAliases[account, default: []] where !accounts.contains(alias) {
            accounts.append(alias)
        }
        return accounts
    }

    private struct StoredCloudCredential: Codable {
        let value: String
    }
}
