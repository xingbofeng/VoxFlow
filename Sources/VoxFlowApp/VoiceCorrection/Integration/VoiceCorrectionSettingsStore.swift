import Foundation

enum VoiceCorrectionSettingsKey: String, CaseIterable {
    case enabled = "settings.voiceCorrection.enabled"
    case autoLearningEnabled = "settings.voiceCorrection.autoLearningEnabled"
    case autoLearningAppliesImmediately = "settings.voiceCorrection.autoLearningAppliesImmediately"
    case shadowMode = "settings.voiceCorrection.shadowMode"

    var defaultValue: Bool {
        switch self {
        case .enabled, .autoLearningEnabled, .autoLearningAppliesImmediately:
            return true
        case .shadowMode:
            return false
        }
    }
}

enum VoiceCorrectionSettingsStore {
    private static let logger = AppLogger.general

    private struct StoredBool: Codable {
        let value: Bool
    }

    static func bool(
        _ key: VoiceCorrectionSettingsKey,
        repository: any SettingsRepository
    ) throws -> Bool {
        Self.logger.debug("VoiceCorrectionSettingsStore bool read key=\(key.rawValue)")
        guard let value = try repository.value(forKey: key.rawValue),
              let data = value.data(using: .utf8)
        else {
            return key.defaultValue
        }
        return try JSONDecoder().decode(StoredBool.self, from: data).value
    }

    static func setBool(
        _ key: VoiceCorrectionSettingsKey,
        value: Bool,
        repository: any SettingsRepository
    ) throws {
        Self.logger.debug("VoiceCorrectionSettingsStore bool set key=\(key.rawValue) value=\(value)")
        let data = try JSONEncoder().encode(StoredBool(value: value))
        guard let json = String(data: data, encoding: .utf8) else {
            Self.logger.warning("VoiceCorrectionSettingsStore setBool failed: serialize json failed key=\(key.rawValue)")
            return
        }
        try repository.set(key.rawValue, jsonValue: json)
        Self.logger.debug("VoiceCorrectionSettingsStore bool set persisted key=\(key.rawValue)")
    }
}
