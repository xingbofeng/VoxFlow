import XCTest
@testable import VoiceInputApp

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

        XCTAssertEqual(SettingsSection.allCases.map(\.title), ["通用", "模型", "系统", "数据与隐私"])
        XCTAssertEqual(viewModel.inputDevices.map(\.name), ["Built-in Mic", "Studio Mic"])
        XCTAssertEqual(viewModel.selectedInputDeviceID, "built-in")
        XCTAssertEqual(viewModel.shortcutKeyCode, 54)
        XCTAssertEqual(viewModel.longPressThreshold, 0.5)
        XCTAssertEqual(viewModel.shortPressBehavior, .toggleListening)
        XCTAssertEqual(viewModel.microphonePermission, .granted)
        XCTAssertEqual(viewModel.speechPermission, .denied)
        XCTAssertFalse(viewModel.screenRecordingGranted)
        XCTAssertEqual(
            viewModel.systemSettingsURL(for: .microphone)?.absoluteString,
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        )
        XCTAssertEqual(
            viewModel.systemSettingsURL(for: .screenRecording)?.absoluteString,
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        )
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
        try viewModel.updateShortcut(keyCode: 63, longPressThreshold: 0.8, shortPressBehavior: .none)
        try viewModel.updateAudioOptions(soundFeedback: false, voiceEnhancement: false)
        try viewModel.updatePerformanceOptions(muteWhileRecording: true, performanceOptimization: true)
        try viewModel.setAnalyticsEnabled(true)

        XCTAssertEqual(shortcutManager.shortcutKeyCode, 63)
        XCTAssertEqual(shortcutManager.longPressThreshold, 0.8)
        XCTAssertEqual(shortcutManager.shortPressBehavior, .none)
        XCTAssertEqual(try environment.settingsRepository.value(forKey: SettingsKey.audioInputDeviceID), #"{"value":"studio"}"#)
        XCTAssertEqual(try environment.settingsRepository.value(forKey: SettingsKey.audioSoundFeedbackEnabled), #"{"value":false}"#)
        XCTAssertEqual(try environment.settingsRepository.value(forKey: SettingsKey.audioVoiceEnhancementEnabled), #"{"value":false}"#)
        XCTAssertEqual(try environment.settingsRepository.value(forKey: SettingsKey.audioMuteWhileRecordingEnabled), #"{"value":true}"#)
        XCTAssertEqual(try environment.settingsRepository.value(forKey: SettingsKey.performanceOptimizationEnabled), #"{"value":true}"#)
        XCTAssertEqual(try environment.settingsRepository.value(forKey: SettingsKey.analyticsEnabled), #"{"value":true}"#)
        XCTAssertEqual(viewModel.lastActionMessage, "已更新分析设置")
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
        XCTAssertEqual(viewModel.lastActionMessage, "已重置设置")
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

        viewModel.applyShortcutKeyCode("63")
        XCTAssertEqual(shortcutManager.shortcutKeyCode, 63)
        XCTAssertEqual(viewModel.lastActionMessage, "已应用快捷键")

        viewModel.applyShortcutKeyCode("invalid")
        XCTAssertEqual(viewModel.lastError, "快捷键录制失败，请按下一个有效按键。")
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
