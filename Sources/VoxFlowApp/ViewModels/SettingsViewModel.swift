@preconcurrency import AVFoundation
import AppKit
import Combine
import Foundation
import ApplicationServices
import VoxFlowVoiceCorrection
import VoxFlowTextProcessing

enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case vibeCoding
    case system
    case textProcessing
    case dictationModels
    case correctionModels
    case ttsModels
    case translationModels
    case dataPrivacy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return L10n.localize("settings.section.general", comment: "")
        case .vibeCoding: return L10n.localize("settings.section.vibe_coding", comment: "")
        case .system: return L10n.localize("settings.section.system_root", comment: "")
        case .textProcessing: return L10n.localize("settings.section.text_processing", comment: "")
        case .dictationModels: return L10n.localize("settings.section.dictation_models", comment: "")
        case .correctionModels: return L10n.localize("settings.section.correction_models", comment: "")
        case .ttsModels: return L10n.localize("settings.section.tts_models", comment: "")
        case .translationModels: return L10n.localize("settings.section.translation_models", comment: "")
        case .dataPrivacy: return L10n.localize("settings.section.data_privacy", comment: "")
        }
    }

    var systemImage: String {
        switch self {
        case .general: return "slider.horizontal.3"
        case .vibeCoding: return "terminal"
        case .textProcessing: return "wand.and.stars"
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
    case hideDockIconWhenWorkbenchCloses = "settings.appearance.hideDockIconWhenWorkbenchCloses"
    case crashLogs = "settings.privacy.crashLogs"
    case llmTraceDiagnostics = "settings.privacy.llmTraceDiagnostics"

    var defaultValue: Bool {
        switch self {
        case .restoreClipboard, .clipboardImageOCR, .hideDockIconWhenWorkbenchCloses, .llmTraceDiagnostics:
            return true
        default:
            return false
        }
    }
}

typealias LatestCrashReportProviding = () -> SystemCrashReport?
typealias ManualCrashReportSending = (ManualCrashReportPayload) -> CrashReportSendResult

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
            title = L10n.localize("settings.storage.title.persistent", comment: "")
            message = L10n.format("settings.storage.message.persistent", comment: "",
                databaseURL.path
            )
            isHealthy = true
            badgeText = L10n.localize("settings.storage.badge.normal", comment: "")
        case let .readOnly(databaseURL, reason):
            title = L10n.localize("settings.storage.title.read_only", comment: "")
            message = reason
            + L10n.localize("settings.storage.read_only_message", comment: "Read-only storage message")
            + " "
            + databaseURL.path
            + L10n.localize("settings.storage.read_only_message_suffix", comment: "Read-only storage message")
            isHealthy = false
            badgeText = L10n.localize("settings.storage.badge.read_only", comment: "")
        case let .migrationRequired(databaseURL, reason):
            title = L10n.localize("settings.storage.title.migration_required", comment: "")
            message = L10n.format("settings.storage.message.migration_required", comment: "",
                reason,
                databaseURL.path
            )
            isHealthy = false
            badgeText = L10n.localize("settings.storage.badge.migration_required", comment: "")
        case let .corrupt(databaseURL, reason):
            title = L10n.localize("settings.storage.title.corrupt", comment: "")
            message = L10n.format("settings.storage.message.corrupt", comment: "",
                reason,
                databaseURL.path
            )
            isHealthy = false
            badgeText = L10n.localize("settings.storage.badge.corrupt", comment: "")
        case let .unavailable(reason):
            title = L10n.localize("settings.storage.title.unavailable", comment: "")
            message = L10n.format("settings.storage.message.unavailable", comment: "",
                reason
            )
            isHealthy = false
            badgeText = L10n.localize("settings.storage.badge.unavailable", comment: "")
        case let .volatile(reason):
            title = L10n.localize("settings.storage.title.volatile", comment: "")
            message = L10n.format("settings.storage.message.volatile", comment: "",
                reason
            )
            isHealthy = false
            badgeText = L10n.localize("settings.storage.badge.volatile", comment: "")
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
    static let systemDefaultDeviceName = L10n.localize("settings.audio_input.default_system_device", comment: "")

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
            return L10n.localize("settings.audio_input.unknown_device", comment: "")
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
    @Published private(set) var textInputMode: TextInputMode = .automatic
    @Published private(set) var recognitionLanguages: [RecognitionLanguage] = RecognitionLanguage.allCases
    @Published private(set) var selectedRecognitionLanguage: RecognitionLanguage = .default
    @Published private(set) var interfaceLanguage: AppLanguage = .default
    @Published private(set) var systemOptions: [SettingsSystemOption: Bool] = [:]
    @Published private(set) var microphonePermission: AudioRecorder.PermissionStatus = .notDetermined
    @Published private(set) var speechPermission: AudioRecorder.PermissionStatus = .notDetermined
    @Published private(set) var accessibilityGranted = false
    @Published private(set) var screenRecordingGranted = false
    @Published private(set) var storageStatus: SettingsStorageStatus
    @Published private(set) var exportedDataJSON: String?
    @Published private(set) var latestCrashReportSummaryText: String?
    @Published private(set) var latestCrashReportAwaitingSendConfirmation = false
    @Published private(set) var lastError: String?
    @Published private(set) var lastActionMessage: String?

    // MARK: - Deterministic text processing settings (section 3)
    // UI entry point for the deterministic text processing pipeline.
    // Visual design will be added later; these fields expose the state.
    @Published private(set) var deterministicTextProcessingEnabled = false
    @Published private(set) var deterministicSmartNumberRecognition = false
    @Published private(set) var deterministicPunctuationOptimization = false
    @Published private(set) var deterministicLongSentenceBreaking = false
    @Published private(set) var deterministicFillerWordFiltering = false
    @Published private(set) var deterministicCjkLatinSpacing = false
    @Published private(set) var deterministicAutoCapitalization = false
    // Thresholds exposed for advanced tuning. Bound to Steppers in the UI.
    @Published private(set) var deterministicLongSentenceWordThreshold = DeterministicTextProcessingSettings.defaults.longSentenceWordThreshold
    @Published private(set) var deterministicLongSentenceCJKThreshold = DeterministicTextProcessingSettings.defaults.longSentenceCJKThreshold
    @Published private(set) var deterministicPunctuationWordThreshold = 4
    @Published private(set) var deterministicPunctuationCJKThreshold = 3

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
    private let interfaceLanguageManager: InterfaceLanguageManager
    private let asrSettingsResetter: (any ASRSettingsResetting)?
    private let localModelDeletionCoordinator: (any LocalModelDeletionCoordinating)?
    private let launchAtLoginManager: any LaunchAtLoginManaging
    private let paths: ApplicationSupportPaths?
    private let fileManager: FileManager
    private let clipboardWriter: ClipboardWriting
    private let latestCrashReportProvider: LatestCrashReportProviding
    private let manualCrashReportSender: ManualCrashReportSending
    private var languageObserverID: UUID?
    private var hasLoaded = false

    init(
        environment: any AppServiceProviding,
        shortcutManager: ShortcutManager = .shared,
        audioDeviceProvider: any AudioInputDeviceProviding = SystemAudioInputDeviceProvider(),
        permissionProvider: any SettingsPermissionProviding = SystemSettingsPermissionProvider(),
        languageManager: LanguageManager = .shared,
        interfaceLanguageManager: InterfaceLanguageManager = .shared,
        asrSettingsResetter: (any ASRSettingsResetting)? = nil,
        localModelDeletionCoordinator: (any LocalModelDeletionCoordinating)? = nil,
        launchAtLoginManager: any LaunchAtLoginManaging = SystemLaunchAtLoginManager(),
        paths: ApplicationSupportPaths? = nil,
        fileManager: FileManager = .default,
        clipboardWriter: ClipboardWriting = GeneralPasteboardWriter(),
        latestCrashReportProvider: @escaping LatestCrashReportProviding = {
            SystemCrashReportScanner().latestReport()
        },
        manualCrashReportSender: @escaping ManualCrashReportSending = { payload in
            CrashReporterService.shared.sendManualCrashReport(payload, configuration: .live())
        }
    ) {
        self.environment = environment
        self.shortcutManager = shortcutManager
        self.audioDeviceProvider = audioDeviceProvider
        self.permissionProvider = permissionProvider
        self.languageManager = languageManager
        self.interfaceLanguageManager = interfaceLanguageManager
        self.asrSettingsResetter = asrSettingsResetter
        self.localModelDeletionCoordinator = localModelDeletionCoordinator
        self.launchAtLoginManager = launchAtLoginManager
        self.paths = paths ?? environment.paths
        self.fileManager = fileManager
        self.clipboardWriter = clipboardWriter
        self.latestCrashReportProvider = latestCrashReportProvider
        self.manualCrashReportSender = manualCrashReportSender
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
            // Deterministic text processing settings (section 3).
            let dtpSettings = DeterministicTextProcessingSettingsStore.load(
                storage: SettingsRepositoryKeyValueAdapter(repository: environment.settingsRepository)
            )
            deterministicTextProcessingEnabled = dtpSettings.enabled
            deterministicSmartNumberRecognition = dtpSettings.smartNumberRecognition
            deterministicPunctuationOptimization = dtpSettings.punctuationOptimization
            deterministicLongSentenceBreaking = dtpSettings.longSentenceBreaking
            deterministicFillerWordFiltering = dtpSettings.fillerWordFiltering
            deterministicCjkLatinSpacing = dtpSettings.cjkLatinSpacing
            deterministicAutoCapitalization = dtpSettings.autoCapitalization
            deterministicLongSentenceWordThreshold = dtpSettings.longSentenceWordThreshold
            deterministicLongSentenceCJKThreshold = dtpSettings.longSentenceCJKThreshold
            deterministicPunctuationWordThreshold = dtpSettings.punctuationWordThreshold
            deterministicPunctuationCJKThreshold = dtpSettings.punctuationCJKThreshold
            shortcutConflict = shortcutManager.hasConflict()
            soundFeedbackEnabled = try readBool(SettingsKey.audioSoundFeedbackEnabled, defaultValue: true)
            voiceEnhancementEnabled = try readBool(SettingsKey.audioVoiceEnhancementEnabled, defaultValue: false)
            muteWhileRecordingEnabled = try readBool(SettingsKey.audioMuteWhileRecordingEnabled, defaultValue: false)
            performanceOptimizationEnabled = try readBool(SettingsKey.performanceOptimizationEnabled, defaultValue: false)
            recognitionLanguages = languageManager.allLanguages
            selectedRecognitionLanguage = languageManager.currentLanguage
            interfaceLanguage = interfaceLanguageManager.currentLanguage
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
        lastActionMessage = persistentWriteMessage(L10n.localize("settings.message.input_device_updated", comment: ""))
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
        lastActionMessage = L10n.localize("settings.message.shortcuts_updated", comment: "")
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
        lastActionMessage = L10n.format("settings.message.action_shortcut_updated_format", comment: "", action.displayName)
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
        lastActionMessage = L10n.format("settings.message.workflow_shortcut_updated_format", comment: "", shortcut.displayName)
        Self.logger.info("settings_vm_update_workflow_shortcut_success shortcut=\(shortcut.displayName) keyCode=\(keyCode.map(String.init) ?? "nil") conflict=\(shortcutConflict)")
    }

    func setAgentDispatchEnabled(_ enabled: Bool) throws {
        Self.logger.debug("settings_vm_set_agent_dispatch_enabled enabled=\(enabled)")
        agentDispatchEnabled = enabled
        try setBool(SettingsKey.agentDispatchEnabled, value: enabled)
        lastActionMessage = enabled
            ? L10n.localize("settings.message.agent_dispatch_enabled", comment: "")
            : L10n.localize("settings.message.agent_dispatch_disabled", comment: "")
    }

    func setAgentDispatchExactDirectEnabled(_ enabled: Bool) throws {
        Self.logger.debug("settings_vm_set_agent_dispatch_exact_direct enabled=\(enabled)")
        agentDispatchExactDirectEnabled = enabled
        try setBool(SettingsKey.agentDispatchExactDirectEnabled, value: enabled)
        lastActionMessage = L10n.localize("settings.message.agent_dispatch_exact_send", comment: "")
    }

    func setAgentDispatchUnresolvedBehavior(_ behavior: String) throws {
        guard ["confirm", "cancel", "model", "default"].contains(behavior) else {
            Self.logger.warning("settings_vm_set_agent_dispatch_unresolved_rejected behavior=\(behavior)")
            return
        }
        Self.logger.debug("settings_vm_set_agent_dispatch_unresolved behavior=\(behavior)")
        agentDispatchUnresolvedBehavior = behavior
        try setString(SettingsKey.agentDispatchUnresolvedBehavior, value: behavior)
        lastActionMessage = L10n.localize("settings.message.agent_dispatch_unresolved_behavior", comment: "")
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
        lastActionMessage = L10n.localize("settings.message.agent_dispatch_mcp", comment: "")
    }

    func setVoiceCorrectionEnabled(_ enabled: Bool) throws {
        Self.logger.debug("settings_vm_set_voice_correction_enabled enabled=\(enabled)")
        voiceCorrectionEnabled = enabled
        try VoiceCorrectionSettingsStore.setBool(.enabled, value: enabled, repository: environment.settingsRepository)
        lastError = nil
        lastActionMessage = enabled ? L10n.localize("settings.message.voice_correction_enabled", comment: "") : L10n.localize("settings.message.voice_correction_disabled", comment: "")
    }

    func setVoiceCorrectionAutoLearningEnabled(_ enabled: Bool) throws {
        Self.logger.debug("settings_vm_set_voice_correction_auto_learning enabled=\(enabled)")
        voiceCorrectionAutoLearningEnabled = enabled
        try VoiceCorrectionSettingsStore.setBool(.autoLearningEnabled, value: enabled, repository: environment.settingsRepository)
        lastError = nil
        lastActionMessage = enabled ? L10n.localize("settings.message.voice_correction_auto_learning_enabled", comment: "") : L10n.localize("settings.message.voice_correction_auto_learning_disabled", comment: "")
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
        lastActionMessage = enabled ? L10n.localize("settings.message.voice_correction_auto_apply_immediate", comment: "") : L10n.localize("settings.message.voice_correction_auto_apply_pending", comment: "")
    }

    func setVoiceCorrectionShadowMode(_ enabled: Bool) throws {
        Self.logger.debug("settings_vm_set_voice_correction_shadow enabled=\(enabled)")
        voiceCorrectionShadowMode = enabled
        try VoiceCorrectionSettingsStore.setBool(.shadowMode, value: enabled, repository: environment.settingsRepository)
        lastError = nil
        lastActionMessage = enabled ? L10n.localize("settings.message.voice_correction_shadow_mode_enabled", comment: "") : L10n.localize("settings.message.voice_correction_shadow_mode_disabled", comment: "")
    }

    // MARK: - Deterministic text processing settings (section 3)

    func updateDeterministicTextProcessing(
        enabled: Bool? = nil,
        smartNumberRecognition: Bool? = nil,
        punctuationOptimization: Bool? = nil,
        longSentenceBreaking: Bool? = nil,
        fillerWordFiltering: Bool? = nil,
        cjkLatinSpacing: Bool? = nil,
        autoCapitalization: Bool? = nil
    ) throws {
        var current = DeterministicTextProcessingSettingsStore.load(
            storage: SettingsRepositoryKeyValueAdapter(repository: environment.settingsRepository)
        )
        if let enabled { current.enabled = enabled }
        if let smartNumberRecognition { current.smartNumberRecognition = smartNumberRecognition }
        if let punctuationOptimization { current.punctuationOptimization = punctuationOptimization }
        if let longSentenceBreaking { current.longSentenceBreaking = longSentenceBreaking }
        if let fillerWordFiltering { current.fillerWordFiltering = fillerWordFiltering }
        if let cjkLatinSpacing { current.cjkLatinSpacing = cjkLatinSpacing }
        if let autoCapitalization { current.autoCapitalization = autoCapitalization }
        try DeterministicTextProcessingSettingsStore.save(
            current,
            storage: SettingsRepositoryKeyValueAdapter(repository: environment.settingsRepository)
        )
        deterministicTextProcessingEnabled = current.enabled
        deterministicSmartNumberRecognition = current.smartNumberRecognition
        deterministicPunctuationOptimization = current.punctuationOptimization
        deterministicLongSentenceBreaking = current.longSentenceBreaking
        deterministicFillerWordFiltering = current.fillerWordFiltering
        deterministicCjkLatinSpacing = current.cjkLatinSpacing
        deterministicAutoCapitalization = current.autoCapitalization
        Self.logger.debug("settings_vm_set_deterministic_text_processing saved")
        lastError = nil
    }

    /// Updates the deterministic text processing thresholds. Each parameter is
    /// optional; only non-nil values are written. Values are clamped to a
    /// sensible positive range to avoid breaking the pipeline with 0 or
    /// negative thresholds.
    func updateDeterministicTextProcessingThresholds(
        longSentenceWord: Int? = nil,
        longSentenceCJK: Int? = nil,
        punctuationWord: Int? = nil,
        punctuationCJK: Int? = nil
    ) throws {
        var current = DeterministicTextProcessingSettingsStore.load(
            storage: SettingsRepositoryKeyValueAdapter(repository: environment.settingsRepository)
        )
        if let longSentenceWord {
            current.longSentenceWordThreshold = max(1, longSentenceWord)
        }
        if let longSentenceCJK {
            current.longSentenceCJKThreshold = max(1, longSentenceCJK)
        }
        if let punctuationWord {
            current.punctuationWordThreshold = max(1, punctuationWord)
        }
        if let punctuationCJK {
            current.punctuationCJKThreshold = max(1, punctuationCJK)
        }
        try DeterministicTextProcessingSettingsStore.save(
            current,
            storage: SettingsRepositoryKeyValueAdapter(repository: environment.settingsRepository)
        )
        deterministicLongSentenceWordThreshold = current.longSentenceWordThreshold
        deterministicLongSentenceCJKThreshold = current.longSentenceCJKThreshold
        deterministicPunctuationWordThreshold = current.punctuationWordThreshold
        deterministicPunctuationCJKThreshold = current.punctuationCJKThreshold
        Self.logger.debug("settings_vm_set_deterministic_text_processing_thresholds saved")
        lastError = nil
    }

    func resetLongSentenceThresholds() throws {
        let defaults = DeterministicTextProcessingSettings.defaults
        try updateDeterministicTextProcessingThresholds(
            longSentenceWord: defaults.longSentenceWordThreshold,
            longSentenceCJK: defaults.longSentenceCJKThreshold
        )
        lastActionMessage = L10n.localize("settings.text_processing.thresholds.reset_feedback", comment: "")
    }

    func resetPunctuationThresholds() throws {
        let defaults = DeterministicTextProcessingSettings.defaults
        try updateDeterministicTextProcessingThresholds(
            punctuationWord: defaults.punctuationWordThreshold,
            punctuationCJK: defaults.punctuationCJKThreshold
        )
        lastActionMessage = L10n.localize("settings.text_processing.thresholds.reset_feedback", comment: "")
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
            lastActionMessage = L10n.localize("settings.message.agent_alias_saved", comment: "")
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
            lastActionMessage = L10n.localize("settings.message.agent_alias_deleted", comment: "")
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
            lastActionMessage = trimmed.isEmpty ? L10n.localize("settings.message.agent_alias_cleared", comment: "") : L10n.localize("settings.message.agent_alias_updated", comment: "")
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
            lastActionMessage = L10n.localize("settings.message.stale_agent_sessions_cleared", comment: "")
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
            lastActionMessage = L10n.localize("settings.message.agent_session_stopped", comment: "")
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
            lastActionMessage = L10n.localize("settings.message.dispatch_log_cleared", comment: "")
        } catch {
            report(error: error)
        }
    }

    func copyAgentLaunchCommand(_ agent: AgentSessionCard) {
        Self.logger.info("settings_vm_copy_agent_launch_command agentID=\(agent.agentID) argCount=\(agent.command.count)")
        clipboardWriter.copy("voxflow run -- \(agent.command.joined(separator: " "))")
        lastActionMessage = L10n.localize("settings.message.agent_launch_command_copied", comment: "")
    }

    func mcpLogSnapshot(for agent: AgentSessionCard) -> AgentMCPLogSnapshot {
        guard let path = agent.mcpLogPath, !path.isEmpty else {
            return AgentMCPLogSnapshot(
                text: L10n.localize("settings.message.mcp_log_path_missing", comment: ""),
                fileExists: false
            )
        }
        let url = URL(fileURLWithPath: path)
        guard fileManager.fileExists(atPath: url.path) else {
            return AgentMCPLogSnapshot(
            text: L10n.localize("settings.message.mcp_log_not_created", comment: ""),
                fileExists: false
            )
        }
        do {
            let data = try Data(contentsOf: url)
            let text = String(data: data, encoding: .utf8) ?? L10n.localize("settings.message.mcp_log_not_utf8", comment: "")
            return AgentMCPLogSnapshot(
                text: text.isEmpty ? L10n.localize("settings.message.mcp_log_empty", comment: "") : text,
                fileExists: true
            )
        } catch {
            return AgentMCPLogSnapshot(
                text: L10n.format("settings.message.mcp_log_read_failed", comment: "", error.localizedDescription),
                fileExists: false
            )
        }
    }

    func copyMCPDiagnostics(for agent: AgentSessionCard, logText: String) {
        Self.logger.info("settings_vm_copy_mcp_diagnostics agentID=\(agent.agentID) logLen=\(logText.count)")
        clipboardWriter.copy(mcpDiagnosticsText(for: agent, logText: logText))
        lastError = nil
        lastActionMessage = L10n.localize("settings.message.mcp_diagnostics_copied", comment: "")
    }

    func openMCPLogFile(for agent: AgentSessionCard) {
        Self.logger.debug("settings_vm_open_mcp_log_file_start agentID=\(agent.agentID) hasPath=\(!(agent.mcpLogPath ?? "").isEmpty)")
        guard let path = agent.mcpLogPath, !path.isEmpty else {
            lastError = L10n.localize("settings.message.mcp_log_path_missing", comment: "")
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
                lastError = L10n.localize("settings.message.mcp_log_open_failed", comment: "")
                lastActionMessage = nil
                Self.logger.warning("settings_vm_open_mcp_log_file_failed agentID=\(agent.agentID) reason=workspaceOpen")
                return
            }
            lastError = nil
            lastActionMessage = L10n.localize("settings.message.mcp_log_opened", comment: "")
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
                ? L10n.localize("settings.message.agent_cli_registered", comment: "")
                : L10n.localize("settings.message.agent_cli_registered_shell_hint", comment: "")
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
            lastActionMessage = L10n.localize("settings.message.agent_cli_unregistered", comment: "")
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
        lastActionMessage = L10n.localize("settings.message.agent_cli_command_copied", comment: "")
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
            lastActionMessage = L10n.localize("settings.message.shortcut_applied", comment: "")
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
        lastActionMessage = persistentWriteMessage(L10n.localize("settings.message.audio_settings_updated", comment: ""))
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
        lastActionMessage = persistentWriteMessage(L10n.localize("settings.message.system_settings_updated", comment: ""))
    }

    func setMiddleMouseRecordingEnabled(_ enabled: Bool) throws {
        middleMouseRecordingEnabled = enabled
        shortcutManager.middleMouseRecordingEnabled = enabled
        lastError = nil
        lastActionMessage = enabled ? L10n.localize("settings.message.middle_mouse_recording_enabled", comment: "") : L10n.localize("settings.message.middle_mouse_recording_disabled", comment: "")
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
        lastActionMessage = persistentWriteMessage(L10n.localize("settings.message.system_settings_updated", comment: ""))
    }

    private func setLaunchAtLoginOption(_ enabled: Bool) throws {
        Self.logger.debug("settings_vm_set_launch_at_login_start enabled=\(enabled)")
        do {
            try launchAtLoginManager.setEnabled(enabled)
            try syncLaunchAtLoginOptionWithSystem()
            applyRuntimeSettingsSnapshot()
            lastError = nil
            lastActionMessage = persistentWriteMessage(L10n.localize("settings.message.system_settings_updated", comment: ""))
            Self.logger.info("settings_vm_set_launch_at_login_success enabled=\(systemOption(.launchAtLogin))")
        } catch {
            let actualValue = launchAtLoginManager.isEnabled
            systemOptions[.launchAtLogin] = actualValue
            try? setBool(SettingsSystemOption.launchAtLogin.rawValue, value: actualValue)
            applyRuntimeSettingsSnapshot()
            lastError = L10n.format("settings.error.launch_at_login_failed", comment: "", error.localizedDescription)
            lastActionMessage = nil
            Self.logger.error("settings_vm_set_launch_at_login_failed requested=\(enabled) actual=\(actualValue) error=\(error.localizedDescription)")
            throw error
        }
    }

    func clearLLMTraceDiagnostics() {
        LLMDiagnosticCapture.shared.clear()
        lastError = nil
        lastActionMessage = L10n.localize("settings.message.mcp_diagnostics_cleared", comment: "")
    }

    func viewLatestCrashReportSummary() {
        _ = prepareLatestCrashReportSendConfirmation()
    }

    @discardableResult
    func prepareLatestCrashReportSendConfirmation() -> Bool {
        guard let report = latestCrashReportProvider() else {
            lastError = nil
            latestCrashReportSummaryText = nil
            latestCrashReportAwaitingSendConfirmation = false
            lastActionMessage = L10n.localize("settings.message.crash_report_summary_unavailable", comment: "")
            return false
        }
        lastError = nil
        latestCrashReportSummaryText = Self.crashReportSummaryText(report.summary)
        latestCrashReportAwaitingSendConfirmation = true
        lastActionMessage = L10n.localize("settings.message.crash_report_summary_ready", comment: "")
        return true
    }

    func sendLatestCrashReport() {
        guard latestCrashReportAwaitingSendConfirmation else {
            lastError = nil
            if latestCrashReportSummaryText == nil {
                _ = prepareLatestCrashReportSendConfirmation()
            }
            lastActionMessage = L10n.localize("settings.message.crash_report_confirm_before_send", comment: "")
            return
        }
        guard let report = latestCrashReportProvider() else {
            lastError = nil
            latestCrashReportSummaryText = nil
            latestCrashReportAwaitingSendConfirmation = false
            lastActionMessage = L10n.localize("settings.message.crash_report_send_unavailable", comment: "")
            return
        }
        guard let raw = try? String(contentsOf: report.url, encoding: .utf8) else {
            lastError = nil
            latestCrashReportSummaryText = nil
            latestCrashReportAwaitingSendConfirmation = false
            lastActionMessage = L10n.localize("settings.message.crash_report_send_unavailable", comment: "")
            return
        }

        let payload = ManualCrashReportPayload(
            summary: report.summary,
            sanitizedBody: SystemCrashReportSanitizer(homeDirectory: FileManager.default.homeDirectoryForCurrentUser)
                .sanitize(raw)
        )
        let result = manualCrashReportSender(payload)
        lastError = nil
        latestCrashReportSummaryText = Self.crashReportSummaryText(report.summary)
        latestCrashReportAwaitingSendConfirmation = false
        lastActionMessage = switch result {
        case .sent:
            L10n.localize("settings.message.crash_report_send_success", comment: "")
        case .missingDSN:
            L10n.localize("settings.message.crash_report_send_missing_dsn", comment: "")
        }
    }

    func setTextInputMode(_ mode: TextInputMode) throws {
        Self.logger.debug("settings_vm_set_text_input_mode mode=\(mode.rawValue)")
        textInputMode = mode
        try setString(SettingsKey.outputTextInputMode, value: mode.rawValue)
        systemOptions[.avoidClipboard] = mode == .simulatedTyping
        try setBool(SettingsSystemOption.avoidClipboard.rawValue, value: mode == .simulatedTyping)
        lastError = nil
        lastActionMessage = persistentWriteMessage(L10n.localize("settings.message.text_input_mode_updated", comment: ""))
    }

    func setRecognitionLanguage(_ language: RecognitionLanguage) throws {
        Self.logger.debug("settings_vm_set_recognition_language language=\(language.rawValue)")
        languageManager.setLanguage(language)
        selectedRecognitionLanguage = languageManager.currentLanguage
        lastError = nil
        lastActionMessage = L10n.localize("settings.message.recognition_language_updated", comment: "")
    }

    func setInterfaceLanguage(_ language: AppLanguage) throws {
        Self.logger.debug("settings_vm_set_interface_language language=\(language.rawValue)")
        interfaceLanguageManager.setLanguage(language)
        interfaceLanguage = interfaceLanguageManager.currentLanguage
        lastError = nil
        lastActionMessage = L10n.localize(
            "settings.interface_language.restart_prompt",
            comment: "切换界面语言后提示重启"
        )
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
        lastActionMessage = L10n.localize("settings.message.local_data_folder_opened", comment: "")
    }

    func clearHistory() throws {
        Self.logger.debug("settings_vm_clear_history_start")
        let entries = try environment.historyRepository.listRecent(limit: 100_000)
        for entry in entries {
            try environment.historyRepository.softDelete(id: entry.id, deletedAt: environment.clock.now)
        }
        lastError = nil
        lastActionMessage = persistentWriteMessage(L10n.localize("settings.message.history_cleared", comment: ""))
        Self.logger.info("settings_vm_clear_history_success count=\(entries.count)")
    }

    func clearCache() throws {
        Self.logger.debug("settings_vm_clear_cache_start")
        try deleteAllLocalModels()
    }

    func deleteAllLocalModels() throws {
        Self.logger.debug("settings_vm_delete_all_local_models_start hasPaths=\(paths != nil) usesCoordinator=\(localModelDeletionCoordinator != nil)")
        guard let paths else {
            lastError = L10n.localize("settings.error.no_data_directory", comment: "")
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
        lastActionMessage = L10n.localize("settings.message.all_models_deleted", comment: "")
        Self.logger.info("settings_vm_delete_all_local_models_success")
    }

    func localModelStorageDescription() -> String {
        guard let paths else { return L10n.localize("settings.message.unknown_storage_size", comment: "") }
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
        lastActionMessage = L10n.localize("settings.message.export_data_generated", comment: "")
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
        lastActionMessage = persistentWriteMessage(L10n.localize("settings.message.settings_imported", comment: ""))
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
        lastActionMessage = persistentWriteMessage(L10n.localize("settings.message.settings_reset", comment: ""))
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
        L10n.format("settings.agent.mcp.diagnostics_format", comment: "",
            agent.mcpCommand ?? "-",
            agent.mcpArgs.isEmpty ? "-" : agent.mcpArgs.joined(separator: " "),
            agent.mcpConfigPath ?? "-",
            agent.mcpLogPath ?? "-",
            timestampText(agent.mcpSeenAt),
            timestampText(agent.mcpReportedAt),
            agent.mcpLastRequest ?? "-",
            agent.mcpLastError ?? "-",
            logText
        )
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

    private static func crashReportSummaryText(_ summary: SystemCrashReportSummary) -> String {
        let unknown = L10n.localize("settings.crash_report.summary.unknown", comment: "")
        return [
            "\(L10n.localize("settings.crash_report.summary.process", comment: "")): \(summary.processName)",
            "\(L10n.localize("settings.crash_report.summary.identifier", comment: "")): \(summary.identifier ?? unknown)",
            "\(L10n.localize("settings.crash_report.summary.version", comment: "")): \(summary.version ?? unknown)",
            "\(L10n.localize("settings.crash_report.summary.date_time", comment: "")): \(summary.dateTime ?? unknown)",
            "\(L10n.localize("settings.crash_report.summary.exception", comment: "")): \(summary.exceptionType)",
            "\(L10n.localize("settings.crash_report.summary.top_frame", comment: "")): \(summary.crashedThreadTopFrames.first ?? unknown)",
        ].joined(separator: "\n")
    }

    private func applyRuntimeSettingsSnapshot() {
        LLMDiagnosticCapture.shared.configure(
            enabled: systemOption(.llmTraceDiagnostics),
            directory: paths?.llmTraceDiagnosticsDirectory
        )
        CrashReporterService.shared.configure(
            enabled: systemOption(.crashLogs),
            configuration: .live()
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
            return L10n.format("settings.storage.message.session_only", comment: "", message)
        case .readOnly, .migrationRequired, .corrupt:
            return L10n.format("settings.storage.message.warning", comment: "", message, storageStatus.badgeText)
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
            return L10n.localize("settings.error.invalid_import_format", comment: "")
        case .invalidShortcutKeyCode:
            return L10n.localize("settings.error.shortcut_record_failed", comment: "")
        case .unsupportedShortcutKeyCode:
            return L10n.localize("settings.error.unsupported_shortcut", comment: "")
        case .unsupportedWorkflowShortcutKeyCode:
            return L10n.localize("settings.error.unsupported_workflow_shortcut", comment: "")
        case .conflictingBindings:
            return L10n.localize("settings.error.duplicate_shortcut", comment: "")
        }
    }
}

private extension HotKeyWorkflowShortcut {
    var displayName: String {
        switch self {
        case .palette:
            return L10n.localize("settings.workflow_name.palette", comment: "")
        case .clipboardImageOCR:
            return L10n.localize("settings.workflow_name.clipboard_image_ocr", comment: "")
        case .screenshotOCR:
            return L10n.localize("settings.workflow_name.screenshot_ocr", comment: "")
        case .selectionAction:
            return L10n.localize("settings.workflow_name.selection_action", comment: "")
        case .selectionTranslate:
            return L10n.localize("settings.workflow_name.selection_translate", comment: "")
        case .selectionSummarize:
            return L10n.localize("settings.workflow_name.selection_summarize", comment: "")
        case .selectionAgent:
            return L10n.localize("settings.workflow_name.selection_agent", comment: "")
        case .selectionAskAI:
            return L10n.localize("settings.workflow_name.selection_ask_ai", comment: "")
        case .cancel:
            return L10n.localize("settings.shortcuts.cancel", comment: "")
        }
    }
}

struct DecodedSettingValue<T: Decodable>: Decodable {
    let value: T
}

struct EncodedSettingValue<T: Encodable>: Encodable {
    let value: T
}
