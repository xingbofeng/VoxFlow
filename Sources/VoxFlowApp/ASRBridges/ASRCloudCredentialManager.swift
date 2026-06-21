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
        if let keychainValue = try? credentialStore.readCredential(account: account) {
            let value = keychainValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty {
                return value
            }
        }

        return legacySettingsCredential(account: account)
    }

    func readCredential(account: String) throws -> String? {
        let value = storedCredential(account: account)
        return value.isEmpty ? nil : value
    }

    func saveCredential(_ value: String, account: String) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            try credentialStore.deleteCredential(account: account)
        } else {
            try credentialStore.saveCredential(trimmed, account: account)
        }
        try settingsRepository?.deleteValue(forKey: Self.settingsKey(account: account))
    }

    func deleteCredential(account: String) throws {
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
