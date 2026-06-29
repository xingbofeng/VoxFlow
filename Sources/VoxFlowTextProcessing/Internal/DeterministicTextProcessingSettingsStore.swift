import Foundation

/// Generic key-value settings storage protocol used by the deterministic
/// text processing store. `VoxFlowApp`'s `SettingsRepository` conforms to
/// this via a thin adapter, avoiding a circular dependency between
/// `VoxFlowTextProcessing` and `VoxFlowApp`.
public protocol KeyValueSettingsStorage: Sendable {
    func value(forKey key: String) throws -> String?
    func set(_ key: String, jsonValue: String) throws
}
/// Persistence layer for `DeterministicTextProcessingSettings`.
///
/// Settings are serialized as JSON and stored via a `KeyValueSettingsStorage`.
/// Reads fall back to `.defaults` when the key is missing or decoding fails.
///
/// Migration: payloads saved before schema version 1 (when every toggle
/// defaulted to off) are detected and replaced with `.defaults` on the next
/// load. This upgrades existing users to the new "sensible defaults" behavior
/// (master on, all processors on except longSentenceBreaking) without
/// requiring them to open settings and re-toggle. After migration the payload
/// carries `schemaVersion = 1` so subsequent loads skip the migration check.
public enum DeterministicTextProcessingSettingsStore {
    public static let settingsKey = "settings.deterministicTextProcessing"

    public static func load(storage: any KeyValueSettingsStorage) -> DeterministicTextProcessingSettings {
        let json: String?
        do {
            json = try storage.value(forKey: settingsKey)
        } catch {
            return .defaults
        }
        guard let json, let data = json.data(using: .utf8) else {
            // No saved payload → use defaults.
            return .defaults
        }
        guard let decoded = try? JSONDecoder().decode(DeterministicTextProcessingSettings.self, from: data) else {
            return .defaults
        }
        // Legacy migration: payloads saved before schemaVersion existed (or
        // with schemaVersion == 0) used all-off defaults. If the user never
        // explicitly enabled anything, migrate them to the new defaults so
        // they get the improved out-of-box experience without manual toggling.
        // We detect "never explicitly configured" by checking that every
        // toggle is off — the legacy default signature. If any toggle is on,
        // the user made an explicit choice and we preserve it.
        if decoded.schemaVersion < DeterministicTextProcessingSettings.currentSchemaVersion,
           !decoded.enabled,
           !decoded.smartNumberRecognition,
           !decoded.punctuationOptimization,
           !decoded.longSentenceBreaking,
           !decoded.fillerWordFiltering,
           !decoded.cjkLatinSpacing,
           !decoded.autoCapitalization {
            let migrated = DeterministicTextProcessingSettings.defaults
            // Best-effort persist the migrated settings so we don't re-run
            // this check on every load. Ignore failures — the in-memory
            // migrated value is still returned to the caller.
            try? save(migrated, storage: storage)
            return migrated
        }
        return decoded
    }

    public static func save(
        _ settings: DeterministicTextProcessingSettings,
        storage: any KeyValueSettingsStorage
    ) throws {
        let data = try JSONEncoder().encode(settings)
        guard let json = String(data: data, encoding: .utf8) else { return }
        try storage.set(settingsKey, jsonValue: json)
    }
}
