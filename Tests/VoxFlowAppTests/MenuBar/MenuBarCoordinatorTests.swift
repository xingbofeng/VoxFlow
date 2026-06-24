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
        var selectedCapabilityModel: (CapabilityModelKind, String)?
        var openedWorkbench = false
        var openedSettings = false
        var openedGitHub = false
        var checkedPermissions = false
        var selectionActionRequested = false
        var quitRequested = false
        let provider = makeProvider(id: "provider", displayName: "OpenAI", model: "gpt-4.1", enabled: true, isDefault: true)
        let coordinator = MenuBarCoordinator(
            asrOptions: [asrOption],
            currentLanguage: { .simplifiedChinese },
            isASRMenuOptionEnabled: { _ in true },
            isASRMenuOptionSelected: { _ in false },
            actions: MenuBarActions(
                selectLanguage: { selectedLanguage = $0 },
                selectASRMenuOption: { selectedASR = $0 },
                selectLLMProvider: { selectedLLMProviderID = $0 },
                selectCapabilityModel: { kind, id in selectedCapabilityModel = (kind, id) },
                openWorkbench: { openedWorkbench = true },
                requestSelectionAction: { selectionActionRequested = true },
                openSettings: { openedSettings = true },
                openGitHub: { openedGitHub = true },
                checkPermissions: { checkedPermissions = true },
                quit: { quitRequested = true },
                menuWillOpen: {}
            ),
            llmProviders: { [provider] },
            selectedLLMProviderID: { "provider" },
            capabilityModels: { CapabilityModelCatalog.models(for: $0) },
            selectedCapabilityModelID: {
                $0 == .tts ? CapabilityModelID.systemDefaultTTS : CapabilityModelID.systemDefaultTranslation
            },
            isCapabilityModelEnabled: { $0.isInstalled }
        )

        let languageItem = try XCTUnwrap(
            coordinator.menu.item(withTitle: "语言 / Language")?.submenu?.item(withTitle: "English")
        )
        let asrItem = try XCTUnwrap(
            coordinator.menu.item(withTitle: "语音识别模型")?.submenu?.item(withTitle: "系统自带")
        )
        let llmItem = try XCTUnwrap(
            coordinator.menu.item(withTitle: "智能模型服务")?.submenu?.item(withTitle: "OpenAI · gpt-4.1")
        )
        let ttsItem = try XCTUnwrap(
            coordinator.menu.item(withTitle: "TTS 模型")?.submenu?.item(withTitle: "系统默认")
        )

        sendAction(for: languageItem)
        sendAction(for: asrItem)
        sendAction(for: llmItem)
        sendAction(for: ttsItem)
        sendAction(for: try XCTUnwrap(coordinator.menu.item(withTitle: "打开工作台")))
        sendAction(for: try XCTUnwrap(coordinator.menu.item(withTitle: "划词动作")))
        sendAction(for: try XCTUnwrap(coordinator.menu.item(withTitle: "设置")))
        sendAction(for: try XCTUnwrap(coordinator.menu.item(withTitle: "GitHub")))
        sendAction(for: try XCTUnwrap(coordinator.menu.item(withTitle: "检查权限")))
        sendAction(for: try XCTUnwrap(coordinator.menu.item(withTitle: "退出码上写")))

        XCTAssertEqual(selectedLanguage, .english)
        XCTAssertEqual(selectedASR, asrOption)
        XCTAssertEqual(selectedLLMProviderID, "provider")
        XCTAssertEqual(selectedCapabilityModel?.0, .tts)
        XCTAssertEqual(selectedCapabilityModel?.1, CapabilityModelID.systemDefaultTTS)
        XCTAssertTrue(openedWorkbench)
        XCTAssertTrue(selectionActionRequested)
        XCTAssertTrue(openedSettings)
        XCTAssertTrue(openedGitHub)
        XCTAssertTrue(checkedPermissions)
        XCTAssertTrue(quitRequested)
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

        var llmMenu = try XCTUnwrap(coordinator.menu.item(withTitle: "智能模型服务")?.submenu)
        var ttsMenu = try XCTUnwrap(coordinator.menu.item(withTitle: "TTS 模型")?.submenu)
        var translationMenu = try XCTUnwrap(coordinator.menu.item(withTitle: "翻译模型")?.submenu)
        let disabledLLMItem = try XCTUnwrap(llmMenu.item(withTitle: "Disabled · gpt-disabled") as NSMenuItem?)
        let disabledKokoroItem = try XCTUnwrap(ttsMenu.item(withTitle: "Kokoro TTS（未下载）") as NSMenuItem?)

        XCTAssertEqual(llmMenu.item(withTitle: "Primary · gpt-primary")?.state, .on)
        XCTAssertFalse(disabledLLMItem.isEnabled)
        XCTAssertEqual(ttsMenu.item(withTitle: "Kokoro TTS（未下载）")?.state, .on)
        XCTAssertFalse(disabledKokoroItem.isEnabled)
        XCTAssertEqual(translationMenu.item(withTitle: "系统默认")?.state, .on)

        defaultProviderID = "disabled"
        kokoroInstalled = true
        coordinator.menuWillOpen(coordinator.menu)

        llmMenu = try XCTUnwrap(coordinator.menu.item(withTitle: "智能模型服务")?.submenu)
        ttsMenu = try XCTUnwrap(coordinator.menu.item(withTitle: "TTS 模型")?.submenu)
        translationMenu = try XCTUnwrap(coordinator.menu.item(withTitle: "翻译模型")?.submenu)
        let enabledKokoroItem = try XCTUnwrap(ttsMenu.item(withTitle: "Kokoro TTS") as NSMenuItem?)

        XCTAssertEqual(llmMenu.item(withTitle: "Primary · gpt-primary")?.state, .off)
        XCTAssertEqual(llmMenu.item(withTitle: "Disabled · gpt-disabled")?.state, .on)
        XCTAssertTrue(enabledKokoroItem.isEnabled)
        XCTAssertEqual(ttsMenu.item(withTitle: "Kokoro TTS")?.state, .on)
        XCTAssertNotNil(translationMenu.item(withTitle: "Soniqo MADLAD（未下载）"))
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

        let translationMenu = try XCTUnwrap(coordinator.menu.item(withTitle: "翻译模型")?.submenu)
        let llmItem = try XCTUnwrap(translationMenu.item(withTitle: "智能模型配置（未配置）"))

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

        let languageMenu = try XCTUnwrap(coordinator.menu.item(withTitle: "语言 / Language")?.submenu)
        let englishItem = try XCTUnwrap(
            languageMenu.item(withTitle: "English")
        )
        let chineseItem = try XCTUnwrap(
            languageMenu.item(withTitle: "简体中文")
        )
        let appleItem = try XCTUnwrap(
            coordinator.menu.item(withTitle: "语音识别模型")?.submenu?.item(withTitle: "系统自带")
        )
        let qwenItem = try XCTUnwrap(
            coordinator.menu.item(withTitle: "语音识别模型")?.submenu?.item(withTitle: "Qwen3-ASR 0.6B")
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
        XCTAssertFalse(try XCTUnwrap(coordinator.menu.item(withTitle: "正在进行智能纠错")).isHidden)
        XCTAssertEqual(enabledChecks, 2)
        XCTAssertEqual(selectedChecks, 2)
        XCTAssertEqual(menuWillOpenCount, 1)
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
        isDefault: Bool
    ) -> LLMProviderRecord {
        LLMProviderRecord(
            id: id,
            displayName: displayName,
            providerType: "openaiCompatible",
            baseURL: "https://api.example.com/v1",
            defaultModel: model,
            apiKeyRef: "llm-provider-\(id)",
            temperature: 0.2,
            timeoutSeconds: 30,
            enabled: enabled,
            isDefault: isDefault,
            lastHealthStatus: nil,
            lastHealthMessage: nil,
            lastLatencyMS: nil,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }
}
