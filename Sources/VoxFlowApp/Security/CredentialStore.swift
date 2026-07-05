import Foundation
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

    var plaintextFileURL: URL {
        fileURL
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
