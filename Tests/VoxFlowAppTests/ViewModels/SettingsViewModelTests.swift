import XCTest
@testable import VoxFlowApp

@MainActor
final class SettingsViewModelTests: XCTestCase {
    func testLoadBuildsThreeSectionsDevicesShortcutAndPermissions() throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let viewModel = SettingsViewModel(
            environment: environment,
            shortcutManager: makeShortcutManager(),
            audioDeviceProvider: StubAudioDeviceProvider(),
            permissionProvider: StubPermissionProvider()
        )

        XCTAssertEqual(SettingsSection.allCases.map(\.title), ["通用", "听写模型", "纠错模型", "系统", "数据与隐私"])
        XCTAssertEqual(viewModel.inputDevices.map(\.name), ["Built-in Mic", "Studio Mic"])
        XCTAssertEqual(viewModel.selectedInputDeviceID, "built-in")
        XCTAssertEqual(viewModel.shortcutKeyCode, 54)
        XCTAssertEqual(viewModel.longPressThreshold, 0.5)
        XCTAssertEqual(viewModel.shortPressBehavior, .toggleListening)
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

    func testVoiceShortcutRejectsNonModifierKeyCodes() throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let shortcutManager = makeShortcutManager()
        let viewModel = SettingsViewModel(
            environment: environment,
            shortcutManager: shortcutManager,
            audioDeviceProvider: StubAudioDeviceProvider(),
            permissionProvider: StubPermissionProvider()
        )

        XCTAssertThrowsError(
            try viewModel.updateActionShortcut(action: .dictation, keyCode: 0x09)
        ) { error in
            XCTAssertEqual(
                error.localizedDescription,
                "语音快捷键仅支持 Command、Option、Control 或 Shift 这类单独修饰键。"
            )
        }
        XCTAssertEqual(shortcutManager.shortcutKeyCode, 54)
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

    func testExtendedSystemAndPrivacyOptionsPersist() throws {
        let environment = AppEnvironment(container: try DependencyContainer.inMemory())
        let viewModel = SettingsViewModel(
            environment: environment,
            shortcutManager: makeShortcutManager(),
            audioDeviceProvider: StubAudioDeviceProvider(),
            permissionProvider: StubPermissionProvider()
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
