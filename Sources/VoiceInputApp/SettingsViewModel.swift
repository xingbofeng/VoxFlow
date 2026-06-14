@preconcurrency import AVFoundation
import AppKit
import Combine
import Foundation
import ApplicationServices

enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case models
    case system
    case dataPrivacy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "通用"
        case .models: return "模型"
        case .system: return "系统"
        case .dataPrivacy: return "数据与隐私"
        }
    }

    var systemImage: String {
        switch self {
        case .general: return "slider.horizontal.3"
        case .models: return "cpu"
        case .system: return "macwindow"
        case .dataPrivacy: return "lock.shield"
        }
    }
}

enum SettingsKey {
    static let audioInputDeviceID = "settings.audio.inputDeviceID"
    static let audioSoundFeedbackEnabled = "settings.audio.soundFeedbackEnabled"
    static let audioVoiceEnhancementEnabled = "settings.audio.voiceEnhancementEnabled"
    static let audioMuteWhileRecordingEnabled = "settings.audio.muteWhileRecordingEnabled"
    static let performanceOptimizationEnabled = "settings.performance.optimizationEnabled"
    static let analyticsEnabled = "settings.privacy.analyticsEnabled"

    static let all = [
        audioInputDeviceID,
        audioSoundFeedbackEnabled,
        audioVoiceEnhancementEnabled,
        audioMuteWhileRecordingEnabled,
        performanceOptimizationEnabled,
        analyticsEnabled,
    ]
}

enum SettingsSystemOption: String, CaseIterable, Sendable {
    case keepMicrophoneActive = "settings.system.keepMicrophoneActive"
    case localModelLivePreview = "settings.system.localModelLivePreview"
    case autoReleaseLocalModel = "settings.system.autoReleaseLocalModel"
    case avoidClipboard = "settings.output.avoidClipboard"
    case restoreClipboard = "settings.output.restoreClipboard"
    case darkMode = "settings.appearance.darkMode"
    case launchAtLogin = "settings.appearance.launchAtLogin"
    case grayMenuBarIcon = "settings.appearance.grayMenuBarIcon"
    case capsLockIndicator = "settings.appearance.capsLockIndicator"
    case crashLogs = "settings.privacy.crashLogs"

    var defaultValue: Bool {
        self == .restoreClipboard
    }
}

struct AudioInputDevice: Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    let isDefault: Bool
}

protocol AudioInputDeviceProviding: Sendable {
    func inputDevices() -> [AudioInputDevice]
}

struct SystemAudioInputDeviceProvider: AudioInputDeviceProviding {
    static let systemDefaultDeviceID = "system-default"
    static let systemDefaultDeviceName = "系统自带"

    func inputDevices() -> [AudioInputDevice] {
        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        )
        return Self.deviceList(
            from: session.devices.map { device in
                (id: device.uniqueID, name: device.localizedName)
            }
        )
    }

    static func deviceList(from discoveredDevices: [(id: String, name: String)]) -> [AudioInputDevice] {
        let concreteDevices = discoveredDevices.compactMap { device -> AudioInputDevice? in
            guard !isCoreAudioDefaultAggregate(id: device.id, name: device.name) else {
                return nil
            }
            return AudioInputDevice(
                id: device.id,
                name: displayName(for: device.name),
                isDefault: false
            )
        }

        return [
            AudioInputDevice(
                id: systemDefaultDeviceID,
                name: systemDefaultDeviceName,
                isDefault: true
            ),
        ] + concreteDevices
    }

    private static func displayName(for name: String) -> String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            return "未知麦克风"
        }
        return trimmedName
    }

    private static func isCoreAudioDefaultAggregate(id: String, name: String) -> Bool {
        id.hasPrefix("CADefaultDeviceAggregate") || name.hasPrefix("CADefaultDeviceAggregate")
    }
}

protocol SettingsPermissionProviding: Sendable {
    func microphonePermission() -> AudioRecorder.PermissionStatus
    func speechPermission() -> AudioRecorder.PermissionStatus
    func screenRecordingPermission() -> Bool
}

struct SystemSettingsPermissionProvider: SettingsPermissionProviding {
    func microphonePermission() -> AudioRecorder.PermissionStatus {
        AudioRecorder.checkPermission()
    }

    func speechPermission() -> AudioRecorder.PermissionStatus {
        SpeechRecognizer.checkPermission()
    }

    func screenRecordingPermission() -> Bool {
        CGPreflightScreenCaptureAccess()
    }
}

enum SystemSettingsPane {
    case microphone
    case speech
    case accessibility
    case screenRecording
}

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var selectedSection: SettingsSection = .general
    @Published private(set) var inputDevices: [AudioInputDevice] = []
    @Published private(set) var selectedInputDeviceID = ""
    @Published private(set) var shortcutKeyCode: Int64 = ShortcutManager.defaultShortcutKeyCode
    @Published private(set) var longPressThreshold: TimeInterval = ShortcutManager.defaultLongPressThreshold
    @Published private(set) var shortPressBehavior: ShortPressBehavior = .toggleListening
    @Published private(set) var dictationShortcutKeyCode: Int64? = nil
    @Published private(set) var agentComposeShortcutKeyCode: Int64? = nil
    @Published private(set) var shortcutConflict: Bool = false
    @Published private(set) var soundFeedbackEnabled = true
    @Published private(set) var voiceEnhancementEnabled = true
    @Published private(set) var muteWhileRecordingEnabled = false
    @Published private(set) var performanceOptimizationEnabled = false
    @Published private(set) var analyticsEnabled = false
    @Published private(set) var systemOptions: [SettingsSystemOption: Bool] = [:]
    @Published private(set) var microphonePermission: AudioRecorder.PermissionStatus = .notDetermined
    @Published private(set) var speechPermission: AudioRecorder.PermissionStatus = .notDetermined
    @Published private(set) var accessibilityGranted = false
    @Published private(set) var screenRecordingGranted = false
    @Published private(set) var exportedDataJSON: String?
    @Published private(set) var lastError: String?
    @Published private(set) var lastActionMessage: String?

    private let environment: AppEnvironment
    private let shortcutManager: ShortcutManager
    private let audioDeviceProvider: any AudioInputDeviceProviding
    private let permissionProvider: any SettingsPermissionProviding
    private let paths: ApplicationSupportPaths?
    private let fileManager: FileManager

    init(
        environment: AppEnvironment,
        shortcutManager: ShortcutManager = .shared,
        audioDeviceProvider: any AudioInputDeviceProviding = SystemAudioInputDeviceProvider(),
        permissionProvider: any SettingsPermissionProviding = SystemSettingsPermissionProvider(),
        paths: ApplicationSupportPaths? = nil,
        fileManager: FileManager = .default
    ) {
        self.environment = environment
        self.shortcutManager = shortcutManager
        self.audioDeviceProvider = audioDeviceProvider
        self.permissionProvider = permissionProvider
        self.paths = paths ?? environment.container.paths
        self.fileManager = fileManager
        load()
    }

    func load() {
        do {
            inputDevices = audioDeviceProvider.inputDevices()
            let storedInputDeviceID = try readString(
                SettingsKey.audioInputDeviceID,
                defaultValue: inputDevices.first(where: \.isDefault)?.id ?? inputDevices.first?.id ?? ""
            )
            selectedInputDeviceID = normalizedInputDeviceID(storedInputDeviceID)
            if selectedInputDeviceID != storedInputDeviceID {
                try setString(SettingsKey.audioInputDeviceID, value: selectedInputDeviceID)
            }
            shortcutKeyCode = shortcutManager.shortcutKeyCode
            longPressThreshold = shortcutManager.longPressThreshold
            shortPressBehavior = shortcutManager.shortPressBehavior
            dictationShortcutKeyCode = shortcutManager.dictationShortcutKeyCode
            agentComposeShortcutKeyCode = shortcutManager.agentComposeShortcutKeyCode
            shortcutConflict = shortcutManager.hasConflict()
            soundFeedbackEnabled = try readBool(SettingsKey.audioSoundFeedbackEnabled, defaultValue: true)
            voiceEnhancementEnabled = try readBool(SettingsKey.audioVoiceEnhancementEnabled, defaultValue: true)
            muteWhileRecordingEnabled = try readBool(SettingsKey.audioMuteWhileRecordingEnabled, defaultValue: false)
            performanceOptimizationEnabled = try readBool(SettingsKey.performanceOptimizationEnabled, defaultValue: false)
            analyticsEnabled = try readBool(SettingsKey.analyticsEnabled, defaultValue: false)
            systemOptions = try Dictionary(
                uniqueKeysWithValues: SettingsSystemOption.allCases.map { option in
                    (
                        option,
                        try readBool(option.rawValue, defaultValue: option.defaultValue)
                    )
                }
            )
            microphonePermission = permissionProvider.microphonePermission()
            speechPermission = permissionProvider.speechPermission()
            accessibilityGranted = AXIsProcessTrusted()
            screenRecordingGranted = permissionProvider.screenRecordingPermission()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func selectInputDevice(id: String) throws {
        selectedInputDeviceID = id
        try setString(SettingsKey.audioInputDeviceID, value: id)
        lastError = nil
        lastActionMessage = "已更新输入设备"
    }

    func updateShortcut(
        keyCode: Int64,
        longPressThreshold: TimeInterval,
        shortPressBehavior: ShortPressBehavior
    ) throws {
        shortcutManager.shortcutKeyCode = keyCode
        shortcutManager.longPressThreshold = longPressThreshold
        shortcutManager.shortPressBehavior = shortPressBehavior
        self.shortcutKeyCode = keyCode
        self.longPressThreshold = longPressThreshold
        self.shortPressBehavior = shortPressBehavior
        self.dictationShortcutKeyCode = shortcutManager.dictationShortcutKeyCode
        self.shortcutConflict = shortcutManager.hasConflict()
        lastError = nil
        lastActionMessage = "已更新快捷键设置"
    }

    func updateActionShortcut(
        action: VoiceAction,
        keyCode: Int64?
    ) throws {
        shortcutManager.setShortcutKeyCode(keyCode, for: action)
        if shortcutManager.hasConflict() {
            throw SettingsViewModelError.conflictingBindings
        }
        shortcutKeyCode = shortcutManager.shortcutKeyCode
        dictationShortcutKeyCode = shortcutManager.dictationShortcutKeyCode
        agentComposeShortcutKeyCode = shortcutManager.agentComposeShortcutKeyCode
        shortcutConflict = false
        lastError = nil
        lastActionMessage = "已更新\(action.displayName)快捷键"
    }

    func applyShortcutKeyCode(_ text: String) {
        guard let keyCode = Int64(text.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            report(error: SettingsViewModelError.invalidShortcutKeyCode)
            return
        }
        do {
            try updateShortcut(
                keyCode: keyCode,
                longPressThreshold: longPressThreshold,
                shortPressBehavior: shortPressBehavior
            )
            lastError = nil
            lastActionMessage = "已应用快捷键"
        } catch {
            report(error: error)
        }
    }

    func updateAudioOptions(soundFeedback: Bool, voiceEnhancement: Bool) throws {
        soundFeedbackEnabled = soundFeedback
        voiceEnhancementEnabled = voiceEnhancement
        try setBool(SettingsKey.audioSoundFeedbackEnabled, value: soundFeedback)
        try setBool(SettingsKey.audioVoiceEnhancementEnabled, value: voiceEnhancement)
        lastError = nil
        lastActionMessage = "已更新音频设置"
    }

    func updatePerformanceOptions(
        muteWhileRecording: Bool,
        performanceOptimization: Bool
    ) throws {
        muteWhileRecordingEnabled = muteWhileRecording
        performanceOptimizationEnabled = performanceOptimization
        try setBool(SettingsKey.audioMuteWhileRecordingEnabled, value: muteWhileRecording)
        try setBool(SettingsKey.performanceOptimizationEnabled, value: performanceOptimization)
        lastError = nil
        lastActionMessage = "已更新系统设置"
    }

    func setAnalyticsEnabled(_ enabled: Bool) throws {
        analyticsEnabled = enabled
        try setBool(SettingsKey.analyticsEnabled, value: enabled)
        lastError = nil
        lastActionMessage = "已更新分析设置"
    }

    func systemOption(_ option: SettingsSystemOption) -> Bool {
        systemOptions[option] ?? option.defaultValue
    }

    func setSystemOption(_ option: SettingsSystemOption, enabled: Bool) throws {
        systemOptions[option] = enabled
        try setBool(option.rawValue, value: enabled)
        lastError = nil
        lastActionMessage = "已更新系统设置"
    }

    func systemSettingsURL(for pane: SystemSettingsPane) -> URL? {
        switch pane {
        case .microphone:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
        case .speech:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition")
        case .accessibility:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        case .screenRecording:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
        }
    }

    func openApplicationSupportFolder() {
        guard let paths else {
            report(error: ApplicationSupportPathsError.applicationSupportDirectoryUnavailable)
            return
        }
        NSWorkspace.shared.open(paths.rootDirectory)
        lastError = nil
        lastActionMessage = "已打开本地数据文件夹"
    }

    func clearHistory() throws {
        let entries = try environment.historyRepository.listRecent(limit: 100_000)
        for entry in entries {
            try environment.historyRepository.softDelete(id: entry.id, deletedAt: environment.clock.now)
        }
        lastError = nil
        lastActionMessage = "已清空历史"
    }

    func clearCache() throws {
        guard let paths else { return }
        if fileManager.fileExists(atPath: paths.modelsDirectory.path) {
            try fileManager.removeItem(at: paths.modelsDirectory)
        }
        try fileManager.createDirectory(
            at: paths.modelsDirectory,
            withIntermediateDirectories: true
        )
        lastError = nil
        lastActionMessage = "已清空缓存"
    }

    @discardableResult
    func exportDataJSON() throws -> String {
        let history = try environment.historyRepository.listRecent(limit: 100_000).map { entry in
            [
                "id": entry.id,
                "rawText": entry.rawText,
                "finalText": entry.finalText,
                "language": entry.language,
                "createdAt": ISO8601DateFormatter().string(from: entry.createdAt),
            ]
        }
        let settings = Dictionary(
            uniqueKeysWithValues: try environment.settingsRepository.list().map { ($0.key, $0.valueJSON) }
        )
        let object: [String: Any] = [
            "history": history,
            "settings": settings,
        ]
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        let string = String(data: data, encoding: .utf8) ?? "{}"
        exportedDataJSON = string
        lastError = nil
        lastActionMessage = "已生成导出数据"
        return string
    }

    func importSettingsJSON(_ json: String) throws {
        let data = Data(json.utf8)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let settings = object["settings"] as? [String: String] else {
            throw SettingsViewModelError.invalidImport
        }
        for (key, value) in settings {
            try environment.settingsRepository.set(key, jsonValue: value)
        }
        load()
        lastError = nil
        lastActionMessage = "已导入设置"
    }

    func resetSettings() throws {
        let records = try environment.settingsRepository.list()
        for record in records {
            try environment.settingsRepository.deleteValue(forKey: record.key)
        }
        shortcutManager.shortcutKeyCode = ShortcutManager.defaultShortcutKeyCode
        shortcutManager.longPressThreshold = ShortcutManager.defaultLongPressThreshold
        shortcutManager.shortPressBehavior = .toggleListening
        exportedDataJSON = nil
        load()
        lastError = nil
        lastActionMessage = "已重置设置"
    }

    func report(error: Error) {
        lastError = error.localizedDescription
        lastActionMessage = nil
    }

    func clearFeedback() {
        lastError = nil
        lastActionMessage = nil
    }

    private func readBool(_ key: String, defaultValue: Bool) throws -> Bool {
        try readSetting(key, defaultValue: defaultValue)
    }

    private func readString(_ key: String, defaultValue: String) throws -> String {
        try readSetting(key, defaultValue: defaultValue)
    }

    private func normalizedInputDeviceID(_ id: String) -> String {
        if id.hasPrefix("CADefaultDeviceAggregate") {
            return SystemAudioInputDeviceProvider.systemDefaultDeviceID
        }
        guard inputDevices.contains(where: { $0.id == id }) else {
            return inputDevices.first(where: \.isDefault)?.id ?? inputDevices.first?.id ?? ""
        }
        return id
    }

    private func readSetting<T: Decodable>(_ key: String, defaultValue: T) throws -> T {
        guard let valueJSON = try environment.settingsRepository.value(forKey: key),
              let data = valueJSON.data(using: .utf8) else {
            return defaultValue
        }
        return try JSONDecoder().decode(DecodedSettingValue<T>.self, from: data).value
    }

    private func setBool(_ key: String, value: Bool) throws {
        try setSetting(key, value: value)
    }

    private func setString(_ key: String, value: String) throws {
        try setSetting(key, value: value)
    }

    private func setSetting<T: Encodable>(_ key: String, value: T) throws {
        let data = try JSONEncoder().encode(EncodedSettingValue(value: value))
        let string = String(data: data, encoding: .utf8) ?? "{}"
        try environment.settingsRepository.set(key, jsonValue: string)
    }
}

enum SettingsViewModelError: LocalizedError {
    case invalidImport
    case invalidShortcutKeyCode
    case conflictingBindings

    var errorDescription: String? {
        switch self {
        case .invalidImport:
            return "导入数据格式不正确。"
        case .invalidShortcutKeyCode:
            return "快捷键录制失败，请按下一个有效按键。"
        case .conflictingBindings:
            return "两个操作不能使用相同的快捷键，请修改其中一个。"
        }
    }
}

struct DecodedSettingValue<T: Decodable>: Decodable {
    let value: T
}

struct EncodedSettingValue<T: Encodable>: Encodable {
    let value: T
}
