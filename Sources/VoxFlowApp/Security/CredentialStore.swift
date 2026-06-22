import Foundation
import Security
import VoxFlowProviderCloudCore

protocol CredentialStore: AnyObject, CloudASRCredentialReading {
    func readCredential(account: String) throws -> String?
    func saveCredential(_ value: String, account: String) throws
    func deleteCredential(account: String) throws
}

final class AppLocalCredentialStore: CredentialStore, @unchecked Sendable {
    private let logger = AppLogger.general
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
            logger.debug("local_credential_read requested account=\(account)")
            do {
                let credential = try load()[account]
                logger.debug(
                    "local_credential_read_complete account=\(account) found=\(credential != nil)"
                )
                return credential
            } catch {
                logger.error(
                    "local_credential_read_failed account=\(account) error=\(error.localizedDescription)"
                )
                throw error
            }
        }
    }

    func saveCredential(_ value: String, account: String) throws {
        try lock.withLock {
            logger.debug("local_credential_save requested account=\(account)")
            do {
                var credentials = try load()
                credentials[account] = value
                try save(credentials)
                logger.debug("local_credential_save_complete account=\(account)")
            } catch {
                logger.error(
                    "local_credential_save_failed account=\(account) error=\(error.localizedDescription)"
                )
                throw error
            }
        }
    }

    func deleteCredential(account: String) throws {
        try lock.withLock {
            logger.debug("local_credential_delete requested account=\(account)")
            do {
                var credentials = try load()
                credentials.removeValue(forKey: account)
                try save(credentials)
                logger.debug("local_credential_delete_complete account=\(account)")
            } catch {
                logger.error(
                    "local_credential_delete_failed account=\(account) error=\(error.localizedDescription)"
                )
                throw error
            }
        }
    }

    private func load() throws -> [String: String] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            logger.debug("local_credential_load_no_file path=\(fileURL.path)")
            return [:]
        }
        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else {
            logger.debug("local_credential_load_empty_file path=\(fileURL.path)")
            return [:]
        }
        do {
            return try JSONDecoder().decode([String: String].self, from: data)
        } catch {
            logger.error(
                "local_credential_load_decode_failed path=\(fileURL.path) error=\(error.localizedDescription)"
            )
            throw error
        }
    }

    private func save(_ credentials: [String: String]) throws {
        let directory = fileURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(credentials)
            try data.write(to: fileURL, options: [.atomic])
            logger.debug("local_credential_save_file accountCount=\(credentials.count) path=\(fileURL.path)")
        } catch {
            logger.error("local_credential_save_file_failed path=\(fileURL.path) error=\(error.localizedDescription)")
            throw error
        }
    }
}

final class KeychainCredentialStore: CredentialStore {
    private let logger = AppLogger.general
    static let defaultService = "\(ProductBrand.bundleIdentifier).credentials"

    private let service: String

    init(service: String = KeychainCredentialStore.defaultService) {
        self.service = service
    }

    func readCredential(account: String) throws -> String? {
        logger.debug("keychain_credential_read requested account=\(account)")
        var query = baseQuery(account: account)
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            logger.warning(
                "keychain_credential_read_failed account=\(account) status=\(status)"
            )
            throw CredentialStoreError.keychainStatus(status)
        }

        guard let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            logger.error("keychain_credential_read_decode_failed account=\(account)")
            throw CredentialStoreError.invalidData
        }

        logger.debug("keychain_credential_read_complete account=\(account)")
        return value
    }

    func saveCredential(_ value: String, account: String) throws {
        logger.debug("keychain_credential_save requested account=\(account)")
        let data = Data(value.utf8)
        let query = baseQuery(account: account)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            logger.debug("keychain_credential_save_update account=\(account)")
            return
        }

        guard updateStatus == errSecItemNotFound else {
            logger.warning(
                "keychain_credential_save_update_failed account=\(account) status=\(updateStatus)"
            )
            throw CredentialStoreError.keychainStatus(updateStatus)
        }

        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            logger.warning("keychain_credential_save_add_failed account=\(account) status=\(addStatus)")
            throw CredentialStoreError.keychainStatus(addStatus)
        }
        logger.debug("keychain_credential_save_add_complete account=\(account)")
    }

    func deleteCredential(account: String) throws {
        logger.debug("keychain_credential_delete requested account=\(account)")
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            logger.warning("keychain_credential_delete_failed account=\(account) status=\(status)")
            throw CredentialStoreError.keychainStatus(status)
        }
        logger.debug("keychain_credential_delete_complete account=\(account) status=\(status)")
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
