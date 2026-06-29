import Foundation
import VoxFlowTextProcessing

/// Adapter that bridges `SettingsRepository` (in VoxFlowApp) to
/// `KeyValueSettingsStorage` (in VoxFlowTextProcessing), avoiding a circular
/// dependency between the two modules.
struct SettingsRepositoryKeyValueAdapter: KeyValueSettingsStorage, @unchecked Sendable {
    private let repository: any SettingsRepository

    init(repository: any SettingsRepository) {
        self.repository = repository
    }

    func value(forKey key: String) throws -> String? {
        try repository.value(forKey: key)
    }

    func set(_ key: String, jsonValue: String) throws {
        try repository.set(key, jsonValue: jsonValue)
    }
}
