import Foundation
import Security
import VoxFlowProviderCloudCore

protocol CredentialStore: AnyObject, CloudASRCredentialReading {
    func readCredential(account: String) throws -> String?
    func saveCredential(_ value: String, account: String) throws
    func deleteCredential(account: String) throws
}

final class AppLocalCredentialStore: CredentialStore, @unchecked Sendable {
    private let fileURL: URL
    private let lock = NSLock()

    static func liveDefault() -> CredentialStore {
        if let paths = try? ApplicationSupportPaths.live() {
            return AppLocalCredentialStore(fileURL: paths.credentialsURL)
        }
        let fallbackURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoxFlow", isDirectory: true)
            .appendingPathComponent("credentials.json", isDirectory: false)
        return AppLocalCredentialStore(fileURL: fallbackURL)
    }

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    func readCredential(account: String) throws -> String? {
        try lock.withLock {
            try load()[account]
        }
    }

    func saveCredential(_ value: String, account: String) throws {
        try lock.withLock {
            var credentials = try load()
            credentials[account] = value
            try save(credentials)
        }
    }

    func deleteCredential(account: String) throws {
        try lock.withLock {
            var credentials = try load()
            credentials.removeValue(forKey: account)
            try save(credentials)
        }
    }

    private func load() throws -> [String: String] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return [:]
        }
        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else {
            return [:]
        }
        return try JSONDecoder().decode([String: String].self, from: data)
    }

    private func save(_ credentials: [String: String]) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(credentials)
        try data.write(to: fileURL, options: [.atomic])
    }
}

final class KeychainCredentialStore: CredentialStore {
    static let defaultService = "\(ProductBrand.bundleIdentifier).credentials"

    private let service: String

    init(service: String = KeychainCredentialStore.defaultService) {
        self.service = service
    }

    func readCredential(account: String) throws -> String? {
        var query = baseQuery(account: account)
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw CredentialStoreError.keychainStatus(status)
        }

        guard let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            throw CredentialStoreError.invalidData
        }

        return value
    }

    func saveCredential(_ value: String, account: String) throws {
        let data = Data(value.utf8)
        let query = baseQuery(account: account)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }

        guard updateStatus == errSecItemNotFound else {
            throw CredentialStoreError.keychainStatus(updateStatus)
        }

        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw CredentialStoreError.keychainStatus(addStatus)
        }
    }

    func deleteCredential(account: String) throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CredentialStoreError.keychainStatus(status)
        }
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

enum CredentialStoreError: Error, LocalizedError {
    case keychainStatus(OSStatus)
    case invalidData

    var errorDescription: String? {
        switch self {
        case .keychainStatus(let status):
            if let message = SecCopyErrorMessageString(status, nil) as String? {
                return message
            }
            return "Keychain returned status \(status)."
        case .invalidData:
            return "Keychain item data is not valid UTF-8."
        }
    }
}
