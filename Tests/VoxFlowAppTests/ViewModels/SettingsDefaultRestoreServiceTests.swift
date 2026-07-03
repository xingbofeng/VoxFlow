import XCTest
@testable import VoxFlowApp

@MainActor
final class SettingsDefaultRestoreServiceTests: XCTestCase {
    private func makeEnvironment(credentialStore: CredentialStore? = nil) throws -> AppEnvironment {
        if let credentialStore {
            return AppEnvironment(container: try DependencyContainer.inMemory(credentialStore: credentialStore))
        }
        return AppEnvironment(container: try DependencyContainer.inMemory())
    }

    private func makeShortcutManager() -> ShortcutManager {
        let suiteName = "test.SettingsDefaultRestoreService.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        return ShortcutManager(defaults: defaults)
    }

    private func makeLanguageManager() -> LanguageManager {
        let suiteName = "test.SettingsDefaultRestoreService.lang.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        return LanguageManager(defaults: defaults)
    }

    private func makeService(
        environment: AppEnvironment,
        shortcutManager: ShortcutManager,
        languageManager: LanguageManager,
        asrSettingsResetter: (any ASRSettingsResetting)? = nil,
        launchAtLoginManager: (any LaunchAtLoginManaging)? = nil
    ) -> SettingsDefaultRestoreService {
        SettingsDefaultRestoreService(
            settingsRepository: environment.settingsRepository,
            styleRepository: environment.styleRepository,
            shortcutManager: shortcutManager,
            languageManager: languageManager,
            asrSettingsResetter: asrSettingsResetter,
            launchAtLoginManager: launchAtLoginManager ?? FakeLaunchAtLoginManager(isEnabled: true),
            clock: environment.clock
        )
    }

    // MARK: - 2.1 受管偏好重置 + Provider/凭证保留

    func testRestoreResetsManagedPreferenceKeysButKeepsProviderRecordsAndCredentials() throws {
        let store = SettingsDefaultRestoreCredentialStore()
        let environment = try makeEnvironment(credentialStore: store)
        let now = environment.clock.now
        let provider = LLMProviderRecord(
            id: "deepseek",
            displayName: "DeepSeek",
            providerType: LLMProviderProviderType.openAICompatible,
            baseURL: "https://api.deepseek.com",
            defaultModel: "deepseek-v4-flash",
            apiKeyRef: "llm-provider-deepseek",
            temperature: 0.2,
            timeoutSeconds: 30,
            enabled: true,
            isDefault: true,
            lastHealthStatus: "ok",
            lastHealthMessage: "healthy",
            lastLatencyMS: 42,
            createdAt: now,
            updatedAt: now
        )
        try environment.llmProviderRepository.save(provider)
        try store.saveCredential("deepseek-secret", account: provider.apiKeyRef)

        // 受管偏好写入非默认值
        try environment.settingsRepository.set(SettingsKey.audioInputDeviceID, jsonValue: #"{"value":"studio"}"#)
        try environment.settingsRepository.set(SettingsKey.agentDispatchEnabled, jsonValue: #"{"value":true}"#)
        try environment.settingsRepository.set(
            SettingsSystemOption.darkMode.rawValue,
            jsonValue: #"{"value":true}"#
        )
        try environment.settingsRepository.set(
            VoiceCorrectionSettingsKey.shadowMode.rawValue,
            jsonValue: #"{"value":true}"#
        )
        // 未知 key（用户资产/外部写入）应保留
        try environment.settingsRepository.set("custom.user.asset", jsonValue: #"{"value":42}"#)

        let service = makeService(
            environment: environment,
            shortcutManager: makeShortcutManager(),
            languageManager: makeLanguageManager()
        )
        try service.restoreDefaultSettings()

        // 受管 key 被删除
        XCTAssertNil(try environment.settingsRepository.value(forKey: SettingsKey.audioInputDeviceID))
        XCTAssertNil(try environment.settingsRepository.value(forKey: SettingsKey.agentDispatchEnabled))
        XCTAssertNil(try environment.settingsRepository.value(forKey: SettingsSystemOption.darkMode.rawValue))
        XCTAssertNil(try environment.settingsRepository.value(forKey: VoiceCorrectionSettingsKey.shadowMode.rawValue))
        // 未知 key 保留（不 blanket 删除）
        XCTAssertEqual(try environment.settingsRepository.value(forKey: "custom.user.asset"), #"{"value":42}"#)

        // Provider 记录与默认选择保留
        let savedProvider = try XCTUnwrap(try environment.llmProviderRepository.provider(id: "deepseek"))
        XCTAssertEqual(savedProvider.defaultModel, "deepseek-v4-flash")
        XCTAssertTrue(savedProvider.isDefault)

        // Keychain 凭证保留
        XCTAssertEqual(try store.readCredential(account: provider.apiKeyRef), "deepseek-secret")
    }

    func testRestorePreservesInterfaceLanguageAndResetsRecognitionLanguage() throws {
        let environment = try makeEnvironment()
        let languageManager = makeLanguageManager()
        let interfaceDefaultsName = "test.SettingsDefaultRestoreService.iface.\(UUID().uuidString)"
        let interfaceDefaults = UserDefaults(suiteName: interfaceDefaultsName)!
        interfaceDefaults.removePersistentDomain(forName: interfaceDefaultsName)
        addTeardownBlock { interfaceDefaults.removePersistentDomain(forName: interfaceDefaultsName) }
        let interfaceLanguageManager = InterfaceLanguageManager(defaults: interfaceDefaults)

        // 用户设定非默认识别语言 + 非默认界面语言
        languageManager.setLanguage(.english)
        interfaceLanguageManager.setLanguage(.ja)
        XCTAssertEqual(languageManager.currentLanguage, .english)
        XCTAssertEqual(interfaceLanguageManager.currentLanguage, .ja)

        let service = SettingsDefaultRestoreService(
            settingsRepository: environment.settingsRepository,
            styleRepository: environment.styleRepository,
            shortcutManager: makeShortcutManager(),
            languageManager: languageManager,
            asrSettingsResetter: nil,
            launchAtLoginManager: FakeLaunchAtLoginManager(isEnabled: true),
            clock: environment.clock
        )
        try service.restoreDefaultSettings()

        // 识别语言恢复默认
        XCTAssertEqual(languageManager.currentLanguage, RecognitionLanguage.default)
        // 界面语言保留
        XCTAssertEqual(interfaceLanguageManager.currentLanguage, .ja)
    }

    func testRestoreResetsShortcutsASRAndLaunchAtLogin() throws {
        let environment = try makeEnvironment()
        let shortcutManager = makeShortcutManager()
        shortcutManager.shortcutKeyCode = 55
        shortcutManager.longPressThreshold = 0.8
        shortcutManager.shortPressBehavior = .none

        let asrSuiteName = "test.SettingsDefaultRestoreService.asr.\(UUID().uuidString)"
        let asrDefaults = UserDefaults(suiteName: asrSuiteName)!
        asrDefaults.removePersistentDomain(forName: asrSuiteName)
        addTeardownBlock { asrDefaults.removePersistentDomain(forName: asrSuiteName) }
        let asrManager = ASRManager(defaults: asrDefaults)
        asrManager.selectedEngineType = .whisper

        let launchManager = FakeLaunchAtLoginManager(isEnabled: true)

        let service = makeService(
            environment: environment,
            shortcutManager: shortcutManager,
            languageManager: makeLanguageManager(),
            asrSettingsResetter: asrManager,
            launchAtLoginManager: launchManager
        )
        try service.restoreDefaultSettings()

        XCTAssertEqual(shortcutManager.shortcutKeyCode, ShortcutManager.defaultShortcutKeyCode)
        XCTAssertEqual(shortcutManager.longPressThreshold, ShortcutManager.defaultLongPressThreshold)
        XCTAssertEqual(shortcutManager.shortPressBehavior, .toggleListening)
        XCTAssertEqual(asrManager.selectedEngineType, .apple)
        XCTAssertEqual(launchManager.requestedValues, [false])
        XCTAssertFalse(launchManager.isEnabled)
    }

    // MARK: - 2.2 内置风格恢复 + 自定义风格保留

    func testRestoreRestoresBuiltInStylesFromCatalogAndPreservesCustomStyles() throws {
        let environment = try makeEnvironment()
        let now = environment.clock.now

        // 用户改写内置风格 prompt / 禁用 / 改默认
        let formal = try XCTUnwrap(try environment.styleRepository.profile(id: "builtin.formal"))
        try environment.styleRepository.save(
            StyleProfileRecord(
                id: formal.id,
                name: formal.name,
                category: formal.category,
                subtitle: formal.subtitle,
                mode: formal.mode,
                prompt: "custom built-in prompt",
                sampleInput: formal.sampleInput,
                sampleOutput: formal.sampleOutput,
                llmProviderID: formal.llmProviderID,
                model: formal.model,
                temperature: formal.temperature,
                enabled: false,
                builtIn: true,
                isDefault: true,
                createdAt: formal.createdAt,
                updatedAt: now,
                outputFormat: formal.outputFormat,
                allowAutoMatch: false,
                autoMatchDescription: "custom route"
            )
        )

        // 自定义风格
        let customProfile = StyleProfileRecord(
            id: "user.custom-1",
            name: "我的风格",
            category: "custom",
            subtitle: nil,
            mode: "chat",
            prompt: "keep me",
            sampleInput: nil,
            sampleOutput: nil,
            llmProviderID: nil,
            model: nil,
            temperature: 0.3,
            enabled: true,
            builtIn: false,
            isDefault: false,
            createdAt: now,
            updatedAt: now
        )
        try environment.styleRepository.save(customProfile)

        let service = makeService(
            environment: environment,
            shortcutManager: makeShortcutManager(),
            languageManager: makeLanguageManager()
        )
        try service.restoreDefaultSettings()

        let restoredFormal = try XCTUnwrap(try environment.styleRepository.profile(id: "builtin.formal"))
        let catalogFormal = try XCTUnwrap(BuiltInStyleCatalog.profile(id: "builtin.formal", now: now))
        XCTAssertEqual(restoredFormal.prompt, catalogFormal.prompt)
        XCTAssertEqual(restoredFormal.outputFormat, catalogFormal.outputFormat)
        XCTAssertEqual(restoredFormal.allowAutoMatch, catalogFormal.allowAutoMatch)
        XCTAssertEqual(restoredFormal.autoMatchDescription, catalogFormal.autoMatchDescription)
        XCTAssertEqual(restoredFormal.enabled, true) // 启用状态恢复
        XCTAssertEqual(restoredFormal.isDefault, false) // 不再是默认

        // 默认风格恢复为 builtin.original
        let defaultProfile = try XCTUnwrap(try environment.styleRepository.defaultProfile())
        XCTAssertEqual(defaultProfile.id, "builtin.original")

        // 自定义风格保留不变
        let restoredCustom = try XCTUnwrap(try environment.styleRepository.profile(id: "user.custom-1"))
        XCTAssertEqual(restoredCustom.prompt, "keep me")
        XCTAssertEqual(restoredCustom.builtIn, false)
    }

    // MARK: - 2.3 自动匹配恢复默认 + route cache 清空

    func testRestoreRestoresAutoMatchDefaultsAndClearsRouteCache() throws {
        let environment = try makeEnvironment()
        let autoMatchStore = StyleAutoMatchSettingsStore(settingsRepository: environment.settingsRepository)

        // 用户关闭自动匹配、改 TTL、写入 route cache
        var settings = autoMatchStore.load()
        settings.globalEnabled = false
        settings.routeCacheTTLHours = 2
        settings.routeCache["com.example.app"] = StyleRouteCacheEntry(
            styleID: "builtin.formal",
            source: "ai",
            createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            lastUsedAt: Date(timeIntervalSince1970: 1_800_000_000),
            expiresAt: Date(timeIntervalSince1970: 1_800_000_000).addingTimeInterval(3600),
            hitCount: 1
        )
        try autoMatchStore.save(settings)

        let service = makeService(
            environment: environment,
            shortcutManager: makeShortcutManager(),
            languageManager: makeLanguageManager()
        )
        try service.restoreDefaultSettings()

        let restored = autoMatchStore.load()
        XCTAssertTrue(restored.globalEnabled) // 默认开启
        XCTAssertEqual(restored.routeCacheTTLHours, 24) // 默认 TTL
        XCTAssertEqual(restored.contextRounds, ContextRoundsSettings.defaults)
        XCTAssertTrue(restored.routeCache.isEmpty) // route cache 清空
    }

    // MARK: - 2.4 历史与词汇数据保留

    func testRestorePreservesHistoryAndVocabularyData() throws {
        let environment = try makeEnvironment()
        let now = environment.clock.now

        try environment.historyRepository.save(
            DictationHistoryEntry(
                id: "history-1",
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

        // 词汇/纠错学习候选数据（auto-learning candidate）
        _ = try environment.correctionTargetRepository.recordKeyTermObservation("voxflow", now: now)

        let service = makeService(
            environment: environment,
            shortcutManager: makeShortcutManager(),
            languageManager: makeLanguageManager()
        )
        try service.restoreDefaultSettings()

        // 历史保留
        let history = try environment.historyRepository.listRecent(limit: 10)
        XCTAssertEqual(history.map(\.id), ["history-1"])

        // 词汇/学习数据保留
        let terms = try environment.correctionTargetRepository.list()
        XCTAssertTrue(terms.contains { $0.text == "voxflow" })
    }
}

// MARK: - Test Doubles

private final class FakeLaunchAtLoginManager: LaunchAtLoginManaging {
    private(set) var requestedValues: [Bool] = []
    var isEnabled: Bool

    init(isEnabled: Bool) {
        self.isEnabled = isEnabled
    }

    func setEnabled(_ enabled: Bool) throws {
        requestedValues.append(enabled)
        isEnabled = enabled
    }
}

private final class SettingsDefaultRestoreCredentialStore: CredentialStore {
    private var values: [String: String] = [:]

    func saveCredential(_ value: String, account: String) throws {
        values[account] = value
    }

    func readCredential(account: String) throws -> String? {
        values[account]
    }

    func deleteCredential(account: String) throws {
        values.removeValue(forKey: account)
    }
}
