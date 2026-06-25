import XCTest
import VoxFlowModelStore
import VoxFlowVoiceCorrection
@testable import VoxFlowApp

@MainActor
final class SettingsViewModelTests: XCTestCase {
    func testSettingsSectionsExposeVibeCoding() {
        XCTAssertTrue(SettingsSection.allCases.contains(.vibeCoding))
        XCTAssertEqual(SettingsSection.vibeCoding.title, "AI 编程")
        XCTAssertTrue(SettingsSection.allCases.contains(.selectionActions))
        XCTAssertEqual(SettingsSection.selectionActions.title, "划词动作")
        XCTAssertEqual(SettingsSection.selectionActions.systemImage, "text.cursor")
    }

    func testLoadBuildsSettingsSectionsDevicesShortcutAndPermissions() throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let viewModel = SettingsViewModel(
            environment: environment,
            shortcutManager: makeShortcutManager(),
            audioDeviceProvider: StubAudioDeviceProvider(),
            permissionProvider: StubPermissionProvider()
        )

        XCTAssertEqual(
            SettingsSection.allCases.map(\.title),
            ["通用", "AI 编程", "划词动作", "系统", "语音识别", "纠错与上下文", "朗读", "翻译", "数据与隐私"]
        )
        XCTAssertEqual(viewModel.selectedSection, .general)
        XCTAssertEqual(viewModel.inputDevices.map(\.name), ["Built-in Mic", "Studio Mic"])
        XCTAssertEqual(viewModel.selectedInputDeviceID, "built-in")
        XCTAssertEqual(viewModel.shortcutKeyCode, 54)
        XCTAssertEqual(viewModel.longPressThreshold, 0.5)
        XCTAssertEqual(viewModel.shortPressBehavior, .toggleListening)
        XCTAssertEqual(
            viewModel.selectionTranslateShortcutKeyCode,
            ShortcutManager.defaultSelectionTranslateShortcutKeyCode
        )
        XCTAssertEqual(
            viewModel.selectionSummarizeShortcutKeyCode,
            ShortcutManager.defaultSelectionSummarizeShortcutKeyCode
        )
        XCTAssertEqual(
            viewModel.selectionAgentShortcutKeyCode,
            ShortcutManager.defaultSelectionAgentShortcutKeyCode
        )
        XCTAssertEqual(viewModel.microphonePermission, .granted)
        XCTAssertEqual(viewModel.speechPermission, .denied)
        XCTAssertFalse(viewModel.screenRecordingGranted)
        XCTAssertFalse(viewModel.storageStatus.isHealthy)
        XCTAssertEqual(viewModel.storageStatus.title, "临时存储模式")
        XCTAssertEqual(viewModel.textInputMode, .automatic)
        XCTAssertEqual(
            viewModel.systemSettingsURL(for: .microphone)?.absoluteString,
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        )
        XCTAssertEqual(
            viewModel.systemSettingsURL(for: .screenRecording)?.absoluteString,
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        )
    }

    func testTextInputModeMapsLegacyAvoidClipboardSetting() throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        try environment.settingsRepository.set(
            SettingsSystemOption.avoidClipboard.rawValue,
            jsonValue: #"{"value":true}"#
        )

        let viewModel = SettingsViewModel(
            environment: environment,
            shortcutManager: makeShortcutManager(),
            audioDeviceProvider: StubAudioDeviceProvider(),
            permissionProvider: StubPermissionProvider()
        )

        XCTAssertEqual(viewModel.textInputMode, .simulatedTyping)
    }

    func testVoiceCorrectionSettingsAreLoadedAndPersisted() throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let viewModel = SettingsViewModel(
            environment: environment,
            shortcutManager: makeShortcutManager(),
            audioDeviceProvider: StubAudioDeviceProvider(),
            permissionProvider: StubPermissionProvider()
        )

        XCTAssertTrue(viewModel.voiceCorrectionEnabled)
        XCTAssertTrue(viewModel.voiceCorrectionAutoLearningEnabled)
        XCTAssertTrue(viewModel.voiceCorrectionAutoLearningAppliesImmediately)
        XCTAssertFalse(viewModel.voiceCorrectionShadowMode)

        try viewModel.setVoiceCorrectionEnabled(false)
        try viewModel.setVoiceCorrectionAutoLearningEnabled(false)
        try viewModel.setVoiceCorrectionAutoLearningAppliesImmediately(true)
        try viewModel.setVoiceCorrectionShadowMode(true)

        XCTAssertFalse(viewModel.voiceCorrectionEnabled)
        XCTAssertFalse(viewModel.voiceCorrectionAutoLearningEnabled)
        XCTAssertTrue(viewModel.voiceCorrectionAutoLearningAppliesImmediately)
        XCTAssertTrue(viewModel.voiceCorrectionShadowMode)
        XCTAssertEqual(
            try environment.settingsRepository.value(forKey: VoiceCorrectionSettingsKey.shadowMode.rawValue),
            #"{"value":true}"#
        )
    }

    func testExportAndImportIncludesVoiceCorrectionDictionary() throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let target = CorrectionTargetTerm(
            text: "Qwen",
            scope: .application(bundleIdentifier: "com.cursor.Cursor"),
            lifecycle: .active,
            source: .automaticLearning
        )
        try environment.correctionTargetRepository.save(target)
        try environment.correctionRuleRepository.save(CorrectionRule(
            targetID: target.id,
            original: "q 问",
            replacement: "Qwen",
            matchPolicy: .boundary,
            scope: .application(bundleIdentifier: "com.cursor.Cursor"),
            lifecycle: .active,
            source: .automaticLearning,
            confidence: 0.9,
            observedCount: 1,
            providerID: "apple_speech",
            modelID: nil,
            language: "zh-CN"
        ))
        let viewModel = SettingsViewModel(
            environment: environment,
            shortcutManager: makeShortcutManager(),
            audioDeviceProvider: StubAudioDeviceProvider(),
            permissionProvider: StubPermissionProvider()
        )

        let exported = try viewModel.exportDataJSON()
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(exported.utf8)) as? [String: Any])
        let voiceCorrection = try XCTUnwrap(payload["voiceCorrection"] as? [String: Any])
        XCTAssertEqual((voiceCorrection["targets"] as? [[String: Any]])?.first?["text"] as? String, "Qwen")
        XCTAssertEqual((voiceCorrection["rules"] as? [[String: Any]])?.first?["original"] as? String, "q 问")

        let importedEnvironment = AppEnvironment(container: try DependencyContainer.inMemory())
        let importViewModel = SettingsViewModel(
            environment: importedEnvironment,
            shortcutManager: makeShortcutManager(),
            audioDeviceProvider: StubAudioDeviceProvider(),
            permissionProvider: StubPermissionProvider()
        )

        try importViewModel.importSettingsJSON(exported)

        let importedRule = try XCTUnwrap(try importedEnvironment.correctionRuleRepository.list().first)
        XCTAssertEqual(importedRule.original, "q 问")
        XCTAssertEqual(importedRule.replacement, "Qwen")
        XCTAssertEqual(importedRule.scope, .application(bundleIdentifier: "com.cursor.Cursor"))
        XCTAssertEqual(importedRule.providerID, "apple_speech")
        XCTAssertEqual(importedRule.language, "zh-CN")
        let importedTarget = try XCTUnwrap(try importedEnvironment.correctionTargetRepository.list().first)
        XCTAssertEqual(importedTarget.text, "Qwen")
        XCTAssertEqual(importedRule.targetID, importedTarget.id)
    }

    func testStorageStatusExplainsVolatileLaunchFallback() throws {
        let environment = AppEnvironment(
            container: try DependencyContainer.inMemory(
                storageHealth: .volatile(reason: "Persistent storage failed to initialize: database locked")
            )
        )

        let viewModel = SettingsViewModel(
            environment: environment,
            shortcutManager: makeShortcutManager(),
            audioDeviceProvider: StubAudioDeviceProvider(),
            permissionProvider: StubPermissionProvider()
        )

        XCTAssertEqual(viewModel.storageStatus.title, "临时存储模式")
        XCTAssertFalse(viewModel.storageStatus.isHealthy)
        XCTAssertTrue(viewModel.storageStatus.message.contains("database locked"))
        XCTAssertTrue(viewModel.storageStatus.message.contains("重启后可能丢失"))
        XCTAssertEqual(viewModel.storageStatus.badgeText, "临时")
    }

    func testStorageStatusExplainsUnavailablePersistentStorage() throws {
        let environment = AppEnvironment(
            container: try DependencyContainer.inMemory(
                storageHealth: .unavailable(reason: "database locked")
            )
        )

        let viewModel = SettingsViewModel(
            environment: environment,
            shortcutManager: makeShortcutManager(),
            audioDeviceProvider: StubAudioDeviceProvider(),
            permissionProvider: StubPermissionProvider()
        )

        XCTAssertEqual(viewModel.storageStatus.title, "持久化存储不可用")
        XCTAssertFalse(viewModel.storageStatus.isHealthy)
        XCTAssertEqual(viewModel.storageStatus.badgeText, "不可用")
        XCTAssertTrue(viewModel.storageStatus.message.contains("database locked"))
        XCTAssertTrue(viewModel.storageStatus.message.contains("重启后可能丢失"))
    }

    func testStorageStatusDistinguishesDegradedPersistentStates() {
        let databaseURL = URL(fileURLWithPath: "/tmp/VoxFlow/voxflow.sqlite")

        let readOnly = SettingsStorageStatus(
            storageHealth: .readOnly(databaseURL: databaseURL, reason: "Permission denied")
        )
        let migrationRequired = SettingsStorageStatus(
            storageHealth: .migrationRequired(databaseURL: databaseURL, reason: "Schema too old")
        )
        let corrupt = SettingsStorageStatus(
            storageHealth: .corrupt(databaseURL: databaseURL, reason: "SQLite not a database")
        )

        XCTAssertEqual(readOnly.title, "数据目录只读")
        XCTAssertEqual(readOnly.badgeText, "只读")
        XCTAssertTrue(readOnly.message.contains("无法可靠写入"))
        XCTAssertTrue(StorageHealthState.readOnly(databaseURL: databaseURL, reason: "Permission denied").isPersistent)
        XCTAssertEqual(migrationRequired.title, "数据库需要迁移")
        XCTAssertEqual(migrationRequired.badgeText, "需迁移")
        XCTAssertTrue(migrationRequired.message.contains("迁移完成前"))
        XCTAssertTrue(StorageHealthState.migrationRequired(databaseURL: databaseURL, reason: "Schema too old").isPersistent)
        XCTAssertEqual(corrupt.title, "数据库可能损坏")
        XCTAssertEqual(corrupt.badgeText, "损坏")
        XCTAssertTrue(corrupt.message.contains("先导出或备份"))
        XCTAssertTrue(StorageHealthState.corrupt(databaseURL: databaseURL, reason: "SQLite not a database").isPersistent)
    }

    func testTextInputModeCanBePersistedExplicitly() throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let viewModel = SettingsViewModel(
            environment: environment,
            shortcutManager: makeShortcutManager(),
            audioDeviceProvider: StubAudioDeviceProvider(),
            permissionProvider: StubPermissionProvider()
        )

        try viewModel.setTextInputMode(.fastPaste)

        XCTAssertEqual(viewModel.textInputMode, .fastPaste)
        XCTAssertEqual(viewModel.lastActionMessage, "已更新文本输入模式（仅当前会话生效，重启后可能丢失）")
        XCTAssertEqual(
            try environment.settingsRepository.value(forKey: SettingsKey.outputTextInputMode),
            #"{"value":"fastPaste"}"#
        )
    }

    func testClipboardImageOCRSettingDefaultsOnAndCanBeDisabled() throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let viewModel = SettingsViewModel(
            environment: environment,
            shortcutManager: makeShortcutManager(),
            audioDeviceProvider: StubAudioDeviceProvider(),
            permissionProvider: StubPermissionProvider()
        )

        XCTAssertTrue(viewModel.systemOption(.clipboardImageOCR))

        try viewModel.setSystemOption(.clipboardImageOCR, enabled: false)

        XCTAssertFalse(viewModel.systemOption(.clipboardImageOCR))
        XCTAssertEqual(
            try environment.settingsRepository.value(forKey: SettingsSystemOption.clipboardImageOCR.rawValue),
            #"{"value":false}"#
        )
    }

    func testRecognitionLanguageSelectionUsesLanguageManagerAndStaysInSync() throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let suiteName = "test.SettingsLanguage.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let languageManager = LanguageManager(defaults: defaults)
        let viewModel = SettingsViewModel(
            environment: environment,
            shortcutManager: makeShortcutManager(),
            audioDeviceProvider: StubAudioDeviceProvider(),
            permissionProvider: StubPermissionProvider(),
            languageManager: languageManager
        )

        XCTAssertEqual(
            viewModel.recognitionLanguages.map(\.rawValue),
            ["zh-CN", "zh-TW", "en-US", "ja-JP", "ko-KR"]
        )
        XCTAssertEqual(viewModel.selectedRecognitionLanguage, .simplifiedChinese)

        try viewModel.setRecognitionLanguage(.korean)

        XCTAssertEqual(languageManager.currentLanguage, .korean)
        XCTAssertEqual(defaults.string(forKey: "VoxFlow_SelectedLanguage"), "ko-KR")
        XCTAssertEqual(viewModel.selectedRecognitionLanguage, .korean)
        XCTAssertEqual(viewModel.lastActionMessage, "已更新识别语言")

        languageManager.setLanguage(.japanese)

        XCTAssertEqual(viewModel.selectedRecognitionLanguage, .japanese)
    }

    func testVoiceEnhancementIsDisabledForFreshSettings() throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())

        let viewModel = SettingsViewModel(
            environment: environment,
            shortcutManager: makeShortcutManager(),
            audioDeviceProvider: StubAudioDeviceProvider(),
            permissionProvider: StubPermissionProvider()
        )

        XCTAssertFalse(viewModel.voiceEnhancementEnabled)
    }

    func testAudioDeviceProviderAddsSystemBuiltInAndHidesCoreAudioDefaultName() {
        let devices = SystemAudioInputDeviceProvider.deviceList(
            from: [
                (id: "CADefaultDeviceAggregate-64856-0", name: "CADefaultDeviceAggregate-64856-0"),
                (id: "studio", name: "Studio Mic"),
            ]
        )

        XCTAssertEqual(devices.map(\.id), ["system-default", "studio"])
        XCTAssertEqual(devices.map(\.name), ["系统自带", "Studio Mic"])
        XCTAssertEqual(devices.first?.isDefault, true)
        XCTAssertEqual(devices.last?.isDefault, false)
    }

    func testLoadMigratesSavedCoreAudioDefaultAggregateToSystemBuiltIn() throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        try environment.settingsRepository.set(
            SettingsKey.audioInputDeviceID,
            jsonValue: #"{"value":"CADefaultDeviceAggregate-64856-0"}"#
        )

        let viewModel = SettingsViewModel(
            environment: environment,
            shortcutManager: makeShortcutManager(),
            audioDeviceProvider: StubAudioDeviceProvider(),
            permissionProvider: StubPermissionProvider()
        )

        XCTAssertEqual(viewModel.selectedInputDeviceID, "system-default")
    }

    func testUpdatesPersistAudioShortcutGeneralAndAnalyticsSettings() throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let shortcutManager = makeShortcutManager()
        let viewModel = SettingsViewModel(
            environment: environment,
            shortcutManager: shortcutManager,
            audioDeviceProvider: StubAudioDeviceProvider(),
            permissionProvider: StubPermissionProvider()
        )

        try viewModel.selectInputDevice(id: "studio")
        try viewModel.updateShortcut(keyCode: 55, longPressThreshold: 0.8, shortPressBehavior: .none)
        try viewModel.updateAudioOptions(soundFeedback: false, voiceEnhancement: false)
        try viewModel.updatePerformanceOptions(muteWhileRecording: true, performanceOptimization: true)
        try viewModel.setAnalyticsEnabled(true)

        XCTAssertEqual(shortcutManager.shortcutKeyCode, 55)
        XCTAssertEqual(shortcutManager.longPressThreshold, 0.8)
        XCTAssertEqual(shortcutManager.shortPressBehavior, .none)
        XCTAssertEqual(try environment.settingsRepository.value(forKey: SettingsKey.audioInputDeviceID), #"{"value":"studio"}"#)
        XCTAssertEqual(try environment.settingsRepository.value(forKey: SettingsKey.audioSoundFeedbackEnabled), #"{"value":false}"#)
        XCTAssertEqual(try environment.settingsRepository.value(forKey: SettingsKey.audioVoiceEnhancementEnabled), #"{"value":false}"#)
        XCTAssertEqual(try environment.settingsRepository.value(forKey: SettingsKey.audioMuteWhileRecordingEnabled), #"{"value":true}"#)
        XCTAssertEqual(try environment.settingsRepository.value(forKey: SettingsKey.performanceOptimizationEnabled), #"{"value":true}"#)
        XCTAssertEqual(try environment.settingsRepository.value(forKey: SettingsKey.analyticsEnabled), #"{"value":true}"#)
        XCTAssertEqual(viewModel.lastActionMessage, "已更新分析设置（仅当前会话生效，重启后可能丢失）")
    }

    func testMiddleMouseRecordingSettingLoadsPersistsAndResets() throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let shortcutManager = makeShortcutManager()
        let viewModel = SettingsViewModel(
            environment: environment,
            shortcutManager: shortcutManager,
            audioDeviceProvider: StubAudioDeviceProvider(),
            permissionProvider: StubPermissionProvider()
        )

        XCTAssertFalse(viewModel.middleMouseRecordingEnabled)

        try viewModel.setMiddleMouseRecordingEnabled(true)

        XCTAssertTrue(viewModel.middleMouseRecordingEnabled)
        XCTAssertTrue(shortcutManager.middleMouseRecordingEnabled)
        XCTAssertEqual(viewModel.lastActionMessage, "已启用鼠标中键录音")

        try viewModel.resetSettings()

        XCTAssertFalse(viewModel.middleMouseRecordingEnabled)
        XCTAssertFalse(shortcutManager.middleMouseRecordingEnabled)
    }

    func testUpdatesDirectSelectionWorkflowShortcuts() throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let shortcutManager = makeShortcutManager()
        let viewModel = SettingsViewModel(
            environment: environment,
            shortcutManager: shortcutManager,
            audioDeviceProvider: StubAudioDeviceProvider(),
            permissionProvider: StubPermissionProvider()
        )
        let customShortcut = ShortcutManager.encodeShortcut(
            keyCode: 0x23,
            modifierMask: ShortcutManager.commandModifierMask | ShortcutManager.optionModifierMask
        )

        try viewModel.updateWorkflowShortcut(.selectionTranslate, keyCode: customShortcut)

        XCTAssertEqual(viewModel.selectionTranslateShortcutKeyCode, customShortcut)
        XCTAssertEqual(shortcutManager.shortcutKeyCode(for: .selectionTranslate), customShortcut)

        try viewModel.updateWorkflowShortcut(.selectionTranslate, keyCode: nil)

        XCTAssertNil(viewModel.selectionTranslateShortcutKeyCode)
        XCTAssertNil(shortcutManager.shortcutKeyCode(for: .selectionTranslate))
    }

    func testClearHistoryClearCacheExportImportAndResetSettings() throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceInputSettingsTests-\(UUID().uuidString)")
        let paths = ApplicationSupportPaths(applicationSupportDirectory: tempRoot)
        try paths.ensureDirectories()
        let cacheFile = paths.modelsDirectory.appendingPathComponent("cache.bin")
        XCTAssertTrue(FileManager.default.createFile(atPath: cacheFile.path, contents: Data("cache".utf8)))
        addTeardownBlock {
            try? FileManager.default.removeItem(at: tempRoot)
        }
        let now = environment.clock.now
        try environment.historyRepository.save(
            DictationHistoryEntry(
                id: "history",
                rawText: "hello",
                finalText: "hello",
                language: "en-US",
                asrProviderID: nil,
                llmProviderID: nil,
                styleID: nil,
                durationMS: 100,
                charCount: 5,
                cpm: 120,
                targetAppBundleID: nil,
                targetAppName: nil,
                processingWarningsJSON: nil,
                createdAt: now,
                updatedAt: now,
                deletedAt: nil
            )
        )
        let viewModel = SettingsViewModel(
            environment: environment,
            shortcutManager: makeShortcutManager(),
            audioDeviceProvider: StubAudioDeviceProvider(),
            permissionProvider: StubPermissionProvider(),
            paths: paths
        )

        let exported = try viewModel.exportDataJSON()
        try viewModel.clearHistory()
        try viewModel.clearCache()
        try viewModel.importSettingsJSON(#"{"settings":{"custom.setting":"{\"value\":42}"}}"#)
        try viewModel.resetSettings()

        XCTAssertTrue(exported.contains("hello"))
        XCTAssertEqual(try environment.historyRepository.listRecent(limit: 10), [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: cacheFile.path))
        XCTAssertNil(try environment.settingsRepository.value(forKey: "custom.setting"))
        XCTAssertEqual(viewModel.shortcutKeyCode, 54)
        XCTAssertEqual(viewModel.lastActionMessage, "已重置设置（仅当前会话生效，重启后可能丢失）")
    }

    func testImportDisablesLLMTraceDiagnosticsRuntimeState() throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceInputSettingsTests-\(UUID().uuidString)")
        let paths = ApplicationSupportPaths(applicationSupportDirectory: tempRoot)
        addTeardownBlock {
            LLMDiagnosticCapture.shared.configure(
                enabled: false,
                directory: paths.llmTraceDiagnosticsDirectory
            )
            try? FileManager.default.removeItem(at: tempRoot)
        }
        let viewModel = SettingsViewModel(
            environment: environment,
            shortcutManager: makeShortcutManager(),
            audioDeviceProvider: StubAudioDeviceProvider(),
            permissionProvider: StubPermissionProvider(),
            paths: paths
        )

        try viewModel.setSystemOption(.llmTraceDiagnostics, enabled: true)
        LLMDiagnosticCapture.shared.capture(taskID: "before-import", trace: diagnosticTrace())
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.llmTraceDiagnosticsDirectory.path))

        try viewModel.importSettingsJSON(
            #"{"settings":{"settings.privacy.llmTraceDiagnostics":"{\"value\":false}"}}"#
        )
        LLMDiagnosticCapture.shared.capture(taskID: "after-import", trace: diagnosticTrace())

        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.llmTraceDiagnosticsDirectory.path))
        XCTAssertFalse(viewModel.systemOption(.llmTraceDiagnostics))
    }

    func testResetSettingsDisablesLLMTraceDiagnosticsRuntimeState() throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceInputSettingsTests-\(UUID().uuidString)")
        let paths = ApplicationSupportPaths(applicationSupportDirectory: tempRoot)
        let shortcutManager = makeShortcutManager()
        let asrSuiteName = "test.SettingsViewModel.ASR.\(UUID().uuidString)"
        let asrDefaults = UserDefaults(suiteName: asrSuiteName)!
        asrDefaults.removePersistentDomain(forName: asrSuiteName)
        let asrManager = ASRManager(defaults: asrDefaults)
        addTeardownBlock {
            LLMDiagnosticCapture.shared.configure(
                enabled: false,
                directory: paths.llmTraceDiagnosticsDirectory
            )
            asrDefaults.removePersistentDomain(forName: asrSuiteName)
            try? FileManager.default.removeItem(at: tempRoot)
        }
        let viewModel = SettingsViewModel(
            environment: environment,
            shortcutManager: shortcutManager,
            audioDeviceProvider: StubAudioDeviceProvider(),
            permissionProvider: StubPermissionProvider(),
            asrSettingsResetter: asrManager,
            paths: paths
        )

        try viewModel.setSystemOption(.llmTraceDiagnostics, enabled: true)
        try viewModel.updateShortcut(keyCode: 55, longPressThreshold: 0.8, shortPressBehavior: .none)
        try viewModel.updateActionShortcut(action: .agentCompose, keyCode: nil)
        try viewModel.updateActionShortcut(action: .agentDispatch, keyCode: nil)
        asrManager.selectedEngineType = .whisper
        asrManager.qwen3ModelSize = .size1_7B
        asrManager.qwen3ModelPath = "/tmp/custom-qwen"
        asrManager.funASRPrecision = .fp32
        asrManager.whisperVariant = .largeV3
        asrManager.groqBaseURL = "https://example.test/groq"
        asrManager.groqModel = "custom-groq-model"
        asrManager.tencentRealtimeEngineModelType = "16k_zh_video"
        asrManager.aliyunDashScopeModel = "custom-aliyun-model"
        LLMDiagnosticCapture.shared.capture(taskID: "before-reset", trace: diagnosticTrace())
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.llmTraceDiagnosticsDirectory.path))

        try viewModel.resetSettings()
        LLMDiagnosticCapture.shared.capture(taskID: "after-reset", trace: diagnosticTrace())

        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.llmTraceDiagnosticsDirectory.path))
        XCTAssertFalse(viewModel.systemOption(.llmTraceDiagnostics))
        XCTAssertEqual(shortcutManager.shortcutKeyCode, ShortcutManager.defaultShortcutKeyCode)
        XCTAssertEqual(shortcutManager.longPressThreshold, ShortcutManager.defaultLongPressThreshold)
        XCTAssertEqual(shortcutManager.shortPressBehavior, .toggleListening)
        XCTAssertEqual(shortcutManager.shortcutKeyCode(for: .agentCompose), ShortcutManager.defaultAgentComposeShortcutKeyCode)
        XCTAssertNil(shortcutManager.shortcutKeyCode(for: .agentDispatch))
        XCTAssertEqual(asrManager.selectedEngineType, .apple)
        XCTAssertEqual(asrManager.qwen3ModelSize, .size0_6B)
        XCTAssertNil(asrManager.qwen3ModelPath)
        XCTAssertEqual(asrManager.funASRPrecision, .int8)
        XCTAssertEqual(asrManager.whisperVariant, .turbo)
        XCTAssertEqual(asrManager.groqBaseURL, "https://api.groq.com/openai/v1")
        XCTAssertEqual(asrManager.groqModel, "whisper-large-v3-turbo")
        XCTAssertEqual(asrManager.tencentRealtimeEngineModelType, "16k_zh")
        XCTAssertEqual(asrManager.aliyunDashScopeModel, "fun-asr-realtime")
    }

    func testDeleteAllLocalModelsClearsFilesStateAndFallsBackToApple() throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceInputSettingsTests-\(UUID().uuidString)")
        let paths = ApplicationSupportPaths(applicationSupportDirectory: tempRoot)
        try paths.ensureDirectories()
        let stateRepository = FileModelInstallationStateRepository(
            fileURL: paths.modelsDirectory.appendingPathComponent("installation-states.json")
        )
        let asrManager = ASRManager(
            defaults: isolatedDefaults(name: "delete-all-local-models"),
            modelInstallationRepository: stateRepository
        )
        let funASRRoot = paths.modelsDirectory
            .appendingPathComponent("funasr-nano", isDirectory: true)
            .appendingPathComponent("int8", isDirectory: true)
        try FileManager.default.createDirectory(at: funASRRoot, withIntermediateDirectories: true)
        try Data("model".utf8).write(to: funASRRoot.appendingPathComponent("model.bin"))
        asrManager.markFunASRModelReady(at: funASRRoot.path, precision: .int8)
        asrManager.selectedEngineType = .funASR
        let viewModel = SettingsViewModel(
            environment: environment,
            shortcutManager: makeShortcutManager(),
            audioDeviceProvider: StubAudioDeviceProvider(),
            permissionProvider: StubPermissionProvider(),
            localModelDeletionCoordinator: asrManager,
            paths: paths
        )
        addTeardownBlock { try? FileManager.default.removeItem(at: tempRoot) }

        try viewModel.deleteAllLocalModels()

        XCTAssertFalse(FileManager.default.fileExists(atPath: funASRRoot.path))
        XCTAssertEqual(asrManager.funASRModelInstallationState(for: .int8), .notInstalled)
        XCTAssertEqual(asrManager.selectedEngineType, .apple)
        XCTAssertEqual(viewModel.lastActionMessage, "已删除全部本地模型")
    }

    func testDeleteAllLocalModelsRejectsBusyModelOperations() throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceInputSettingsTests-\(UUID().uuidString)")
        let paths = ApplicationSupportPaths(applicationSupportDirectory: tempRoot)
        try paths.ensureDirectories()
        let stateRepository = FileModelInstallationStateRepository(
            fileURL: paths.modelsDirectory.appendingPathComponent("installation-states.json")
        )
        let asrManager = ASRManager(
            defaults: isolatedDefaults(name: "delete-all-local-models-busy"),
            modelInstallationRepository: stateRepository
        )
        let funASRRoot = paths.modelsDirectory
            .appendingPathComponent("funasr-nano", isDirectory: true)
            .appendingPathComponent("int8", isDirectory: true)
        try FileManager.default.createDirectory(at: funASRRoot, withIntermediateDirectories: true)
        try Data("model".utf8).write(to: funASRRoot.appendingPathComponent("model.bin"))
        asrManager.markFunASRModelReady(at: funASRRoot.path, precision: .int8)
        asrManager.markModelDeleting(for: .funASR)
        let viewModel = SettingsViewModel(
            environment: environment,
            shortcutManager: makeShortcutManager(),
            audioDeviceProvider: StubAudioDeviceProvider(),
            permissionProvider: StubPermissionProvider(),
            localModelDeletionCoordinator: asrManager,
            paths: paths
        )
        addTeardownBlock { try? FileManager.default.removeItem(at: tempRoot) }

        XCTAssertThrowsError(try viewModel.deleteAllLocalModels()) { error in
            XCTAssertEqual(error as? LocalModelDeletionError, .modelOperationInProgress)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: funASRRoot.path))
    }

    func testPersistentWriteWarningMentionsDegradedStorageState() throws {
        let environment = AppEnvironment(
            container: try DependencyContainer.inMemory(
                storageHealth: .corrupt(
                    databaseURL: URL(fileURLWithPath: "/tmp/VoxFlow/voxflow.sqlite"),
                    reason: "SQLite not a database"
                )
            )
        )
        let viewModel = SettingsViewModel(
            environment: environment,
            shortcutManager: makeShortcutManager(),
            audioDeviceProvider: StubAudioDeviceProvider(),
            permissionProvider: StubPermissionProvider()
        )

        try viewModel.setAnalyticsEnabled(true)

        XCTAssertEqual(viewModel.lastActionMessage, "已更新分析设置（存储状态：损坏，不保证已持久保存）")
    }

    func testShortcutKeyCodeTextIsValidatedAndApplied() throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let shortcutManager = makeShortcutManager()
        let viewModel = SettingsViewModel(
            environment: environment,
            shortcutManager: shortcutManager,
            audioDeviceProvider: StubAudioDeviceProvider(),
            permissionProvider: StubPermissionProvider()
        )

        viewModel.applyShortcutKeyCode("55")
        XCTAssertEqual(shortcutManager.shortcutKeyCode, 55)
        XCTAssertEqual(viewModel.lastActionMessage, "已应用快捷键")

        viewModel.applyShortcutKeyCode("invalid")
        XCTAssertEqual(viewModel.lastError, "快捷键录制失败，请按下一个有效按键。")
    }

    func testVoiceShortcutSupportsModifierCombinationsAndRejectsBareNonModifierKeys() throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let shortcutManager = makeShortcutManager()
        let viewModel = SettingsViewModel(
            environment: environment,
            shortcutManager: shortcutManager,
            audioDeviceProvider: StubAudioDeviceProvider(),
            permissionProvider: StubPermissionProvider()
        )

        let commandShiftY = ShortcutManager.encodeShortcut(
            keyCode: 0x10,
            modifierMask: ShortcutManager.commandModifierMask | ShortcutManager.shiftModifierMask
        )
        try viewModel.updateActionShortcut(action: .dictation, keyCode: commandShiftY)
        XCTAssertEqual(shortcutManager.shortcutKeyCode, commandShiftY)

        XCTAssertThrowsError(
            try viewModel.updateActionShortcut(action: .dictation, keyCode: 0x09)
        ) { error in
            XCTAssertEqual(
                error.localizedDescription,
                "语音快捷键支持单独 Command、Option、Control、Shift，或带这些修饰键的组合键。"
            )
        }
        XCTAssertEqual(shortcutManager.shortcutKeyCode, commandShiftY)
    }

    func testConflictingActionShortcutDoesNotPersistFailedBinding() throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let shortcutManager = makeShortcutManager()
        let viewModel = SettingsViewModel(
            environment: environment,
            shortcutManager: shortcutManager,
            audioDeviceProvider: StubAudioDeviceProvider(),
            permissionProvider: StubPermissionProvider()
        )

        XCTAssertThrowsError(
            try viewModel.updateActionShortcut(action: .agentCompose, keyCode: 54)
        ) { error in
            XCTAssertEqual(error.localizedDescription, "两个操作不能使用相同的快捷键，请修改其中一个。")
        }
        XCTAssertNil(shortcutManager.agentComposeShortcutKeyCode)
    }

    func testOCRWorkflowShortcutDefaultsCanBeChangedAndClearedFromSettings() throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let shortcutManager = makeShortcutManager()
        let viewModel = SettingsViewModel(
            environment: environment,
            shortcutManager: shortcutManager,
            audioDeviceProvider: StubAudioDeviceProvider(),
            permissionProvider: StubPermissionProvider()
        )

        viewModel.load()
        XCTAssertEqual(
            viewModel.paletteShortcutKeyCode,
            ShortcutManager.defaultPaletteShortcutKeyCode
        )
        XCTAssertEqual(
            viewModel.clipboardImageOCRShortcutKeyCode,
            ShortcutManager.defaultClipboardImageOCRShortcutKeyCode
        )
        XCTAssertEqual(
            viewModel.screenshotOCRShortcutKeyCode,
            ShortcutManager.defaultScreenshotOCRShortcutKeyCode
        )

        let customShortcut = ShortcutManager.encodeShortcut(
            keyCode: 0x0B,
            modifierMask: ShortcutManager.optionModifierMask | ShortcutManager.shiftModifierMask
        )
        try viewModel.updateWorkflowShortcut(.clipboardImageOCR, keyCode: customShortcut)

        XCTAssertEqual(viewModel.clipboardImageOCRShortcutKeyCode, customShortcut)
        XCTAssertEqual(shortcutManager.shortcutKeyCode(for: .clipboardImageOCR), customShortcut)
        XCTAssertEqual(viewModel.lastActionMessage, "已更新剪贴板图片识别 快捷键")

        try viewModel.updateWorkflowShortcut(.clipboardImageOCR, keyCode: nil)

        XCTAssertNil(viewModel.clipboardImageOCRShortcutKeyCode)
        XCTAssertNil(shortcutManager.shortcutKeyCode(for: .clipboardImageOCR))
    }

    func testPaletteWorkflowShortcutCanBeChangedAndClearedFromSettings() throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let shortcutManager = makeShortcutManager()
        let viewModel = SettingsViewModel(
            environment: environment,
            shortcutManager: shortcutManager,
            audioDeviceProvider: StubAudioDeviceProvider(),
            permissionProvider: StubPermissionProvider()
        )

        viewModel.load()

        let customShortcut = ShortcutManager.encodeShortcut(
            keyCode: 0x0F,
            modifierMask: ShortcutManager.optionModifierMask | ShortcutManager.controlModifierMask
        )
        try viewModel.updateWorkflowShortcut(.palette, keyCode: customShortcut)

        XCTAssertEqual(viewModel.paletteShortcutKeyCode, customShortcut)
        XCTAssertEqual(shortcutManager.shortcutKeyCode(for: .palette), customShortcut)
        XCTAssertEqual(viewModel.lastActionMessage, "已更新启动台 快捷键")

        try viewModel.updateWorkflowShortcut(.palette, keyCode: nil)

        XCTAssertNil(viewModel.paletteShortcutKeyCode)
        XCTAssertNil(shortcutManager.shortcutKeyCode(for: .palette))
    }

    func testOCRWorkflowShortcutRejectsConflictsWithVoiceShortcuts() throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let shortcutManager = makeShortcutManager()
        let viewModel = SettingsViewModel(
            environment: environment,
            shortcutManager: shortcutManager,
            audioDeviceProvider: StubAudioDeviceProvider(),
            permissionProvider: StubPermissionProvider()
        )

        viewModel.load()
        let commandShiftY = ShortcutManager.encodeShortcut(
            keyCode: 0x10,
            modifierMask: ShortcutManager.commandModifierMask | ShortcutManager.shiftModifierMask
        )
        try viewModel.updateActionShortcut(action: .dictation, keyCode: commandShiftY)

        XCTAssertThrowsError(
            try viewModel.updateWorkflowShortcut(.clipboardImageOCR, keyCode: commandShiftY)
        ) { error in
            XCTAssertEqual(error as? SettingsViewModelError, .conflictingBindings)
        }
        XCTAssertEqual(
            shortcutManager.shortcutKeyCode(for: .clipboardImageOCR),
            ShortcutManager.defaultClipboardImageOCRShortcutKeyCode
        )
    }

    func testScreenshotOCRShortcutCannotTakeClipboardOCRDefaultShortcutAfterClipboardShortcutIsCleared() throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let shortcutManager = makeShortcutManager()
        let viewModel = SettingsViewModel(
            environment: environment,
            shortcutManager: shortcutManager,
            audioDeviceProvider: StubAudioDeviceProvider(),
            permissionProvider: StubPermissionProvider()
        )

        viewModel.load()
        try viewModel.updateWorkflowShortcut(.clipboardImageOCR, keyCode: nil)

        XCTAssertThrowsError(
            try viewModel.updateWorkflowShortcut(
                .screenshotOCR,
                keyCode: ShortcutManager.defaultClipboardImageOCRShortcutKeyCode
            )
        ) { error in
            XCTAssertEqual(error as? SettingsViewModelError, .conflictingBindings)
        }
        XCTAssertEqual(
            shortcutManager.shortcutKeyCode(for: .screenshotOCR),
            ShortcutManager.defaultScreenshotOCRShortcutKeyCode
        )
    }

    func testVoiceShortcutRejectsConflictsWithConfiguredOCRShortcuts() throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let shortcutManager = makeShortcutManager()
        let viewModel = SettingsViewModel(
            environment: environment,
            shortcutManager: shortcutManager,
            audioDeviceProvider: StubAudioDeviceProvider(),
            permissionProvider: StubPermissionProvider()
        )

        viewModel.load()

        XCTAssertThrowsError(
            try viewModel.updateActionShortcut(
                action: .dictation,
                keyCode: ShortcutManager.defaultScreenshotOCRShortcutKeyCode
            )
        ) { error in
            XCTAssertEqual(error as? SettingsViewModelError, .conflictingBindings)
        }
    }

    func testAgentDispatchEnabledPersistsAsAFeatureToggle() throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let viewModel = SettingsViewModel(
            environment: environment,
            shortcutManager: makeShortcutManager(),
            audioDeviceProvider: StubAudioDeviceProvider(),
            permissionProvider: StubPermissionProvider()
        )

        XCTAssertFalse(viewModel.agentDispatchEnabled)

        try viewModel.setAgentDispatchEnabled(true)

        XCTAssertTrue(viewModel.agentDispatchEnabled)
        XCTAssertEqual(viewModel.lastActionMessage, "已启用AI 编程")
        XCTAssertEqual(
            try environment.settingsRepository.value(forKey: SettingsKey.agentDispatchEnabled),
            #"{"value":true}"#
        )
    }

    func testLaunchAtLoginLoadsActualSystemStatusInsteadOfStoredPreference() throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        try environment.settingsRepository.set(
            SettingsSystemOption.launchAtLogin.rawValue,
            jsonValue: #"{"value":false}"#
        )
        let launchAtLoginManager = FakeLaunchAtLoginManager(isEnabled: true)

        let viewModel = SettingsViewModel(
            environment: environment,
            shortcutManager: makeShortcutManager(),
            audioDeviceProvider: StubAudioDeviceProvider(),
            permissionProvider: StubPermissionProvider(),
            launchAtLoginManager: launchAtLoginManager
        )

        XCTAssertTrue(viewModel.systemOption(.launchAtLogin))
        XCTAssertEqual(
            try environment.settingsRepository.value(forKey: SettingsSystemOption.launchAtLogin.rawValue),
            #"{"value":true}"#
        )
    }

    func testLaunchAtLoginToggleUpdatesSystemLoginItemAndPersistsActualState() throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let launchAtLoginManager = FakeLaunchAtLoginManager(isEnabled: false)
        let viewModel = SettingsViewModel(
            environment: environment,
            shortcutManager: makeShortcutManager(),
            audioDeviceProvider: StubAudioDeviceProvider(),
            permissionProvider: StubPermissionProvider(),
            launchAtLoginManager: launchAtLoginManager
        )

        try viewModel.setSystemOption(.launchAtLogin, enabled: true)

        XCTAssertEqual(launchAtLoginManager.requestedValues, [true])
        XCTAssertTrue(viewModel.systemOption(.launchAtLogin))
        XCTAssertEqual(
            try environment.settingsRepository.value(forKey: SettingsSystemOption.launchAtLogin.rawValue),
            #"{"value":true}"#
        )
    }

    func testLaunchAtLoginToggleReportsChineseErrorWhenSystemUpdateFails() throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let launchAtLoginManager = FakeLaunchAtLoginManager(isEnabled: false)
        launchAtLoginManager.errorToThrow = FakeLaunchAtLoginError.rejected
        let viewModel = SettingsViewModel(
            environment: environment,
            shortcutManager: makeShortcutManager(),
            audioDeviceProvider: StubAudioDeviceProvider(),
            permissionProvider: StubPermissionProvider(),
            launchAtLoginManager: launchAtLoginManager
        )

        XCTAssertThrowsError(try viewModel.setSystemOption(.launchAtLogin, enabled: true))
        XCTAssertFalse(viewModel.systemOption(.launchAtLogin))
        XCTAssertEqual(viewModel.lastError, "开机自动启动设置失败：系统拒绝了登录项更新")
    }

    func testExtendedSystemAndPrivacyOptionsPersist() throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let launchAtLoginManager = FakeLaunchAtLoginManager(isEnabled: false)
        let viewModel = SettingsViewModel(
            environment: environment,
            shortcutManager: makeShortcutManager(),
            audioDeviceProvider: StubAudioDeviceProvider(),
            permissionProvider: StubPermissionProvider(),
            launchAtLoginManager: launchAtLoginManager
        )

        try viewModel.setSystemOption(.keepMicrophoneActive, enabled: true)
        try viewModel.setSystemOption(.localModelLivePreview, enabled: true)
        try viewModel.setSystemOption(.autoReleaseLocalModel, enabled: true)
        try viewModel.setSystemOption(.avoidClipboard, enabled: true)
        try viewModel.setSystemOption(.restoreClipboard, enabled: true)
        try viewModel.setSystemOption(.launchAtLogin, enabled: true)
        try viewModel.setSystemOption(.darkMode, enabled: true)
        try viewModel.setSystemOption(.grayMenuBarIcon, enabled: true)
        try viewModel.setSystemOption(.capsLockIndicator, enabled: true)
        try viewModel.setSystemOption(.crashLogs, enabled: true)
        try viewModel.setSystemOption(.llmTraceDiagnostics, enabled: true)

        XCTAssertTrue(viewModel.systemOption(.keepMicrophoneActive))
        XCTAssertTrue(viewModel.systemOption(.localModelLivePreview))
        XCTAssertTrue(viewModel.systemOption(.autoReleaseLocalModel))
        XCTAssertTrue(viewModel.systemOption(.avoidClipboard))
        XCTAssertTrue(viewModel.systemOption(.restoreClipboard))
        XCTAssertTrue(viewModel.systemOption(.launchAtLogin))
        XCTAssertTrue(viewModel.systemOption(.darkMode))
        XCTAssertTrue(viewModel.systemOption(.grayMenuBarIcon))
        XCTAssertTrue(viewModel.systemOption(.capsLockIndicator))
        XCTAssertTrue(viewModel.systemOption(.crashLogs))
        XCTAssertTrue(viewModel.systemOption(.llmTraceDiagnostics))
    }

    private func makeShortcutManager() -> ShortcutManager {
        let suiteName = "test.SettingsViewModel.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }
        return ShortcutManager(defaults: defaults)
    }

    private func isolatedDefaults(name: String) -> UserDefaults {
        let suiteName = "test.SettingsViewModel.\(name).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }
        return defaults
    }

    private func diagnosticTrace() -> TextProcessingTrace {
        TextProcessingTrace(
            llm: LLMRefinementTrace(
                providerID: "provider",
                providerName: "Provider",
                endpoint: "https://api.example.com/v1/chat/completions",
                model: "model",
                temperature: 0.2,
                timeoutSeconds: 8,
                requestBodyJSON: #"{"messages":[{"content":"prompt"}]}"#,
                responseText: "response",
                statusCode: 200,
                durationMS: 123,
                errorMessage: nil,
                completedAt: Date(timeIntervalSince1970: 1_800_000_000)
            )
        )
    }
}

private struct StubAudioDeviceProvider: AudioInputDeviceProviding {
    func inputDevices() -> [AudioInputDevice] {
        [
            AudioInputDevice(id: "built-in", name: "Built-in Mic", isDefault: true),
            AudioInputDevice(id: "studio", name: "Studio Mic", isDefault: false),
        ]
    }
}

private struct StubPermissionProvider: SettingsPermissionProviding {
    func microphonePermission() -> AudioRecorder.PermissionStatus { .granted }
    func speechPermission() -> AudioRecorder.PermissionStatus { .denied }
    func screenRecordingPermission() -> Bool { false }
}

private enum FakeLaunchAtLoginError: LocalizedError {
    case rejected

    var errorDescription: String? {
        "系统拒绝了登录项更新"
    }
}

private final class FakeLaunchAtLoginManager: LaunchAtLoginManaging {
    private(set) var requestedValues: [Bool] = []
    var isEnabled: Bool
    var errorToThrow: Error?

    init(isEnabled: Bool) {
        self.isEnabled = isEnabled
    }

    func setEnabled(_ enabled: Bool) throws {
        requestedValues.append(enabled)
        if let errorToThrow {
            throw errorToThrow
        }
        isEnabled = enabled
    }
}
