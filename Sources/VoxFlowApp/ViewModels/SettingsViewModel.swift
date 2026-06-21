@preconcurrency import AVFoundation
import AppKit
import Combine
import Foundation
import ApplicationServices

enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case vibeCoding
    case dictationModels
    case correctionModels
    case ttsModels
    case translationModels
    case system
    case dataPrivacy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "通用"
        case .vibeCoding: return "Vibe Coding"
        case .dictationModels: return "ASR 模型"
        case .correctionModels: return "LLM 模型"
        case .ttsModels: return "TTS 模型"
        case .translationModels: return "翻译模型"
        case .system: return "系统"
        case .dataPrivacy: return "数据与隐私"
        }
    }

    var systemImage: String {
        switch self {
        case .general: return "slider.horizontal.3"
        case .vibeCoding: return "terminal"
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
    @Published var selectedSection: SettingsSection = .general
    @Published private(set) var inputDevices: [AudioInputDevice] = []
    @Published private(set) var selectedInputDeviceID = ""
    @Published private(set) var shortcutKeyCode: Int64 = ShortcutManager.defaultShortcutKeyCode
    @Published private(set) var longPressThreshold: TimeInterval = ShortcutManager.defaultLongPressThreshold
    @Published private(set) var shortPressBehavior: ShortPressBehavior = .toggleListening
    @Published private(set) var dictationShortcutKeyCode: Int64? = nil
    @Published private(set) var agentComposeShortcutKeyCode: Int64? = nil
    @Published private(set) var agentDispatchEnabled = false
    @Published private(set) var agentDispatchExactDirectEnabled = true
    @Published private(set) var agentDispatchMCPEnabled = true
    @Published private(set) var agentDispatchUnresolvedBehavior = "confirm"
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
    private let paths: ApplicationSupportPaths?
    private let fileManager: FileManager
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
        paths: ApplicationSupportPaths? = nil,
        fileManager: FileManager = .default
    ) {
        self.environment = environment
        self.shortcutManager = shortcutManager
        self.audioDeviceProvider = audioDeviceProvider
        self.permissionProvider = permissionProvider
        self.languageManager = languageManager
        self.asrSettingsResetter = asrSettingsResetter
        self.localModelDeletionCoordinator = localModelDeletionCoordinator
        self.paths = paths ?? environment.paths
        self.fileManager = fileManager
        self.storageStatus = SettingsStorageStatus(storageHealth: environment.storageHealth)
        load()
        languageObserverID = languageManager.observeLanguageChanges { [weak self] language in
            self?.selectedRecognitionLanguage = language
        }
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
            dictationShortcutKeyCode = shortcutManager.shortcutKeyCode(for: .dictation)
            agentComposeShortcutKeyCode = shortcutManager.shortcutKeyCode(for: .agentCompose)
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
            textInputMode = try readTextInputMode()
            microphonePermission = permissionProvider.microphonePermission()
            speechPermission = permissionProvider.speechPermission()
            accessibilityGranted = AXIsProcessTrusted()
            screenRecordingGranted = permissionProvider.screenRecordingPermission()
            storageStatus = SettingsStorageStatus(storageHealth: environment.storageHealth)
            applyRuntimeSettingsSnapshot()
            hasLoaded = true
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func loadIfNeeded() {
        guard !hasLoaded else {
            return
        }
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
        guard ShortcutManager.isSupportedVoiceShortcutKeyCode(keyCode) else {
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
        self.shortcutConflict = shortcutManager.hasConflict()
        lastError = nil
        lastActionMessage = "已更新快捷键设置"
    }

    func updateActionShortcut(
        action: VoiceAction,
        keyCode: Int64?
    ) throws {
        if let keyCode, !ShortcutManager.isSupportedVoiceShortcutKeyCode(keyCode) {
            throw SettingsViewModelError.unsupportedShortcutKeyCode
        }
        if wouldConflict(action: action, keyCode: keyCode) {
            throw SettingsViewModelError.conflictingBindings
        }
        shortcutManager.setShortcutKeyCode(keyCode, for: action)
        shortcutKeyCode = shortcutManager.shortcutKeyCode
        dictationShortcutKeyCode = shortcutManager.shortcutKeyCode(for: .dictation)
        agentComposeShortcutKeyCode = shortcutManager.shortcutKeyCode(for: .agentCompose)
        shortcutConflict = false
        lastError = nil
        lastActionMessage = "已更新\(action.displayName)快捷键"
    }

    func setAgentDispatchEnabled(_ enabled: Bool) throws {
        agentDispatchEnabled = enabled
        try setBool(SettingsKey.agentDispatchEnabled, value: enabled)
        lastActionMessage = enabled
            ? "已启用 Vibe Coding 指挥中心"
            : "已关闭 Vibe Coding 指挥中心"
    }

    func setAgentDispatchExactDirectEnabled(_ enabled: Bool) throws {
        agentDispatchExactDirectEnabled = enabled
        try setBool(SettingsKey.agentDispatchExactDirectEnabled, value: enabled)
        lastActionMessage = "已更新准确命名发送策略"
    }

    func setAgentDispatchUnresolvedBehavior(_ behavior: String) throws {
        guard ["confirm", "cancel", "model", "default"].contains(behavior) else { return }
        agentDispatchUnresolvedBehavior = behavior
        try setString(SettingsKey.agentDispatchUnresolvedBehavior, value: behavior)
        lastActionMessage = "已更新未命中处理方式"
    }

    func setAgentDispatchMCPEnabled(_ enabled: Bool) throws {
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
        lastActionMessage = "已更新 MCP 自报身份设置"
    }

    func refreshAgentSessions(reportFailures: Bool = true) async {
        guard let paths else { return }
        do {
            let client = AgentRouterClient(socketURL: paths.agentRouterSocketURL)
            agentSessions = try await client.listAllAgents()
            agentAliases = try await client.listAliases()
            agentDispatchLogs = try await client.listDispatchLog()
            lastError = nil
        } catch {
            agentSessions = []
            if reportFailures {
                lastError = error.localizedDescription
            }
        }
    }

    func addAgentAlias(_ alias: String, agentID: String) async {
        guard let paths else { return }
        let trimmed = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            let client = AgentRouterClient(socketURL: paths.agentRouterSocketURL)
            try await client.learnAlias(trimmed, agentID: agentID, userConfirmed: true)
            agentAliases = try await client.listAliases()
            lastError = nil
            lastActionMessage = "已保存队员别名"
        } catch {
            report(error: error)
        }
    }

    func removeAgentAlias(_ alias: String) async {
        guard let paths else { return }
        do {
            let client = AgentRouterClient(socketURL: paths.agentRouterSocketURL)
            try await client.removeAlias(alias)
            agentAliases = try await client.listAliases()
            lastError = nil
            lastActionMessage = "已删除队员别名"
        } catch {
            report(error: error)
        }
    }

    func setAgentAlias(_ alias: String, for agentID: String) async {
        guard let paths else { return }
        let trimmed = alias.trimmingCharacters(in: .whitespacesAndNewlines)
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
            lastActionMessage = trimmed.isEmpty ? "已清空队员别名" : "已更新队员别名"
        } catch {
            report(error: error)
        }
    }

    func cleanStaleAgentSessions() async {
        guard let paths else { return }
        do {
            let client = AgentRouterClient(socketURL: paths.agentRouterSocketURL)
            try await client.cleanStaleSessions()
            await refreshAgentSessions()
            lastActionMessage = "已清理失效队员"
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
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(
            "voxflow run -- \(agent.command.joined(separator: " "))",
            forType: .string
        )
        lastActionMessage = "已复制队员启动命令"
    }

    func registerAgentCLI() {
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
        } catch {
            report(error: error)
        }
    }

    func unregisterAgentCLI() {
        guard let paths else {
            report(error: ApplicationSupportPathsError.applicationSupportDirectoryUnavailable)
            return
        }
        do {
            try AgentHelperManager(paths: paths).unregisterCLI()
            agentCLIRegistrationStatus = nil
            lastError = nil
            lastActionMessage = "终端命令已卸载"
        } catch {
            report(error: error)
        }
    }

    func agentCLIRegistrationPreview() -> AgentCLIRegistrationPreview {
        AgentHelperManager.registrationPreview()
    }

    func copyAgentCLIExamples() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(
            "vox flow codex\nvox flow --claude\nvox flow --codebuddy",
            forType: .string
        )
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

    func systemOption(_ option: SettingsSystemOption) -> Bool {
        systemOptions[option] ?? option.defaultValue
    }

    func setSystemOption(_ option: SettingsSystemOption, enabled: Bool) throws {
        systemOptions[option] = enabled
        try setBool(option.rawValue, value: enabled)
        if option == .avoidClipboard {
            try setTextInputMode(enabled ? .simulatedTyping : .automatic)
        }
        applyRuntimeSettingsSnapshot()
        lastError = nil
        lastActionMessage = persistentWriteMessage("已更新系统设置")
    }

    func clearLLMTraceDiagnostics() {
        LLMDiagnosticCapture.shared.clear()
        lastError = nil
        lastActionMessage = "已删除 LLM 诊断内容"
    }

    func setTextInputMode(_ mode: TextInputMode) throws {
        textInputMode = mode
        try setString(SettingsKey.outputTextInputMode, value: mode.rawValue)
        systemOptions[.avoidClipboard] = mode == .simulatedTyping
        try setBool(SettingsSystemOption.avoidClipboard.rawValue, value: mode == .simulatedTyping)
        lastError = nil
        lastActionMessage = persistentWriteMessage("已更新文本输入模式")
    }

    func setRecognitionLanguage(_ language: RecognitionLanguage) throws {
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
        let entries = try environment.historyRepository.listRecent(limit: 100_000)
        for entry in entries {
            try environment.historyRepository.softDelete(id: entry.id, deletedAt: environment.clock.now)
        }
        lastError = nil
        lastActionMessage = persistentWriteMessage("已清空历史")
    }

    func clearCache() throws {
        try deleteAllLocalModels()
    }

    func deleteAllLocalModels() throws {
        guard let paths else {
            lastError = "没有可用的数据目录，本地模型未删除。"
            lastActionMessage = nil
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
        lastActionMessage = persistentWriteMessage("已导入设置")
    }

    func resetSettings() throws {
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

    private func readTextInputMode() throws -> TextInputMode {
        if let explicitMode = try readOptionalTextInputMode() {
            return explicitMode
        }
        return systemOptions[.avoidClipboard] == true ? .simulatedTyping : .automatic
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
            }
        case .agentCompose:
            return [.dictation].contains {
                shortcutManager.shortcutKeyCode(for: $0) == keyCode
            }
        case .agentDispatch:
            return false
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
    case conflictingBindings

    var errorDescription: String? {
        switch self {
        case .invalidImport:
            return "导入数据格式不正确。"
        case .invalidShortcutKeyCode:
            return "快捷键录制失败，请按下一个有效按键。"
        case .unsupportedShortcutKeyCode:
            return "语音快捷键支持单独 Command、Option、Control、Shift，或带这些修饰键的组合键；Command+Shift+A/V 已保留给 OCR。"
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
