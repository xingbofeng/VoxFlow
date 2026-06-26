@preconcurrency import AVFoundation
import AppKit
import Combine
import Foundation
import ApplicationServices
import VoxFlowVoiceCorrection

enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case vibeCoding
    case selectionActions
    case system
    case dictationModels
    case correctionModels
    case ttsModels
    case translationModels
    case dataPrivacy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "通用"
        case .vibeCoding: return "AI 编程"
        case .selectionActions: return "划词动作"
        case .system: return "系统"
        case .dictationModels: return "语音识别"
        case .correctionModels: return "纠错与上下文"
        case .ttsModels: return "朗读"
        case .translationModels: return "翻译"
        case .dataPrivacy: return "数据与隐私"
        }
    }

    var systemImage: String {
        switch self {
        case .general: return "slider.horizontal.3"
        case .vibeCoding: return "terminal"
        case .selectionActions: return "text.cursor"
        case .dictationModels: return "waveform"
        case .correctionModels: return "sparkles"
        case .ttsModels: return "speaker.wave.2"
        case .translationModels: return "globe.asia.australia"
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
    static let outputTextInputMode = "settings.output.textInputMode"
    static let agentDispatchEnabled = "settings.agentDispatch.enabled"
    static let agentDispatchExactDirectEnabled = "settings.agentDispatch.exactDirectEnabled"
    static let agentDispatchMCPEnabled = "settings.agentDispatch.mcpEnabled"
    static let agentDispatchUnresolvedBehavior = "settings.agentDispatch.unresolvedBehavior"

    static let all = [
        audioInputDeviceID,
        audioSoundFeedbackEnabled,
        audioVoiceEnhancementEnabled,
        audioMuteWhileRecordingEnabled,
        performanceOptimizationEnabled,
        analyticsEnabled,
        outputTextInputMode,
        agentDispatchEnabled,
        agentDispatchExactDirectEnabled,
        agentDispatchMCPEnabled,
        agentDispatchUnresolvedBehavior,
    ]
}

enum SettingsSystemOption: String, CaseIterable, Sendable {
    case keepMicrophoneActive = "settings.system.keepMicrophoneActive"
    case localModelLivePreview = "settings.system.localModelLivePreview"
    case autoReleaseLocalModel = "settings.system.autoReleaseLocalModel"
    case avoidClipboard = "settings.output.avoidClipboard"
    case restoreClipboard = "settings.output.restoreClipboard"
    case clipboardImageOCR = "settings.output.clipboardImageOCR"
    case darkMode = "settings.appearance.darkMode"
    case launchAtLogin = "settings.appearance.launchAtLogin"
    case grayMenuBarIcon = "settings.appearance.grayMenuBarIcon"
    case capsLockIndicator = "settings.appearance.capsLockIndicator"
    case crashLogs = "settings.privacy.crashLogs"
    case llmTraceDiagnostics = "settings.privacy.llmTraceDiagnostics"

    var defaultValue: Bool {
        self == .restoreClipboard || self == .clipboardImageOCR
    }
}

struct AudioInputDevice: Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    let isDefault: Bool
}

struct SettingsStorageStatus: Equatable, Sendable {
    let title: String
    let message: String
    let isHealthy: Bool
    let badgeText: String

    init(storageHealth: StorageHealthState) {
        switch storageHealth {
        case let .persistent(databaseURL):
            title = "持久化存储正常"
            message = "历史、设置和模型状态会保存到 \(databaseURL.path)。"
            isHealthy = true
            badgeText = "正常"
        case let .readOnly(databaseURL, reason):
            title = "数据目录只读"
            message = "\(reason)。当前数据库位于 \(databaseURL.path)，码上写无法可靠写入新历史、设置或任务状态。请检查目录权限或复制数据后修复。"
            isHealthy = false
            badgeText = "只读"
        case let .migrationRequired(databaseURL, reason):
            title = "数据库需要迁移"
            message = "\(reason)。当前数据库位于 \(databaseURL.path)，迁移完成前不会把新历史、设置或任务状态当作已保存。"
            isHealthy = false
            badgeText = "需迁移"
        case let .corrupt(databaseURL, reason):
            title = "数据库可能损坏"
            message = "\(reason)。当前数据库位于 \(databaseURL.path)，请先导出或备份数据，再执行修复或重建。"
            isHealthy = false
            badgeText = "损坏"
        case let .unavailable(reason):
            title = "持久化存储不可用"
            message = "\(reason)。当前历史、设置和任务状态只保存在内存里，重启后可能丢失。"
            isHealthy = false
            badgeText = "不可用"
        case let .volatile(reason):
            title = "临时存储模式"
            message = "\(reason)。当前历史、设置和任务状态只保存在内存里，重启后可能丢失。"
            isHealthy = false
            badgeText = "临时"
        }
    }
}

struct AgentMCPLogSnapshot: Equatable {
    let text: String
    let fileExists: Bool
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

protocol ASRSettingsResetting: AnyObject {
    func resetASRSettingsToDefaults()
}

protocol LocalModelDeletionCoordinating: AnyObject {
    func deleteAllLocalModels(in modelsDirectory: URL, fileManager: FileManager) throws
    func localModelStorageBytes(in modelsDirectory: URL, fileManager: FileManager) -> Int64
}

extension ASRManager: ASRSettingsResetting, LocalModelDeletionCoordinating {}

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
    private static let logger = AppLogger.general

    @Published var selectedSection: SettingsSection = .general
    @Published private(set) var inputDevices: [AudioInputDevice] = []
    @Published private(set) var selectedInputDeviceID = ""
    @Published private(set) var shortcutKeyCode: Int64 = ShortcutManager.defaultShortcutKeyCode
    @Published private(set) var longPressThreshold: TimeInterval = ShortcutManager.defaultLongPressThreshold
    @Published private(set) var shortPressBehavior: ShortPressBehavior = .toggleListening
    @Published private(set) var dictationShortcutKeyCode: Int64? = nil
    @Published private(set) var agentComposeShortcutKeyCode: Int64? = nil
    @Published private(set) var paletteShortcutKeyCode: Int64? = nil
    @Published private(set) var clipboardImageOCRShortcutKeyCode: Int64? = nil
    @Published private(set) var screenshotOCRShortcutKeyCode: Int64? = nil
    @Published private(set) var selectionActionShortcutKeyCode: Int64? = nil
    @Published private(set) var selectionTranslateShortcutKeyCode: Int64? = nil
    @Published private(set) var selectionSummarizeShortcutKeyCode: Int64? = nil
    @Published private(set) var selectionAgentShortcutKeyCode: Int64? = nil
    @Published private(set) var selectionAskAIShortcutKeyCode: Int64? = nil
    @Published private(set) var middleMouseRecordingEnabled = false
    @Published private(set) var agentDispatchEnabled = false
    @Published private(set) var agentDispatchExactDirectEnabled = true
    @Published private(set) var agentDispatchMCPEnabled = true
    @Published private(set) var agentDispatchUnresolvedBehavior = "confirm"
    @Published private(set) var voiceCorrectionEnabled = VoiceCorrectionSettingsKey.enabled.defaultValue
    @Published private(set) var voiceCorrectionAutoLearningEnabled = VoiceCorrectionSettingsKey.autoLearningEnabled.defaultValue
    @Published private(set) var voiceCorrectionAutoLearningAppliesImmediately = VoiceCorrectionSettingsKey.autoLearningAppliesImmediately.defaultValue
    @Published private(set) var voiceCorrectionShadowMode = VoiceCorrectionSettingsKey.shadowMode.defaultValue
    @Published private(set) var agentSessions: [AgentSessionCard] = []
    @Published private(set) var agentAliases: [String: String] = [:]
    @Published private(set) var agentDispatchLogs: [AgentDispatchLogEntry] = []
    @Published private(set) var agentCLIRegistrationStatus: AgentCLIRegistrationStatus?
    @Published private(set) var shortcutConflict: Bool = false
    @Published private(set) var soundFeedbackEnabled = true
    @Published private(set) var voiceEnhancementEnabled = false
    @Published private(set) var muteWhileRecordingEnabled = false
    @Published private(set) var performanceOptimizationEnabled = false
    @Published private(set) var analyticsEnabled = false
    @Published private(set) var textInputMode: TextInputMode = .automatic
    @Published private(set) var recognitionLanguages: [RecognitionLanguage] = RecognitionLanguage.allCases
    @Published private(set) var selectedRecognitionLanguage: RecognitionLanguage = .default
    @Published private(set) var systemOptions: [SettingsSystemOption: Bool] = [:]
    @Published private(set) var microphonePermission: AudioRecorder.PermissionStatus = .notDetermined
    @Published private(set) var speechPermission: AudioRecorder.PermissionStatus = .notDetermined
    @Published private(set) var accessibilityGranted = false
    @Published private(set) var screenRecordingGranted = false
    @Published private(set) var storageStatus: SettingsStorageStatus
    @Published private(set) var exportedDataJSON: String?
    @Published private(set) var lastError: String?
    @Published private(set) var lastActionMessage: String?

    var currentAgentSessions: [AgentSessionCard] {
        agentSessions.currentDispatchableAgents
    }

    var inactiveAgentSessions: [AgentSessionCard] {
        agentSessions.filter { !$0.status.isDispatchable }
    }

    func preferredAlias(for agentID: String) -> String? {
        agentAliases
            .filter { $0.value == agentID }
            .map(\.key)
            .sorted()
            .first
    }

    private let environment: any AppServiceProviding
    private let shortcutManager: ShortcutManager
    private let audioDeviceProvider: any AudioInputDeviceProviding
    private let permissionProvider: any SettingsPermissionProviding
    private let languageManager: LanguageManager
    private let asrSettingsResetter: (any ASRSettingsResetting)?
    private let localModelDeletionCoordinator: (any LocalModelDeletionCoordinating)?
    private let launchAtLoginManager: any LaunchAtLoginManaging
    private let paths: ApplicationSupportPaths?
    private let fileManager: FileManager
    private let clipboardWriter: ClipboardWriting
    private var languageObserverID: UUID?
    private var hasLoaded = false

    init(
        environment: any AppServiceProviding,
        shortcutManager: ShortcutManager = .shared,
        audioDeviceProvider: any AudioInputDeviceProviding = SystemAudioInputDeviceProvider(),
        permissionProvider: any SettingsPermissionProviding = SystemSettingsPermissionProvider(),
        languageManager: LanguageManager = .shared,
        asrSettingsResetter: (any ASRSettingsResetting)? = nil,
        localModelDeletionCoordinator: (any LocalModelDeletionCoordinating)? = nil,
        launchAtLoginManager: any LaunchAtLoginManaging = SystemLaunchAtLoginManager(),
        paths: ApplicationSupportPaths? = nil,
        fileManager: FileManager = .default,
        clipboardWriter: ClipboardWriting = GeneralPasteboardWriter()
    ) {
        self.environment = environment
        self.shortcutManager = shortcutManager
        self.audioDeviceProvider = audioDeviceProvider
        self.permissionProvider = permissionProvider
        self.languageManager = languageManager
        self.asrSettingsResetter = asrSettingsResetter
        self.localModelDeletionCoordinator = localModelDeletionCoordinator
        self.launchAtLoginManager = launchAtLoginManager
        self.paths = paths ?? environment.paths
        self.fileManager = fileManager
        self.clipboardWriter = clipboardWriter
        self.storageStatus = SettingsStorageStatus(storageHealth: environment.storageHealth)
        load()
        languageObserverID = languageManager.observeLanguageChanges { [weak self] language in
            self?.selectedRecognitionLanguage = language
        }
    }

    func load() {
        Self.logger.debug("settings_vm_load_start hasLoaded=\(hasLoaded)")
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
            dictationShortcutKeyCode = shortcutManager.shortcutKeyCode(for: .dictation)
            agentComposeShortcutKeyCode = shortcutManager.shortcutKeyCode(for: .agentCompose)
            paletteShortcutKeyCode = shortcutManager.shortcutKeyCode(for: .palette)
            clipboardImageOCRShortcutKeyCode = shortcutManager.shortcutKeyCode(for: .clipboardImageOCR)
            screenshotOCRShortcutKeyCode = shortcutManager.shortcutKeyCode(for: .screenshotOCR)
            selectionActionShortcutKeyCode = shortcutManager.shortcutKeyCode(for: .selectionAction)
            selectionTranslateShortcutKeyCode = shortcutManager.shortcutKeyCode(for: .selectionTranslate)
            selectionSummarizeShortcutKeyCode = shortcutManager.shortcutKeyCode(for: .selectionSummarize)
            selectionAgentShortcutKeyCode = shortcutManager.shortcutKeyCode(for: .selectionAgent)
            selectionAskAIShortcutKeyCode = shortcutManager.shortcutKeyCode(for: .selectionAskAI)
            middleMouseRecordingEnabled = shortcutManager.middleMouseRecordingEnabled
            agentDispatchEnabled = try readBool(
                SettingsKey.agentDispatchEnabled,
                defaultValue: false
            )
            agentDispatchExactDirectEnabled = try readBool(
                SettingsKey.agentDispatchExactDirectEnabled,
                defaultValue: true
            )
            agentDispatchMCPEnabled = try readBool(
                SettingsKey.agentDispatchMCPEnabled,
                defaultValue: true
            )
            agentDispatchUnresolvedBehavior = try readString(
                SettingsKey.agentDispatchUnresolvedBehavior,
                defaultValue: "confirm"
            )
            voiceCorrectionEnabled = try VoiceCorrectionSettingsStore.bool(
                .enabled,
                repository: environment.settingsRepository
            )
            voiceCorrectionAutoLearningEnabled = try VoiceCorrectionSettingsStore.bool(
                .autoLearningEnabled,
                repository: environment.settingsRepository
            )
            voiceCorrectionAutoLearningAppliesImmediately = try VoiceCorrectionSettingsStore.bool(
                .autoLearningAppliesImmediately,
                repository: environment.settingsRepository
            )
            voiceCorrectionShadowMode = try VoiceCorrectionSettingsStore.bool(
                .shadowMode,
                repository: environment.settingsRepository
            )
            shortcutConflict = shortcutManager.hasConflict()
            soundFeedbackEnabled = try readBool(SettingsKey.audioSoundFeedbackEnabled, defaultValue: true)
            voiceEnhancementEnabled = try readBool(SettingsKey.audioVoiceEnhancementEnabled, defaultValue: false)
            muteWhileRecordingEnabled = try readBool(SettingsKey.audioMuteWhileRecordingEnabled, defaultValue: false)
            performanceOptimizationEnabled = try readBool(SettingsKey.performanceOptimizationEnabled, defaultValue: false)
            analyticsEnabled = try readBool(SettingsKey.analyticsEnabled, defaultValue: false)
            recognitionLanguages = languageManager.allLanguages
            selectedRecognitionLanguage = languageManager.currentLanguage
            systemOptions = try Dictionary(
                uniqueKeysWithValues: SettingsSystemOption.allCases.map { option in
                    (
                        option,
                        try readBool(option.rawValue, defaultValue: option.defaultValue)
                    )
                }
            )
            try syncLaunchAtLoginOptionWithSystem()
            textInputMode = try readTextInputMode()
            microphonePermission = permissionProvider.microphonePermission()
            speechPermission = permissionProvider.speechPermission()
            accessibilityGranted = AXIsProcessTrusted()
            screenRecordingGranted = permissionProvider.screenRecordingPermission()
            storageStatus = SettingsStorageStatus(storageHealth: environment.storageHealth)
            applyRuntimeSettingsSnapshot()
            hasLoaded = true
            lastError = nil
            Self.logger.info(
                "settings_vm_load_success inputDevices=\(inputDevices.count) agentDispatch=\(agentDispatchEnabled) voiceCorrection=\(voiceCorrectionEnabled) systemOptions=\(systemOptions.count) shortcutConflict=\(shortcutConflict) storageHealthy=\(storageStatus.isHealthy)"
            )
        } catch {
            lastError = error.localizedDescription
            Self.logger.error("settings_vm_load_failed error=\(error.localizedDescription)")
        }
    }

    func loadIfNeeded() {
        guard !hasLoaded else {
            Self.logger.debug("settings_vm_load_if_needed_skip")
            return
        }
        Self.logger.debug("settings_vm_load_if_needed_execute")
        load()
    }

    func selectInputDevice(id: String) throws {
        selectedInputDeviceID = id
        try setString(SettingsKey.audioInputDeviceID, value: id)
        lastError = nil
        lastActionMessage = persistentWriteMessage("已更新输入设备")
    }

    func updateShortcut(
        keyCode: Int64,
        longPressThreshold: TimeInterval,
        shortPressBehavior: ShortPressBehavior
    ) throws {
        Self.logger.debug("settings_vm_update_shortcut_start keyCode=\(keyCode) threshold=\(longPressThreshold) behavior=\(shortPressBehavior.rawValue)")
        guard ShortcutManager.isSupportedVoiceShortcutKeyCode(keyCode) else {
            Self.logger.warning("settings_vm_update_shortcut_rejected unsupportedKeyCode=\(keyCode)")
            throw SettingsViewModelError.unsupportedShortcutKeyCode
        }
        shortcutManager.shortcutKeyCode = keyCode
        shortcutManager.longPressThreshold = longPressThreshold
        shortcutManager.shortPressBehavior = shortPressBehavior
        self.shortcutKeyCode = keyCode
        self.longPressThreshold = longPressThreshold
        self.shortPressBehavior = shortPressBehavior
        self.dictationShortcutKeyCode = shortcutManager.shortcutKeyCode(for: .dictation)
        self.agentComposeShortcutKeyCode = shortcutManager.shortcutKeyCode(for: .agentCompose)
        self.paletteShortcutKeyCode = shortcutManager.shortcutKeyCode(for: .palette)
        self.clipboardImageOCRShortcutKeyCode = shortcutManager.shortcutKeyCode(for: .clipboardImageOCR)
        self.screenshotOCRShortcutKeyCode = shortcutManager.shortcutKeyCode(for: .screenshotOCR)
        self.selectionActionShortcutKeyCode = shortcutManager.shortcutKeyCode(for: .selectionAction)
        self.selectionTranslateShortcutKeyCode = shortcutManager.shortcutKeyCode(for: .selectionTranslate)
        self.selectionSummarizeShortcutKeyCode = shortcutManager.shortcutKeyCode(for: .selectionSummarize)
        self.selectionAgentShortcutKeyCode = shortcutManager.shortcutKeyCode(for: .selectionAgent)
        self.selectionAskAIShortcutKeyCode = shortcutManager.shortcutKeyCode(for: .selectionAskAI)
        self.shortcutConflict = shortcutManager.hasConflict()
        lastError = nil
        lastActionMessage = "已更新快捷键设置"
        Self.logger.info("settings_vm_update_shortcut_success keyCode=\(keyCode) conflict=\(shortcutConflict)")
    }

    func updateActionShortcut(
        action: VoiceAction,
        keyCode: Int64?
    ) throws {
        Self.logger.debug("settings_vm_update_action_shortcut_start action=\(action.rawValue) keyCode=\(keyCode.map(String.init) ?? "nil")")
        if let keyCode, !ShortcutManager.isSupportedVoiceShortcutKeyCode(keyCode) {
            Self.logger.warning("settings_vm_update_action_shortcut_rejected action=\(action.rawValue) reason=unsupported keyCode=\(keyCode)")
            throw SettingsViewModelError.unsupportedShortcutKeyCode
        }
        if wouldConflict(action: action, keyCode: keyCode) {
            Self.logger.warning("settings_vm_update_action_shortcut_rejected action=\(action.rawValue) reason=conflict keyCode=\(keyCode.map(String.init) ?? "nil")")
            throw SettingsViewModelError.conflictingBindings
        }
        shortcutManager.setShortcutKeyCode(keyCode, for: action)
        shortcutKeyCode = shortcutManager.shortcutKeyCode
        dictationShortcutKeyCode = shortcutManager.shortcutKeyCode(for: .dictation)
        agentComposeShortcutKeyCode = shortcutManager.shortcutKeyCode(for: .agentCompose)
        paletteShortcutKeyCode = shortcutManager.shortcutKeyCode(for: .palette)
        clipboardImageOCRShortcutKeyCode = shortcutManager.shortcutKeyCode(for: .clipboardImageOCR)
        screenshotOCRShortcutKeyCode = shortcutManager.shortcutKeyCode(for: .screenshotOCR)
        selectionActionShortcutKeyCode = shortcutManager.shortcutKeyCode(for: .selectionAction)
        selectionTranslateShortcutKeyCode = shortcutManager.shortcutKeyCode(for: .selectionTranslate)
        selectionSummarizeShortcutKeyCode = shortcutManager.shortcutKeyCode(for: .selectionSummarize)
        selectionAgentShortcutKeyCode = shortcutManager.shortcutKeyCode(for: .selectionAgent)
        selectionAskAIShortcutKeyCode = shortcutManager.shortcutKeyCode(for: .selectionAskAI)
        shortcutConflict = false
        lastError = nil
        lastActionMessage = "已更新\(action.displayName)快捷键"
        Self.logger.info("settings_vm_update_action_shortcut_success action=\(action.rawValue) keyCode=\(keyCode.map(String.init) ?? "nil")")
    }

    func updateWorkflowShortcut(
        _ shortcut: HotKeyWorkflowShortcut,
        keyCode: Int64?
    ) throws {
        Self.logger.debug("settings_vm_update_workflow_shortcut_start shortcut=\(shortcut.displayName) keyCode=\(keyCode.map(String.init) ?? "nil")")
        if let keyCode, !ShortcutManager.isSupportedWorkflowShortcutKeyCode(keyCode) {
            Self.logger.warning("settings_vm_update_workflow_shortcut_rejected shortcut=\(shortcut.displayName) reason=unsupported keyCode=\(keyCode)")
            throw SettingsViewModelError.unsupportedWorkflowShortcutKeyCode
        }
        if wouldConflict(workflowShortcut: shortcut, keyCode: keyCode) {
            Self.logger.warning("settings_vm_update_workflow_shortcut_rejected shortcut=\(shortcut.displayName) reason=conflict keyCode=\(keyCode.map(String.init) ?? "nil")")
            throw SettingsViewModelError.conflictingBindings
        }
        shortcutManager.setShortcutKeyCode(keyCode, for: shortcut)
        paletteShortcutKeyCode = shortcutManager.shortcutKeyCode(for: .palette)
        clipboardImageOCRShortcutKeyCode = shortcutManager.shortcutKeyCode(for: .clipboardImageOCR)
        screenshotOCRShortcutKeyCode = shortcutManager.shortcutKeyCode(for: .screenshotOCR)
        selectionActionShortcutKeyCode = shortcutManager.shortcutKeyCode(for: .selectionAction)
        selectionTranslateShortcutKeyCode = shortcutManager.shortcutKeyCode(for: .selectionTranslate)
        selectionSummarizeShortcutKeyCode = shortcutManager.shortcutKeyCode(for: .selectionSummarize)
        selectionAgentShortcutKeyCode = shortcutManager.shortcutKeyCode(for: .selectionAgent)
        selectionAskAIShortcutKeyCode = shortcutManager.shortcutKeyCode(for: .selectionAskAI)
        shortcutConflict = shortcutManager.hasConflict()
        lastError = nil
        lastActionMessage = "已更新\(shortcut.displayName) 快捷键"
        Self.logger.info("settings_vm_update_workflow_shortcut_success shortcut=\(shortcut.displayName) keyCode=\(keyCode.map(String.init) ?? "nil") conflict=\(shortcutConflict)")
    }

    func setAgentDispatchEnabled(_ enabled: Bool) throws {
        Self.logger.debug("settings_vm_set_agent_dispatch_enabled enabled=\(enabled)")
        agentDispatchEnabled = enabled
        try setBool(SettingsKey.agentDispatchEnabled, value: enabled)
        lastActionMessage = enabled
            ? "已启用AI 编程"
            : "已关闭AI 编程"
    }

    func setAgentDispatchExactDirectEnabled(_ enabled: Bool) throws {
        Self.logger.debug("settings_vm_set_agent_dispatch_exact_direct enabled=\(enabled)")
        agentDispatchExactDirectEnabled = enabled
        try setBool(SettingsKey.agentDispatchExactDirectEnabled, value: enabled)
        lastActionMessage = "已更新准确命名发送策略"
    }

    func setAgentDispatchUnresolvedBehavior(_ behavior: String) throws {
        guard ["confirm", "cancel", "model", "default"].contains(behavior) else {
            Self.logger.warning("settings_vm_set_agent_dispatch_unresolved_rejected behavior=\(behavior)")
            return
        }
        Self.logger.debug("settings_vm_set_agent_dispatch_unresolved behavior=\(behavior)")
        agentDispatchUnresolvedBehavior = behavior
        try setString(SettingsKey.agentDispatchUnresolvedBehavior, value: behavior)
        lastActionMessage = "已更新未命中处理方式"
    }

    func setAgentDispatchMCPEnabled(_ enabled: Bool) throws {
        Self.logger.debug("settings_vm_set_agent_dispatch_mcp enabled=\(enabled) hasPaths=\(paths != nil)")
        agentDispatchMCPEnabled = enabled
        try setBool(SettingsKey.agentDispatchMCPEnabled, value: enabled)
        if let paths {
            try paths.ensureDirectories(fileManager: fileManager)
            let data = try JSONSerialization.data(
                withJSONObject: ["mcp_enabled": enabled],
                options: [.prettyPrinted, .sortedKeys]
            )
            try data.write(
                to: paths.agentRouterDirectory.appendingPathComponent("settings.json"),
                options: .atomic
            )
        }
        lastActionMessage = "已更新协作通道身份上报设置"
    }

    func setVoiceCorrectionEnabled(_ enabled: Bool) throws {
        Self.logger.debug("settings_vm_set_voice_correction_enabled enabled=\(enabled)")
        voiceCorrectionEnabled = enabled
        try VoiceCorrectionSettingsStore.setBool(.enabled, value: enabled, repository: environment.settingsRepository)
        lastError = nil
        lastActionMessage = enabled ? "已启用易错词修正" : "已关闭易错词修正"
    }

    func setVoiceCorrectionAutoLearningEnabled(_ enabled: Bool) throws {
        Self.logger.debug("settings_vm_set_voice_correction_auto_learning enabled=\(enabled)")
        voiceCorrectionAutoLearningEnabled = enabled
        try VoiceCorrectionSettingsStore.setBool(.autoLearningEnabled, value: enabled, repository: environment.settingsRepository)
        lastError = nil
        lastActionMessage = enabled ? "已启用自动学习" : "已关闭自动学习"
    }

    func setVoiceCorrectionAutoLearningAppliesImmediately(_ enabled: Bool) throws {
        Self.logger.debug("settings_vm_set_voice_correction_auto_learning_immediate enabled=\(enabled)")
        voiceCorrectionAutoLearningAppliesImmediately = enabled
        try VoiceCorrectionSettingsStore.setBool(
            .autoLearningAppliesImmediately,
            value: enabled,
            repository: environment.settingsRepository
        )
        lastError = nil
        lastActionMessage = enabled ? "自动学习会直接生效" : "自动学习会先进入候选"
    }

    func setVoiceCorrectionShadowMode(_ enabled: Bool) throws {
        Self.logger.debug("settings_vm_set_voice_correction_shadow enabled=\(enabled)")
        voiceCorrectionShadowMode = enabled
        try VoiceCorrectionSettingsStore.setBool(.shadowMode, value: enabled, repository: environment.settingsRepository)
        lastError = nil
        lastActionMessage = enabled ? "已开启影子模式" : "已关闭影子模式"
    }

    func refreshAgentSessions(reportFailures: Bool = true) async {
        guard let paths else {
            Self.logger.warning("settings_vm_refresh_agent_sessions_skipped missingPaths=true")
            return
        }
        Self.logger.debug("settings_vm_refresh_agent_sessions_start reportFailures=\(reportFailures)")
        do {
            let client = AgentRouterClient(socketURL: paths.agentRouterSocketURL)
            agentSessions = try await client.listAllAgents()
            agentAliases = try await client.listAliases()
            agentDispatchLogs = try await client.listDispatchLog()
            lastError = nil
            Self.logger.info("settings_vm_refresh_agent_sessions_success sessions=\(agentSessions.count) aliases=\(agentAliases.count) logs=\(agentDispatchLogs.count)")
        } catch {
            agentSessions = []
            if reportFailures {
                lastError = error.localizedDescription
            }
            Self.logger.error("settings_vm_refresh_agent_sessions_failed reportFailures=\(reportFailures) error=\(error.localizedDescription)")
        }
    }

    func addAgentAlias(_ alias: String, agentID: String) async {
        guard let paths else {
            Self.logger.warning("settings_vm_add_agent_alias_skipped missingPaths=true agentID=\(agentID)")
            return
        }
        let trimmed = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            Self.logger.warning("settings_vm_add_agent_alias_skipped emptyAlias=true agentID=\(agentID)")
            return
        }
        Self.logger.debug("settings_vm_add_agent_alias_start aliasLen=\(trimmed.count) agentID=\(agentID)")
        do {
            let client = AgentRouterClient(socketURL: paths.agentRouterSocketURL)
            try await client.learnAlias(trimmed, agentID: agentID, userConfirmed: true)
            agentAliases = try await client.listAliases()
            lastError = nil
            lastActionMessage = "已保存任务助手别名"
            Self.logger.info("settings_vm_add_agent_alias_success aliases=\(agentAliases.count) agentID=\(agentID)")
        } catch {
            report(error: error)
        }
    }

    func removeAgentAlias(_ alias: String) async {
        guard let paths else {
            Self.logger.warning("settings_vm_remove_agent_alias_skipped missingPaths=true aliasLen=\(alias.count)")
            return
        }
        Self.logger.debug("settings_vm_remove_agent_alias_start aliasLen=\(alias.count)")
        do {
            let client = AgentRouterClient(socketURL: paths.agentRouterSocketURL)
            try await client.removeAlias(alias)
            agentAliases = try await client.listAliases()
            lastError = nil
            lastActionMessage = "已删除任务助手别名"
            Self.logger.info("settings_vm_remove_agent_alias_success aliases=\(agentAliases.count)")
        } catch {
            report(error: error)
        }
    }

    func setAgentAlias(_ alias: String, for agentID: String) async {
        guard let paths else {
            Self.logger.warning("settings_vm_set_agent_alias_skipped missingPaths=true agentID=\(agentID)")
            return
        }
        let trimmed = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        Self.logger.debug("settings_vm_set_agent_alias_start aliasLen=\(trimmed.count) agentID=\(agentID)")
        do {
            let client = AgentRouterClient(socketURL: paths.agentRouterSocketURL)
            if let existingAlias = preferredAlias(for: agentID), existingAlias != trimmed {
                try await client.removeAlias(existingAlias)
            }
            if !trimmed.isEmpty {
                try await client.learnAlias(trimmed, agentID: agentID, userConfirmed: true)
            }
            agentAliases = try await client.listAliases()
            lastError = nil
            lastActionMessage = trimmed.isEmpty ? "已清空任务助手别名" : "已更新任务助手别名"
            Self.logger.info("settings_vm_set_agent_alias_success aliases=\(agentAliases.count) agentID=\(agentID) cleared=\(trimmed.isEmpty)")
        } catch {
            report(error: error)
        }
    }

    func cleanStaleAgentSessions() async {
        guard let paths else {
            Self.logger.warning("settings_vm_clean_stale_agent_sessions_skipped missingPaths=true")
            return
        }
        Self.logger.debug("settings_vm_clean_stale_agent_sessions_start")
        do {
            let client = AgentRouterClient(socketURL: paths.agentRouterSocketURL)
            try await client.cleanInactiveSessions()
            await refreshAgentSessions()
            lastActionMessage = "已清理已退出/失效任务助手"
            Self.logger.info("settings_vm_clean_stale_agent_sessions_success sessions=\(agentSessions.count)")
        } catch {
            report(error: error)
        }
    }

    func terminateAgentSession(_ agent: AgentSessionCard) async {
        guard let paths else {
            Self.logger.warning("settings_vm_terminate_agent_session_skipped missingPaths=true agentID=\(agent.agentID)")
            return
        }
        Self.logger.debug("settings_vm_terminate_agent_session_start agentID=\(agent.agentID)")
        do {
            let client = AgentRouterClient(socketURL: paths.agentRouterSocketURL)
            try await client.terminateAgent(agentID: agent.agentID)
            await refreshAgentSessions()
            lastActionMessage = "已停止任务助手进程"
            Self.logger.info("settings_vm_terminate_agent_session_success agentID=\(agent.agentID) sessions=\(agentSessions.count)")
        } catch {
            report(error: error)
        }
    }

    func clearAgentDispatchLogs() async {
        guard let paths else { return }
        do {
            let client = AgentRouterClient(socketURL: paths.agentRouterSocketURL)
            try await client.clearDispatchLog()
            agentDispatchLogs = []
            lastError = nil
            lastActionMessage = "已清空调度记录"
        } catch {
            report(error: error)
        }
    }

    func copyAgentLaunchCommand(_ agent: AgentSessionCard) {
        Self.logger.info("settings_vm_copy_agent_launch_command agentID=\(agent.agentID) argCount=\(agent.command.count)")
        clipboardWriter.copy("voxflow run -- \(agent.command.joined(separator: " "))")
        lastActionMessage = "已复制任务助手启动命令"
    }

    func mcpLogSnapshot(for agent: AgentSessionCard) -> AgentMCPLogSnapshot {
        guard let path = agent.mcpLogPath, !path.isEmpty else {
            return AgentMCPLogSnapshot(
                text: "暂无协作通道日志文件路径。请重启对应任务助手后再试。",
                fileExists: false
            )
        }
        let url = URL(fileURLWithPath: path)
        guard fileManager.fileExists(atPath: url.path) else {
            return AgentMCPLogSnapshot(
            text: "日志文件暂未生成。任务助手首次连接协作通道后会写入这里。",
                fileExists: false
            )
        }
        do {
            let data = try Data(contentsOf: url)
            let text = String(data: data, encoding: .utf8) ?? "<日志不是 UTF-8 文本>"
            return AgentMCPLogSnapshot(
                text: text.isEmpty ? "日志文件已创建，但暂时没有内容。" : text,
                fileExists: true
            )
        } catch {
            return AgentMCPLogSnapshot(
                text: "读取日志失败：\(error.localizedDescription)",
                fileExists: false
            )
        }
    }

    func copyMCPDiagnostics(for agent: AgentSessionCard, logText: String) {
        Self.logger.info("settings_vm_copy_mcp_diagnostics agentID=\(agent.agentID) logLen=\(logText.count)")
        clipboardWriter.copy(mcpDiagnosticsText(for: agent, logText: logText))
        lastError = nil
        lastActionMessage = "已复制协作通道诊断信息"
    }

    func openMCPLogFile(for agent: AgentSessionCard) {
        Self.logger.debug("settings_vm_open_mcp_log_file_start agentID=\(agent.agentID) hasPath=\(!(agent.mcpLogPath ?? "").isEmpty)")
        guard let path = agent.mcpLogPath, !path.isEmpty else {
            lastError = "暂无协作通道日志文件路径。请重启对应任务助手后再试。"
            lastActionMessage = nil
            return
        }
        let url = URL(fileURLWithPath: path)
        do {
            try fileManager.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if !fileManager.fileExists(atPath: url.path) {
                _ = fileManager.createFile(atPath: url.path, contents: Data())
            }
            guard NSWorkspace.shared.open(url) else {
                lastError = "无法打开协作通道日志文件"
                lastActionMessage = nil
                Self.logger.warning("settings_vm_open_mcp_log_file_failed agentID=\(agent.agentID) reason=workspaceOpen")
                return
            }
            lastError = nil
            lastActionMessage = "已打开协作通道日志文件"
            Self.logger.info("settings_vm_open_mcp_log_file_success agentID=\(agent.agentID)")
        } catch {
            report(error: error)
        }
    }

    func registerAgentCLI() {
        Self.logger.debug("settings_vm_register_agent_cli_start hasPaths=\(paths != nil)")
        guard let paths else {
            report(error: ApplicationSupportPathsError.applicationSupportDirectoryUnavailable)
            return
        }
        do {
            agentCLIRegistrationStatus = try AgentHelperManager(paths: paths).registerCLI()
            lastError = nil
            lastActionMessage = agentCLIRegistrationStatus?.isOnCurrentPath == true
                ? "终端命令已注册"
                : "终端命令已注册；请新开终端后使用"
            Self.logger.info("settings_vm_register_agent_cli_success onPath=\(agentCLIRegistrationStatus?.isOnCurrentPath == true)")
        } catch {
            report(error: error)
        }
    }

    func unregisterAgentCLI() {
        Self.logger.debug("settings_vm_unregister_agent_cli_start hasPaths=\(paths != nil)")
        guard let paths else {
            report(error: ApplicationSupportPathsError.applicationSupportDirectoryUnavailable)
            return
        }
        do {
            try AgentHelperManager(paths: paths).unregisterCLI()
            agentCLIRegistrationStatus = nil
            lastError = nil
            lastActionMessage = "终端命令已卸载"
            Self.logger.info("settings_vm_unregister_agent_cli_success")
        } catch {
            report(error: error)
        }
    }

    func agentCLIRegistrationPreview() -> AgentCLIRegistrationPreview {
        AgentHelperManager.registrationPreview()
    }

    func copyAgentCLIExamples() {
        clipboardWriter.copy("vox flow codex\nvox flow --claude\nvox flow --codebuddy")
        lastActionMessage = "已复制启动命令"
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
        lastActionMessage = persistentWriteMessage("已更新音频设置")
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
        lastActionMessage = persistentWriteMessage("已更新系统设置")
    }

    func setAnalyticsEnabled(_ enabled: Bool) throws {
        analyticsEnabled = enabled
        try setBool(SettingsKey.analyticsEnabled, value: enabled)
        lastError = nil
        lastActionMessage = persistentWriteMessage("已更新分析设置")
    }

    func setMiddleMouseRecordingEnabled(_ enabled: Bool) throws {
        middleMouseRecordingEnabled = enabled
        shortcutManager.middleMouseRecordingEnabled = enabled
        lastError = nil
        lastActionMessage = enabled ? "已启用鼠标中键录音" : "已关闭鼠标中键录音"
    }

    func systemOption(_ option: SettingsSystemOption) -> Bool {
        systemOptions[option] ?? option.defaultValue
    }

    func setSystemOption(_ option: SettingsSystemOption, enabled: Bool) throws {
        Self.logger.debug("settings_vm_set_system_option option=\(option.rawValue) enabled=\(enabled)")
        if option == .launchAtLogin {
            try setLaunchAtLoginOption(enabled)
            return
        }
        systemOptions[option] = enabled
        try setBool(option.rawValue, value: enabled)
        if option == .avoidClipboard {
            try setTextInputMode(enabled ? .simulatedTyping : .automatic)
        }
        applyRuntimeSettingsSnapshot()
        lastError = nil
        lastActionMessage = persistentWriteMessage("已更新系统设置")
    }

    private func setLaunchAtLoginOption(_ enabled: Bool) throws {
        Self.logger.debug("settings_vm_set_launch_at_login_start enabled=\(enabled)")
        do {
            try launchAtLoginManager.setEnabled(enabled)
            try syncLaunchAtLoginOptionWithSystem()
            applyRuntimeSettingsSnapshot()
            lastError = nil
            lastActionMessage = persistentWriteMessage("已更新系统设置")
            Self.logger.info("settings_vm_set_launch_at_login_success enabled=\(systemOption(.launchAtLogin))")
        } catch {
            let actualValue = launchAtLoginManager.isEnabled
            systemOptions[.launchAtLogin] = actualValue
            try? setBool(SettingsSystemOption.launchAtLogin.rawValue, value: actualValue)
            applyRuntimeSettingsSnapshot()
            lastError = "开机自动启动设置失败：\(error.localizedDescription)"
            lastActionMessage = nil
            Self.logger.error("settings_vm_set_launch_at_login_failed requested=\(enabled) actual=\(actualValue) error=\(error.localizedDescription)")
            throw error
        }
    }

    func clearLLMTraceDiagnostics() {
        LLMDiagnosticCapture.shared.clear()
        lastError = nil
        lastActionMessage = "已删除模型诊断内容"
    }

    func setTextInputMode(_ mode: TextInputMode) throws {
        Self.logger.debug("settings_vm_set_text_input_mode mode=\(mode.rawValue)")
        textInputMode = mode
        try setString(SettingsKey.outputTextInputMode, value: mode.rawValue)
        systemOptions[.avoidClipboard] = mode == .simulatedTyping
        try setBool(SettingsSystemOption.avoidClipboard.rawValue, value: mode == .simulatedTyping)
        lastError = nil
        lastActionMessage = persistentWriteMessage("已更新文本输入模式")
    }

    func setRecognitionLanguage(_ language: RecognitionLanguage) throws {
        Self.logger.debug("settings_vm_set_recognition_language language=\(language.rawValue)")
        languageManager.setLanguage(language)
        selectedRecognitionLanguage = languageManager.currentLanguage
        lastError = nil
        lastActionMessage = "已更新识别语言"
    }

    func systemSettingsURL(for pane: SystemSettingsPane) -> URL? {
        PermissionGuideContent.systemSettingsURL(for: pane)
    }

    func openApplicationSupportFolder() {
        let resolvedPaths = paths ?? (try? ApplicationSupportPaths.live())
        guard let resolvedPaths else {
            report(error: ApplicationSupportPathsError.applicationSupportDirectoryUnavailable)
            return
        }
        try? fileManager.createDirectory(
            at: resolvedPaths.rootDirectory,
            withIntermediateDirectories: true
        )
        NSWorkspace.shared.open(resolvedPaths.rootDirectory)
        lastError = nil
        lastActionMessage = "已打开本地数据文件夹"
    }

    func clearHistory() throws {
        Self.logger.debug("settings_vm_clear_history_start")
        let entries = try environment.historyRepository.listRecent(limit: 100_000)
        for entry in entries {
            try environment.historyRepository.softDelete(id: entry.id, deletedAt: environment.clock.now)
        }
        lastError = nil
        lastActionMessage = persistentWriteMessage("已清空历史")
        Self.logger.info("settings_vm_clear_history_success count=\(entries.count)")
    }

    func clearCache() throws {
        Self.logger.debug("settings_vm_clear_cache_start")
        try deleteAllLocalModels()
    }

    func deleteAllLocalModels() throws {
        Self.logger.debug("settings_vm_delete_all_local_models_start hasPaths=\(paths != nil) usesCoordinator=\(localModelDeletionCoordinator != nil)")
        guard let paths else {
            lastError = "没有可用的数据目录，本地模型未删除。"
            lastActionMessage = nil
            Self.logger.warning("settings_vm_delete_all_local_models_skipped missingPaths=true")
            return
        }
        if let localModelDeletionCoordinator {
            try localModelDeletionCoordinator.deleteAllLocalModels(
                in: paths.modelsDirectory,
                fileManager: fileManager
            )
        } else {
            try deleteModelDirectoryContents(paths.modelsDirectory)
        }
        lastError = nil
        lastActionMessage = "已删除全部本地模型"
        Self.logger.info("settings_vm_delete_all_local_models_success")
    }

    func localModelStorageDescription() -> String {
        guard let paths else { return "大小未知" }
        let bytes = localModelDeletionCoordinator?.localModelStorageBytes(
            in: paths.modelsDirectory,
            fileManager: fileManager
        ) ?? directoryAllocatedBytes(paths.modelsDirectory)
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    @discardableResult
    func exportDataJSON() throws -> String {
        Self.logger.debug("settings_vm_export_data_json_start")
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
            "voiceCorrection": try voiceCorrectionExportObject(),
        ]
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        let string = String(data: data, encoding: .utf8) ?? "{}"
        exportedDataJSON = string
        lastError = nil
        lastActionMessage = "已生成导出数据"
        Self.logger.info("settings_vm_export_data_json_success history=\(history.count) settings=\(settings.count) bytes=\(data.count)")
        return string
    }

    func importSettingsJSON(_ json: String) throws {
        Self.logger.debug("settings_vm_import_settings_json_start bytes=\(Data(json.utf8).count)")
        let data = Data(json.utf8)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let settings = object["settings"] as? [String: String] else {
            throw SettingsViewModelError.invalidImport
        }
        for (key, value) in settings {
            try environment.settingsRepository.set(key, jsonValue: value)
        }
        if let voiceCorrection = object["voiceCorrection"] as? [String: Any] {
            try importVoiceCorrection(voiceCorrection)
        }
        load()
        lastError = nil
        lastActionMessage = persistentWriteMessage("已导入设置")
        Self.logger.info("settings_vm_import_settings_json_success settings=\(settings.count)")
    }

    private func voiceCorrectionExportObject() throws -> [String: Any] {
        [
            "targets": try environment.correctionTargetRepository.list().map(exportTarget),
            "rules": try environment.correctionRuleRepository.list().map(exportRule),
        ]
    }

    private func exportTarget(_ target: CorrectionTargetTerm) -> [String: Any] {
        var object: [String: Any] = [
            "id": target.id.uuidString,
            "text": target.text,
            "normalizedText": target.normalizedText,
            "lifecycle": target.lifecycle.rawValue,
            "source": target.source.rawValue,
            "observedCount": target.observedCount,
            "appliedCount": target.appliedCount,
            "revertedCount": target.revertedCount,
            "createdAt": Self.iso8601.string(from: target.createdAt),
            "updatedAt": Self.iso8601.string(from: target.updatedAt),
        ]
        addScope(target.scope, to: &object)
        if let lastAppliedAt = target.lastAppliedAt {
            object["lastAppliedAt"] = Self.iso8601.string(from: lastAppliedAt)
        }
        return object
    }

    private func exportRule(_ rule: CorrectionRule) -> [String: Any] {
        var object: [String: Any] = [
            "id": rule.id.uuidString,
            "original": rule.original,
            "replacement": rule.replacement,
            "matchPolicy": rule.matchPolicy.rawValue,
            "allowedModes": rule.allowedModes.map(\.rawValue).sorted(),
            "lifecycle": rule.lifecycle.rawValue,
            "source": rule.source.rawValue,
            "caseSensitive": rule.caseSensitive,
            "confidence": rule.confidence,
            "observedCount": rule.observedCount,
            "appliedCount": rule.appliedCount,
            "revertedCount": rule.revertedCount,
            "enabled": rule.isEnabled,
            "createdAt": Self.iso8601.string(from: rule.createdAt),
            "updatedAt": Self.iso8601.string(from: rule.updatedAt),
        ]
        addScope(rule.scope, to: &object)
        object["targetID"] = rule.targetID?.uuidString
        object["providerID"] = rule.providerID
        object["modelID"] = rule.modelID
        object["language"] = rule.language
        if let lastAppliedAt = rule.lastAppliedAt {
            object["lastAppliedAt"] = Self.iso8601.string(from: lastAppliedAt)
        }
        return object
    }

    private func importVoiceCorrection(_ object: [String: Any]) throws {
        let targets = object["targets"] as? [[String: Any]] ?? []
        let rules = object["rules"] as? [[String: Any]] ?? []
        for targetObject in targets {
            try environment.correctionTargetRepository.save(importTarget(targetObject))
        }
        for ruleObject in rules {
            try environment.correctionRuleRepository.save(importRule(ruleObject))
        }
        _ = environment.correctionSnapshotProvider.refresh()
    }

    private func importTarget(_ object: [String: Any]) throws -> CorrectionTargetTerm {
        let text = try requiredString("text", in: object)
        return CorrectionTargetTerm(
            id: UUID(uuidString: try requiredString("id", in: object)) ?? UUID(),
            text: text,
            normalizedText: object["normalizedText"] as? String ?? CorrectionTargetTerm.normalize(text),
            scope: scope(from: object),
            lifecycle: RuleLifecycle(rawValue: object["lifecycle"] as? String ?? "") ?? .active,
            source: RuleSource(rawValue: object["source"] as? String ?? "") ?? .imported,
            observedCount: object["observedCount"] as? Int ?? 0,
            appliedCount: object["appliedCount"] as? Int ?? 0,
            revertedCount: object["revertedCount"] as? Int ?? 0,
            createdAt: date("createdAt", in: object) ?? Date(),
            updatedAt: date("updatedAt", in: object) ?? Date(),
            lastAppliedAt: date("lastAppliedAt", in: object)
        )
    }

    private func importRule(_ object: [String: Any]) throws -> CorrectionRule {
        let allowedModeValues = object["allowedModes"] as? [String] ?? [CorrectionInputMode.dictation.rawValue]
        return CorrectionRule(
            id: UUID(uuidString: try requiredString("id", in: object)) ?? UUID(),
            targetID: (object["targetID"] as? String).flatMap(UUID.init(uuidString:)),
            original: try requiredString("original", in: object),
            replacement: try requiredString("replacement", in: object),
            matchPolicy: MatchPolicy(rawValue: object["matchPolicy"] as? String ?? "") ?? .boundary,
            scope: scope(from: object),
            allowedModes: Set(allowedModeValues.compactMap(CorrectionInputMode.init(rawValue:))),
            lifecycle: RuleLifecycle(rawValue: object["lifecycle"] as? String ?? "") ?? .active,
            source: RuleSource(rawValue: object["source"] as? String ?? "") ?? .imported,
            caseSensitive: object["caseSensitive"] as? Bool ?? false,
            confidence: object["confidence"] as? Double ?? 1,
            observedCount: object["observedCount"] as? Int ?? 0,
            appliedCount: object["appliedCount"] as? Int ?? 0,
            revertedCount: object["revertedCount"] as? Int ?? 0,
            providerID: object["providerID"] as? String,
            modelID: object["modelID"] as? String,
            language: object["language"] as? String,
            isEnabled: object["enabled"] as? Bool ?? true,
            createdAt: date("createdAt", in: object) ?? Date(),
            updatedAt: date("updatedAt", in: object) ?? Date(),
            lastAppliedAt: date("lastAppliedAt", in: object)
        )
    }

    private static let iso8601 = ISO8601DateFormatter()

    private func addScope(_ scope: RuleScope, to object: inout [String: Any]) {
        switch scope {
        case .global:
            object["scopeType"] = "global"
        case .application(let bundleIdentifier):
            object["scopeType"] = "application"
            object["scopeValue"] = bundleIdentifier
        }
    }

    private func scope(from object: [String: Any]) -> RuleScope {
        guard object["scopeType"] as? String == "application",
              let bundleIdentifier = object["scopeValue"] as? String,
              !bundleIdentifier.isEmpty else {
            return .global
        }
        return .application(bundleIdentifier: bundleIdentifier)
    }

    private func date(_ key: String, in object: [String: Any]) -> Date? {
        (object[key] as? String).flatMap(Self.iso8601.date(from:))
    }

    private func requiredString(_ key: String, in object: [String: Any]) throws -> String {
        guard let value = object[key] as? String else {
            throw SettingsViewModelError.invalidImport
        }
        return value
    }

    func resetSettings() throws {
        Self.logger.debug("settings_vm_reset_settings_start")
        let records = try environment.settingsRepository.list()
        for record in records {
            try environment.settingsRepository.deleteValue(forKey: record.key)
        }
        shortcutManager.resetToDefaults()
        asrSettingsResetter?.resetASRSettingsToDefaults()
        exportedDataJSON = nil
        load()
        lastError = nil
        lastActionMessage = persistentWriteMessage("已重置设置")
        Self.logger.info("settings_vm_reset_settings_success deletedSettings=\(records.count)")
    }

    func report(error: Error) {
        lastError = error.localizedDescription
        lastActionMessage = nil
        Self.logger.error("settings_vm_error error=\(error.localizedDescription)")
    }

    func clearFeedback() {
        lastError = nil
        lastActionMessage = nil
    }

    private func mcpDiagnosticsText(for agent: AgentSessionCard, logText: String) -> String {
        """
        协作命令: \(agent.mcpCommand ?? "-")
        参数: \(agent.mcpArgs.isEmpty ? "-" : agent.mcpArgs.joined(separator: " "))
        配置路径: \(agent.mcpConfigPath ?? "-")
        日志路径: \(agent.mcpLogPath ?? "-")
        最近连接: \(timestampText(agent.mcpSeenAt))
        上报时间: \(timestampText(agent.mcpReportedAt))
        最近请求: \(agent.mcpLastRequest ?? "-")
        最近错误: \(agent.mcpLastError ?? "-")

        --- Logs ---
        \(logText)
        """
    }

    private func timestampText(_ timestamp: TimeInterval?) -> String {
        guard let timestamp else { return "-" }
        return ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: timestamp))
    }

    private func readBool(_ key: String, defaultValue: Bool) throws -> Bool {
        try readSetting(key, defaultValue: defaultValue)
    }

    private func readString(_ key: String, defaultValue: String) throws -> String {
        try readSetting(key, defaultValue: defaultValue)
    }

    private func readTextInputMode() throws -> TextInputMode {
        if let explicitMode = try readOptionalTextInputMode() {
            return explicitMode
        }
        return systemOptions[.avoidClipboard] == true ? .simulatedTyping : .automatic
    }

    private func syncLaunchAtLoginOptionWithSystem() throws {
        let isEnabled = launchAtLoginManager.isEnabled
        systemOptions[.launchAtLogin] = isEnabled
        try setBool(SettingsSystemOption.launchAtLogin.rawValue, value: isEnabled)
    }

    private func readOptionalTextInputMode() throws -> TextInputMode? {
        guard let valueJSON = try environment.settingsRepository.value(forKey: SettingsKey.outputTextInputMode),
              let data = valueJSON.data(using: .utf8) else {
            return nil
        }
        let rawValue = try JSONDecoder().decode(DecodedSettingValue<String>.self, from: data).value
        return TextInputMode(rawValue: rawValue)
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

    private func wouldConflict(action: VoiceAction, keyCode: Int64?) -> Bool {
        guard let keyCode else { return false }
        switch action {
        case .dictation:
            return [.agentCompose].contains {
                shortcutManager.shortcutKeyCode(for: $0) == keyCode
            } || currentWorkflowShortcutKeyCodes(excluding: nil).contains(keyCode)
        case .agentCompose:
            return [.dictation].contains {
                shortcutManager.shortcutKeyCode(for: $0) == keyCode
            } || currentWorkflowShortcutKeyCodes(excluding: nil).contains(keyCode)
        case .agentDispatch:
            return false
        }
    }

    private func wouldConflict(workflowShortcut: HotKeyWorkflowShortcut, keyCode: Int64?) -> Bool {
        guard let keyCode else { return false }
        if workflowShortcut == .screenshotOCR,
           keyCode == ShortcutManager.defaultClipboardImageOCRShortcutKeyCode {
            return true
        }
        let voiceShortcutKeyCodes = [
            shortcutManager.shortcutKeyCode(for: .dictation),
            shortcutManager.shortcutKeyCode(for: .agentCompose),
        ]
        if voiceShortcutKeyCodes.contains(keyCode) {
            return true
        }
        return currentWorkflowShortcutKeyCodes(excluding: workflowShortcut).contains(keyCode)
    }

    private func currentWorkflowShortcutKeyCodes(excluding workflowShortcut: HotKeyWorkflowShortcut?) -> [Int64] {
        let shortcuts: [HotKeyWorkflowShortcut] = [
            .palette,
            .clipboardImageOCR,
            .screenshotOCR,
            .selectionAction,
            .selectionTranslate,
            .selectionSummarize,
            .selectionAgent,
            .selectionAskAI,
        ]
        return shortcuts.compactMap { shortcut in
            guard shortcut != workflowShortcut else { return nil }
            return shortcutManager.shortcutKeyCode(for: shortcut)
        }
    }

    private func readSetting<T: Decodable>(_ key: String, defaultValue: T) throws -> T {
        guard let valueJSON = try environment.settingsRepository.value(forKey: key),
              let data = valueJSON.data(using: .utf8) else {
            return defaultValue
        }
        return try JSONDecoder().decode(DecodedSettingValue<T>.self, from: data).value
    }

    private func applyRuntimeSettingsSnapshot() {
        LLMDiagnosticCapture.shared.configure(
            enabled: systemOption(.llmTraceDiagnostics),
            directory: paths?.llmTraceDiagnosticsDirectory
        )
    }

    private func deleteModelDirectoryContents(_ modelsDirectory: URL) throws {
        if fileManager.fileExists(atPath: modelsDirectory.path) {
            let contents = try fileManager.contentsOfDirectory(
                at: modelsDirectory,
                includingPropertiesForKeys: nil
            )
            for url in contents {
                try fileManager.removeItem(at: url)
            }
        }
        try fileManager.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
    }

    private func directoryAllocatedBytes(_ directory: URL) -> Int64 {
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(
                forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isDirectoryKey]
            ), values.isDirectory != true else {
                continue
            }
            total += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }
        return total
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

    private func persistentWriteMessage(_ message: String) -> String {
        guard !storageStatus.isHealthy else {
            return message
        }
        switch environment.storageHealth {
        case .unavailable, .volatile:
            return "\(message)（仅当前会话生效，重启后可能丢失）"
        case .readOnly, .migrationRequired, .corrupt:
            return "\(message)（存储状态：\(storageStatus.badgeText)，不保证已持久保存）"
        case .persistent:
            return message
        }
    }
}

enum SettingsViewModelError: LocalizedError {
    case invalidImport
    case invalidShortcutKeyCode
    case unsupportedShortcutKeyCode
    case unsupportedWorkflowShortcutKeyCode
    case conflictingBindings

    var errorDescription: String? {
        switch self {
        case .invalidImport:
            return "导入数据格式不正确。"
        case .invalidShortcutKeyCode:
            return "快捷键录制失败，请按下一个有效按键。"
        case .unsupportedShortcutKeyCode:
            return "语音快捷键支持单独 Command、Option、Control、Shift，或带这些修饰键的组合键。"
        case .unsupportedWorkflowShortcutKeyCode:
            return "图片识别快捷键需要使用带修饰键的普通按键组合，不能使用单键或系统编辑快捷键。"
        case .conflictingBindings:
            return "两个操作不能使用相同的快捷键，请修改其中一个。"
        }
    }
}

private extension HotKeyWorkflowShortcut {
    var displayName: String {
        switch self {
        case .palette:
            return "启动台"
        case .clipboardImageOCR:
            return "剪贴板图片识别"
        case .screenshotOCR:
            return "截图文字识别"
        case .selectionAction:
            return "划词动作"
        case .selectionTranslate:
            return "划词翻译"
        case .selectionSummarize:
            return "划词总结"
        case .selectionAgent:
            return "发给任务助手"
        case .selectionAskAI:
            return "划词问 AI"
        case .cancel:
            return "取消"
        }
    }
}

struct DecodedSettingValue<T: Decodable>: Decodable {
    let value: T
}

struct EncodedSettingValue<T: Encodable>: Encodable {
    let value: T
}
