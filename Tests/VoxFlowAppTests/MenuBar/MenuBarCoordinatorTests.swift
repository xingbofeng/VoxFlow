import AppKit
import XCTest
@testable import VoxFlowApp

@MainActor
final class MenuBarCoordinatorTests: XCTestCase {
    func testAttachUsesDefaultStatusItemMenuPresentation() throws {
        let coordinator = MenuBarCoordinator(
            asrOptions: [],
            currentLanguage: { .simplifiedChinese },
            isASRMenuOptionEnabled: { _ in true },
            isASRMenuOptionSelected: { _ in false },
            actions: .noop
        )
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        defer { NSStatusBar.system.removeStatusItem(statusItem) }

        coordinator.attach(to: statusItem)

        let button = try XCTUnwrap(statusItem.button)
        XCTAssertTrue(statusItem.menu === coordinator.menu)
        XCTAssertNil(button.action)
        XCTAssertNil(button.target)
    }

    func testCoordinatorBuildsStatusMenuAndRoutesActions() throws {
        let asrOption = ASRMenuModel(engineType: .apple, title: "系统自带")
        var selectedLanguage: RecognitionLanguage?
        var selectedASR: ASRMenuModel?
        var selectedLLMProviderID: String?
        var selectedAgentProviderID: String?
        var selectedCapabilityModel: (CapabilityModelKind, String)?
        var openedWorkbench = false
        var openedSettings = false
        var openedGitHub = false
        var checkedPermissions = false
        var selectionActionRequested = false
        var quitRequested = false
        let provider = makeProvider(id: "provider", displayName: "OpenAI", model: "gpt-4.1", enabled: true, isDefault: true)
        let agentProvider = makeProvider(
            id: "codex",
            displayName: "Codex",
            model: "gpt-5.4-mini",
            enabled: true,
            isDefault: false,
            providerType: "codex",
            baseURL: "local://codex"
        )
        let coordinator = MenuBarCoordinator(
            asrOptions: [asrOption],
            currentLanguage: { .simplifiedChinese },
            isASRMenuOptionEnabled: { _ in true },
            isASRMenuOptionSelected: { _ in false },
            actions: MenuBarActions(
                selectLanguage: { selectedLanguage = $0 },
                selectASRMenuOption: { selectedASR = $0 },
                selectLLMProvider: { selectedLLMProviderID = $0 },
                selectAgentProvider: { selectedAgentProviderID = $0 },
                selectCapabilityModel: { kind, id in selectedCapabilityModel = (kind, id) },
                openWorkbench: { openedWorkbench = true },
                requestSelectionAction: { selectionActionRequested = true },
                openSettings: { openedSettings = true },
                openGitHub: { openedGitHub = true },
                checkPermissions: { checkedPermissions = true },
                quit: { quitRequested = true },
                menuWillOpen: {}
            ),
            llmProviders: { [provider, agentProvider] },
            selectedLLMProviderID: { "provider" },
            selectedAgentProviderID: { "codex" },
            capabilityModels: { CapabilityModelCatalog.models(for: $0) },
            selectedCapabilityModelID: {
                $0 == .tts ? CapabilityModelID.systemDefaultTTS : CapabilityModelID.systemDefaultTranslation
            },
            isCapabilityModelEnabled: { $0.isInstalled }
        )

        let languageItem = try XCTUnwrap(
            coordinator.menu.item(withTitle: menuLanguageTitle)?.submenu?.item(withTitle: "English")
        )
        let asrItem = try XCTUnwrap(
            coordinator.menu.item(withTitle: menuAsrModelTitle)?.submenu?.item(withTitle: "系统自带")
        )
        let llmItem = try XCTUnwrap(
            coordinator.menu.item(withTitle: menuLLMServiceTitle)?.submenu?.item(withTitle: "OpenAI · gpt-4.1")
        )
        let agentItem = try XCTUnwrap(
            coordinator.menu.item(withTitle: menuAgentModelTitle)?.submenu?.item(withTitle: "Codex · gpt-5.4-mini")
        )
        let ttsItem = try XCTUnwrap(
            coordinator.menu.item(withTitle: menuTTSModelTitle)?.submenu?.item(withTitle: "系统默认")
        )

        sendAction(for: languageItem)
        sendAction(for: asrItem)
        sendAction(for: llmItem)
        sendAction(for: agentItem)
        sendAction(for: ttsItem)
        sendAction(for: try XCTUnwrap(coordinator.menu.item(withTitle: menuOpenWorkbenchTitle)))
        sendAction(for: try XCTUnwrap(coordinator.menu.item(withTitle: menuSelectionActionTitle)))
        sendAction(for: try XCTUnwrap(coordinator.menu.item(withTitle: menuSettingsTitle)))
        sendAction(for: try XCTUnwrap(coordinator.menu.item(withTitle: menuGitHubTitle)))
        sendAction(for: try XCTUnwrap(coordinator.menu.item(withTitle: menuCheckPermissionsTitle)))
        sendAction(for: try XCTUnwrap(coordinator.menu.item(withTitle: menuQuitTitle())))

        XCTAssertEqual(selectedLanguage, .english)
        XCTAssertEqual(selectedASR, asrOption)
        XCTAssertEqual(selectedLLMProviderID, "provider")
        XCTAssertEqual(selectedAgentProviderID, "codex")
        XCTAssertEqual(selectedCapabilityModel?.0, .tts)
        XCTAssertEqual(selectedCapabilityModel?.1, CapabilityModelID.systemDefaultTTS)
        XCTAssertTrue(openedWorkbench)
        XCTAssertTrue(selectionActionRequested)
        XCTAssertTrue(openedSettings)
        XCTAssertTrue(openedGitHub)
        XCTAssertTrue(checkedPermissions)
        XCTAssertTrue(quitRequested)

        let modelMenuTitles = coordinator.menu.items.map(\.title)
        XCTAssertLessThan(
            try XCTUnwrap(modelMenuTitles.firstIndex(of: menuAsrModelTitle)),
            try XCTUnwrap(modelMenuTitles.firstIndex(of: menuLLMServiceTitle))
        )
        XCTAssertLessThan(
            try XCTUnwrap(modelMenuTitles.firstIndex(of: menuLLMServiceTitle)),
            try XCTUnwrap(modelMenuTitles.firstIndex(of: menuAgentModelTitle))
        )
        XCTAssertLessThan(
            try XCTUnwrap(modelMenuTitles.firstIndex(of: menuAgentModelTitle)),
            try XCTUnwrap(modelMenuTitles.firstIndex(of: menuTranslationModelTitle))
        )
        XCTAssertLessThan(
            try XCTUnwrap(modelMenuTitles.firstIndex(of: menuTranslationModelTitle)),
            try XCTUnwrap(modelMenuTitles.firstIndex(of: menuTTSModelTitle))
        )
    }

    func testCoordinatorBuildsModelSubmenusAndRefreshesLinkedStateWhenMenuOpens() throws {
        var defaultProviderID = "primary"
        var kokoroInstalled = false
        let primary = makeProvider(id: "primary", displayName: "Primary", model: "gpt-primary", enabled: true, isDefault: true)
        let disabled = makeProvider(id: "disabled", displayName: "Disabled", model: "gpt-disabled", enabled: false, isDefault: false)
        let coordinator = MenuBarCoordinator(
            asrOptions: [],
            currentLanguage: { .simplifiedChinese },
            isASRMenuOptionEnabled: { _ in true },
            isASRMenuOptionSelected: { _ in false },
            actions: .noop,
            llmProviders: { [primary, disabled] },
            selectedLLMProviderID: { defaultProviderID },
            capabilityModels: { kind in
                CapabilityModelCatalog.models(for: kind).map { model in
                    var mutable = model
                    if model.id == CapabilityModelID.kokoroTTS {
                        mutable.isInstalled = kokoroInstalled
                    }
                    return mutable
                }
            },
            selectedCapabilityModelID: { kind in
                kind == .tts ? CapabilityModelID.kokoroTTS : CapabilityModelID.systemDefaultTranslation
            },
            isCapabilityModelEnabled: { $0.isInstalled }
        )

        var llmMenu = try XCTUnwrap(coordinator.menu.item(withTitle: menuLLMServiceTitle)?.submenu)
        var ttsMenu = try XCTUnwrap(coordinator.menu.item(withTitle: menuTTSModelTitle)?.submenu)
        var translationMenu = try XCTUnwrap(coordinator.menu.item(withTitle: menuTranslationModelTitle)?.submenu)
        let disabledLLMItem = try XCTUnwrap(llmMenu.item(withTitle: "Disabled · gpt-disabled") as NSMenuItem?)
        let disabledKokoroItem = try XCTUnwrap(ttsMenu.item(withTitle: "Kokoro TTS（\(menuNotDownloadedSuffix)）") as NSMenuItem?)

        XCTAssertEqual(llmMenu.item(withTitle: "Primary · gpt-primary")?.state, .on)
        XCTAssertFalse(disabledLLMItem.isEnabled)
        XCTAssertEqual(ttsMenu.item(withTitle: "Kokoro TTS（\(menuNotDownloadedSuffix)）")?.state, .on)
        XCTAssertFalse(disabledKokoroItem.isEnabled)
        XCTAssertEqual(translationMenu.item(withTitle: "系统默认")?.state, .on)

        defaultProviderID = "disabled"
        kokoroInstalled = true
        coordinator.menuWillOpen(coordinator.menu)

        llmMenu = try XCTUnwrap(coordinator.menu.item(withTitle: menuLLMServiceTitle)?.submenu)
        ttsMenu = try XCTUnwrap(coordinator.menu.item(withTitle: menuTTSModelTitle)?.submenu)
        translationMenu = try XCTUnwrap(coordinator.menu.item(withTitle: menuTranslationModelTitle)?.submenu)
        let enabledKokoroItem = try XCTUnwrap(ttsMenu.item(withTitle: "Kokoro TTS") as NSMenuItem?)

        XCTAssertEqual(llmMenu.item(withTitle: "Primary · gpt-primary")?.state, .on)
        XCTAssertEqual(llmMenu.item(withTitle: "Disabled · gpt-disabled")?.state, .off)
        XCTAssertTrue(enabledKokoroItem.isEnabled)
        XCTAssertEqual(ttsMenu.item(withTitle: "Kokoro TTS")?.state, .on)
        XCTAssertNotNil(translationMenu.item(withTitle: "Soniqo MADLAD（\(menuNotDownloadedSuffix)）"))
    }

    func testCoordinatorRunsMenuWillOpenActionBeforeRefreshingProviderSelection() throws {
        let primary = makeProvider(id: "primary", displayName: "Primary", model: "gpt-primary", enabled: true, isDefault: true)
        let secondary = makeProvider(id: "secondary", displayName: "Secondary", model: "gpt-secondary", enabled: true, isDefault: false)
        let primaryAfterSync = makeProvider(id: "primary", displayName: "Primary", model: "gpt-primary", enabled: true, isDefault: false)
        let secondaryAfterSync = makeProvider(id: "secondary", displayName: "Secondary", model: "gpt-secondary", enabled: true, isDefault: true)
        var providers = [primary, secondary]
        let coordinator = MenuBarCoordinator(
            asrOptions: [],
            currentLanguage: { .simplifiedChinese },
            isASRMenuOptionEnabled: { _ in true },
            isASRMenuOptionSelected: { _ in false },
            actions: MenuBarActions(
                selectLanguage: { _ in },
                selectASRMenuOption: { _ in },
                openWorkbench: {},
                openSettings: {},
                openGitHub: {},
                checkPermissions: {},
                quit: {},
                menuWillOpen: {
                    providers = [primaryAfterSync, secondaryAfterSync]
                }
            ),
            llmProviders: { providers },
            selectedLLMProviderID: { providers.first(where: \.isDefault)?.id }
        )

        coordinator.menuWillOpen(coordinator.menu)

        let llmMenu = try XCTUnwrap(coordinator.menu.item(withTitle: menuLLMServiceTitle)?.submenu)
        XCTAssertEqual(llmMenu.item(withTitle: "Primary · gpt-primary")?.state, .off)
        XCTAssertEqual(llmMenu.item(withTitle: "Secondary · gpt-secondary")?.state, .on)
    }

    func testCoordinatorRefreshesProviderSelectionWhenLLMSubmenuOpens() throws {
        let primary = makeProvider(id: "primary", displayName: "Primary", model: "gpt-primary", enabled: true, isDefault: true)
        let secondary = makeProvider(id: "secondary", displayName: "Secondary", model: "gpt-secondary", enabled: true, isDefault: false)
        let primaryAfterSync = makeProvider(id: "primary", displayName: "Primary", model: "gpt-primary", enabled: true, isDefault: false)
        let secondaryAfterSync = makeProvider(id: "secondary", displayName: "Secondary", model: "gpt-secondary", enabled: true, isDefault: true)
        var providers = [primary, secondary]
        var menuWillOpenCount = 0
        let coordinator = MenuBarCoordinator(
            asrOptions: [],
            currentLanguage: { .simplifiedChinese },
            isASRMenuOptionEnabled: { _ in true },
            isASRMenuOptionSelected: { _ in false },
            actions: MenuBarActions(
                selectLanguage: { _ in },
                selectASRMenuOption: { _ in },
                openWorkbench: {},
                openSettings: {},
                openGitHub: {},
                checkPermissions: {},
                quit: {},
                menuWillOpen: {
                    menuWillOpenCount += 1
                    providers = [primaryAfterSync, secondaryAfterSync]
                }
            ),
            llmProviders: { providers },
            selectedLLMProviderID: { providers.first(where: \.isDefault)?.id }
        )

        let llmMenu = try XCTUnwrap(coordinator.menu.item(withTitle: menuLLMServiceTitle)?.submenu)

        coordinator.menuWillOpen(llmMenu)

        XCTAssertEqual(menuWillOpenCount, 1)
        XCTAssertEqual(llmMenu.item(withTitle: "Primary · gpt-primary")?.state, .off)
        XCTAssertEqual(llmMenu.item(withTitle: "Secondary · gpt-secondary")?.state, .on)
    }

    func testLLMAndAgentProviderMenusAreSeparate() throws {
        let openAI = makeProvider(
            id: "openai",
            displayName: "OpenAI",
            model: "gpt-4.1",
            enabled: true,
            isDefault: true
        )
        let codex = makeProvider(
            id: "codex",
            displayName: "Codex",
            model: "gpt-5.4-mini",
            enabled: true,
            isDefault: false,
            providerType: "codex",
            baseURL: "local://codex",
            lastHealthStatus: "ok"
        )
        let claude = makeProvider(
            id: "claude",
            displayName: "Claude Code",
            model: "sonnet",
            enabled: false,
            isDefault: false,
            providerType: "claude",
            baseURL: "local://claude",
            lastHealthStatus: nil
        )
        let detectedOpenCode = makeProvider(
            id: "opencode",
            displayName: "Opencode",
            model: "opencode/big-pickle",
            enabled: false,
            isDefault: false,
            providerType: "opencode",
            baseURL: "local://opencode",
            lastHealthStatus: "ok"
        )
        let coordinator = MenuBarCoordinator(
            asrOptions: [],
            currentLanguage: { .simplifiedChinese },
            isASRMenuOptionEnabled: { _ in true },
            isASRMenuOptionSelected: { _ in false },
            actions: .noop,
            llmProviders: { [openAI, codex, claude, detectedOpenCode] },
            selectedLLMProviderID: { "openai" },
            selectedAgentProviderID: { "codex" }
        )

        let llmMenu = try XCTUnwrap(coordinator.menu.item(withTitle: menuLLMServiceTitle)?.submenu)
        let agentMenu = try XCTUnwrap(coordinator.menu.item(withTitle: menuAgentModelTitle)?.submenu)

        XCTAssertNotNil(llmMenu.item(withTitle: "OpenAI · gpt-4.1"))
        XCTAssertNil(llmMenu.item(withTitle: "Codex · gpt-5.4-mini"))
        XCTAssertNil(llmMenu.item(withTitle: "Claude Code · sonnet"))
        XCTAssertNil(agentMenu.item(withTitle: "OpenAI · gpt-4.1"))
        XCTAssertEqual(agentMenu.item(withTitle: "Codex · gpt-5.4-mini")?.state, .on)
        XCTAssertEqual(agentMenu.item(withTitle: "Claude Code · sonnet")?.state, .off)
        XCTAssertFalse(try XCTUnwrap(agentMenu.item(withTitle: "Claude Code · sonnet")).isEnabled)
        let openCodeItem = try XCTUnwrap(agentMenu.item(withTitle: "Opencode · opencode/big-pickle"))
        XCTAssertTrue(openCodeItem.isEnabled)
        XCTAssertEqual(openCodeItem.state, .off)
    }

    func testAgentProviderMenuDisablesConfiguredProviderWhenHealthIsError() throws {
        let brokenAgent = makeProvider(
            id: "opencode",
            displayName: "opencode",
            model: "kimi-k2",
            enabled: true,
            isDefault: false,
            providerType: "opencode",
            baseURL: "local://opencode",
            lastHealthStatus: "error"
        )
        let coordinator = MenuBarCoordinator(
            asrOptions: [],
            currentLanguage: { .simplifiedChinese },
            isASRMenuOptionEnabled: { _ in true },
            isASRMenuOptionSelected: { _ in false },
            actions: .noop,
            llmProviders: { [brokenAgent] },
            selectedAgentProviderID: { "opencode" }
        )

        let agentMenu = try XCTUnwrap(coordinator.menu.item(withTitle: menuAgentModelTitle)?.submenu)
        let item = try XCTUnwrap(agentMenu.item(withTitle: "Opencode · kimi-k2"))

        XCTAssertFalse(item.isEnabled)
        XCTAssertEqual(item.state, .on)
    }

    func testTranslationLLMMenuItemIsDisabledWhenProviderIsUnavailable() throws {
        let coordinator = MenuBarCoordinator(
            asrOptions: [],
            currentLanguage: { .simplifiedChinese },
            isASRMenuOptionEnabled: { _ in true },
            isASRMenuOptionSelected: { _ in false },
            actions: .noop,
            capabilityModels: { kind in
                CapabilityModelCatalog.models(for: kind).map { model in
                    var mutable = model
                    if model.id == CapabilityModelID.llmTranslation {
                        mutable.isInstalled = false
                    }
                    return mutable
                }
            },
            selectedCapabilityModelID: { kind in
                kind == .tts ? CapabilityModelID.systemDefaultTTS : CapabilityModelID.systemDefaultTranslation
            },
            isCapabilityModelEnabled: { $0.isInstalled }
        )

        let translationMenu = try XCTUnwrap(coordinator.menu.item(withTitle: menuTranslationModelTitle)?.submenu)
        let llmItem = try XCTUnwrap(translationMenu.item(withTitle: "智能模型配置（\(menuNotConfiguredSuffix)）"))

        XCTAssertFalse(llmItem.isEnabled)
        XCTAssertEqual(llmItem.state, .off)
        XCTAssertEqual(translationMenu.item(withTitle: "系统默认")?.state, .on)
    }

    func testCoordinatorRefreshesLanguageASRAndRefiningStateWhenMenuOpens() throws {
        let apple = ASRMenuModel(engineType: .apple, title: "系统自带")
        let qwen = ASRMenuModel(engineType: .qwen3, modelSize: .size0_6B, title: "Qwen3-ASR 0.6B")
        var currentLanguage = RecognitionLanguage.english
        var selectedASR = qwen
        var menuWillOpenCount = 0
        var enabledChecks = 0
        var selectedChecks = 0
        let coordinator = MenuBarCoordinator(
            asrOptions: [apple, qwen],
            currentLanguage: { currentLanguage },
            isASRMenuOptionEnabled: {
                enabledChecks += 1
                return $0.engineType == .apple
            },
            isASRMenuOptionSelected: {
                selectedChecks += 1
                return $0 == selectedASR
            },
            actions: MenuBarActions(
                selectLanguage: { _ in },
                selectASRMenuOption: { _ in },
                openWorkbench: {},
                openSettings: {},
                openGitHub: {},
                checkPermissions: {},
                quit: {},
                menuWillOpen: { menuWillOpenCount += 1 }
            )
        )

        currentLanguage = .simplifiedChinese
        selectedASR = apple
        enabledChecks = 0
        selectedChecks = 0
        coordinator.setRefiningStatusVisible(true)
        coordinator.menuWillOpen(coordinator.menu)

        let languageMenu = try XCTUnwrap(coordinator.menu.item(withTitle: menuLanguageTitle)?.submenu)
        let englishItem = try XCTUnwrap(
            languageMenu.item(withTitle: "English")
        )
        let chineseItem = try XCTUnwrap(
            languageMenu.item(withTitle: "简体中文")
        )
        let appleItem = try XCTUnwrap(
            coordinator.menu.item(withTitle: menuAsrModelTitle)?.submenu?.item(withTitle: "系统自带")
        )
        let qwenItem = try XCTUnwrap(
            coordinator.menu.item(withTitle: menuAsrModelTitle)?.submenu?.item(withTitle: "Qwen3-ASR 0.6B")
        )

        XCTAssertEqual(englishItem.state, .off)
        XCTAssertEqual(chineseItem.state, .on)
        XCTAssertNotNil(languageMenu.item(withTitle: "繁體中文"))
        XCTAssertNotNil(languageMenu.item(withTitle: "日本語"))
        XCTAssertNotNil(languageMenu.item(withTitle: "한국어"))
        XCTAssertEqual(appleItem.state, .on)
        XCTAssertTrue(appleItem.isEnabled)
        XCTAssertEqual(qwenItem.state, .off)
        XCTAssertFalse(qwenItem.isEnabled)
        XCTAssertFalse(try XCTUnwrap(coordinator.menu.item(withTitle: menuRefiningStatusTitle)).isHidden)
        XCTAssertEqual(enabledChecks, 2)
        XCTAssertEqual(selectedChecks, 2)
        XCTAssertEqual(menuWillOpenCount, 1)
    }

    private var menuLanguageTitle: String {
        L10n.localize("menu.status.language", comment: "")
    }

    private var menuAsrModelTitle: String {
        L10n.localize("menu.status.asr_model", comment: "")
    }

    private var menuLLMServiceTitle: String {
        L10n.localize("menu.status.llm_service", comment: "")
    }

    private var menuAgentModelTitle: String {
        L10n.localize("menu.status.agent_model", comment: "")
    }

    private var menuTTSModelTitle: String {
        L10n.localize("menu.status.tts_model", comment: "")
    }

    private var menuTranslationModelTitle: String {
        L10n.localize("menu.status.translation_model", comment: "")
    }

    private var menuOpenWorkbenchTitle: String {
        L10n.localize("menu.status.open_workbench", comment: "")
    }

    private var menuSelectionActionTitle: String {
        L10n.localize("menu.status.selection_action", comment: "")
    }

    private var menuSettingsTitle: String {
        L10n.localize("menu.status.settings", comment: "")
    }

    private var menuGitHubTitle: String {
        L10n.localize("menu.status.github", comment: "")
    }

    private var menuCheckPermissionsTitle: String {
        L10n.localize("menu.status.check_permissions", comment: "")
    }

    private func menuQuitTitle() -> String {
        L10n.localize("menu.status.quit", comment: "")
    }

    private var menuRefiningStatusTitle: String {
        L10n.localize("menu.status.refining", comment: "")
    }

    private var menuNotDownloadedSuffix: String {
        L10n.localize("menu.status.capability.not_downloaded", comment: "")
    }

    private var menuNotConfiguredSuffix: String {
        L10n.localize("menu.status.capability.not_configured", comment: "")
    }

    private func sendAction(for item: NSMenuItem) {
        guard let action = item.action else {
            XCTFail("Expected menu item \(item.title) to have an action.")
            return
        }
        XCTAssertTrue(NSApplication.shared.sendAction(action, to: item.target, from: item))
    }

    private func makeProvider(
        id: String,
        displayName: String,
        model: String,
        enabled: Bool,
        isDefault: Bool,
        providerType: String = "openaiCompatible",
        baseURL: String = "https://api.example.com/v1",
        lastHealthStatus: String? = nil
    ) -> LLMProviderRecord {
        LLMProviderRecord(
            id: id,
            displayName: displayName,
            providerType: providerType,
            baseURL: baseURL,
            defaultModel: model,
            apiKeyRef: "llm-provider-\(id)",
            temperature: 0.2,
            timeoutSeconds: 30,
            enabled: enabled,
            isDefault: isDefault,
            lastHealthStatus: lastHealthStatus,
            lastHealthMessage: nil,
            lastLatencyMS: nil,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }
}
