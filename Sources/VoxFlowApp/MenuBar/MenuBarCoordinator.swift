import AppKit

@MainActor
struct MenuBarActions {
    let selectLanguage: (RecognitionLanguage) -> Void
    let selectASRMenuOption: (ASRMenuModel) -> Void
    let selectLLMProvider: (String) -> Void
    let selectCapabilityModel: (CapabilityModelKind, String) -> Void
    let openWorkbench: () -> Void
    let requestSelectionAction: () -> Void
    let openSettings: () -> Void
    let openGitHub: () -> Void
    let checkPermissions: () -> Void
    let quit: () -> Void
    let menuWillOpen: () -> Void

    static let noop = MenuBarActions(
        selectLanguage: { _ in },
        selectASRMenuOption: { _ in },
        selectLLMProvider: { _ in },
        selectCapabilityModel: { _, _ in },
        openWorkbench: {},
        requestSelectionAction: {},
        openSettings: {},
        openGitHub: {},
        checkPermissions: {},
        quit: {},
        menuWillOpen: {}
    )

    init(
        selectLanguage: @escaping (RecognitionLanguage) -> Void,
        selectASRMenuOption: @escaping (ASRMenuModel) -> Void,
        selectLLMProvider: @escaping (String) -> Void = { _ in },
        selectCapabilityModel: @escaping (CapabilityModelKind, String) -> Void = { _, _ in },
        openWorkbench: @escaping () -> Void,
        requestSelectionAction: @escaping () -> Void = {},
        openSettings: @escaping () -> Void,
        openGitHub: @escaping () -> Void,
        checkPermissions: @escaping () -> Void,
        quit: @escaping () -> Void,
        menuWillOpen: @escaping () -> Void
    ) {
        self.selectLanguage = selectLanguage
        self.selectASRMenuOption = selectASRMenuOption
        self.selectLLMProvider = selectLLMProvider
        self.selectCapabilityModel = selectCapabilityModel
        self.openWorkbench = openWorkbench
        self.requestSelectionAction = requestSelectionAction
        self.openSettings = openSettings
        self.openGitHub = openGitHub
        self.checkPermissions = checkPermissions
        self.quit = quit
        self.menuWillOpen = menuWillOpen
    }
}

@MainActor
final class MenuBarCoordinator: NSObject, NSMenuDelegate {
    let menu = NSMenu()

    private var languageMenuItems: [NSMenuItem] = []
    private var asrEngineMenuItems: [NSMenuItem] = []
    private let llmProviderMenu = NSMenu()
    private let ttsModelMenu = NSMenu()
    private let translationModelMenu = NSMenu()
    private var refiningMenuItem: NSMenuItem!
    private let asrOptions: [ASRMenuModel]
    private let currentLanguage: () -> RecognitionLanguage
    private let isASRMenuOptionEnabled: (ASRMenuModel) -> Bool
    private let isASRMenuOptionSelected: (ASRMenuModel) -> Bool
    private let actions: MenuBarActions
    private let llmProviders: () -> [LLMProviderRecord]
    private let selectedLLMProviderID: () -> String?
    private let capabilityModels: (CapabilityModelKind) -> [CapabilityModelDescriptor]
    private let selectedCapabilityModelID: (CapabilityModelKind) -> String
    private let isCapabilityModelEnabled: (CapabilityModelDescriptor) -> Bool

    init(
        asrOptions: [ASRMenuModel],
        currentLanguage: @escaping () -> RecognitionLanguage,
        isASRMenuOptionEnabled: @escaping (ASRMenuModel) -> Bool,
        isASRMenuOptionSelected: @escaping (ASRMenuModel) -> Bool,
        actions: MenuBarActions,
        llmProviders: @escaping () -> [LLMProviderRecord] = { [] },
        selectedLLMProviderID: @escaping () -> String? = { nil },
        capabilityModels: @escaping (CapabilityModelKind) -> [CapabilityModelDescriptor] = {
            CapabilityModelCatalog.models(for: $0)
        },
        selectedCapabilityModelID: @escaping (CapabilityModelKind) -> String = {
            CapabilityModelViewModel.selectedModelID(kind: $0)
        },
        isCapabilityModelEnabled: @escaping (CapabilityModelDescriptor) -> Bool = { $0.isInstalled }
    ) {
        self.asrOptions = asrOptions
        self.currentLanguage = currentLanguage
        self.isASRMenuOptionEnabled = isASRMenuOptionEnabled
        self.isASRMenuOptionSelected = isASRMenuOptionSelected
        self.actions = actions
        self.llmProviders = llmProviders
        self.selectedLLMProviderID = selectedLLMProviderID
        self.capabilityModels = capabilityModels
        self.selectedCapabilityModelID = selectedCapabilityModelID
        self.isCapabilityModelEnabled = isCapabilityModelEnabled
        super.init()
        AppLogger.general.debug("MenuBarCoordinator init with \(asrOptions.count) ASR options")
        buildMenu()
    }

    func attach(to statusItem: NSStatusItem) {
        statusItem.menu = menu
        statusItem.button?.target = nil
        statusItem.button?.action = nil
    }

    func menuWillOpen(_ menu: NSMenu) {
        AppLogger.general.debug("MenuBarCoordinator menuWillOpen")
        refreshDynamicState()
        actions.menuWillOpen()
    }

    func setRefiningStatusVisible(_ isVisible: Bool) {
        refiningMenuItem?.isHidden = !isVisible
    }

    private func buildMenu() {
        AppLogger.general.debug("MenuBarCoordinator buildMenu")
        menu.autoenablesItems = false
        menu.delegate = self

        addLanguageMenu()
        menu.addItem(.separator())
        addASREngineMenu()
        addLLMProviderMenu()
        addCapabilityModelMenu(title: "TTS 模型", menu: ttsModelMenu, kind: .tts)
        addCapabilityModelMenu(title: "翻译模型", menu: translationModelMenu, kind: .translation)
        menu.addItem(.separator())
        addCommandItems()
    }

    private func addLanguageMenu() {
        AppLogger.general.debug("MenuBarCoordinator addLanguageMenu")
        let languageMenu = NSMenu()
        languageMenu.autoenablesItems = false
        for language in RecognitionLanguage.allCases {
            let item = NSMenuItem(
                title: language.displayName,
                action: #selector(selectLanguage(_:)),
                keyEquivalent: ""
            )
            item.representedObject = language
            item.target = self
            item.state = language == currentLanguage() ? .on : .off
            languageMenu.addItem(item)
            languageMenuItems.append(item)
        }

        let languageParentItem = NSMenuItem()
        languageParentItem.title = "语言 / Language"
        languageParentItem.submenu = languageMenu
        menu.addItem(languageParentItem)
    }

    private func addASREngineMenu() {
        AppLogger.general.debug("MenuBarCoordinator addASREngineMenu")
        let asrMenu = NSMenu()
        asrMenu.autoenablesItems = false

        for option in asrOptions {
            let item = NSMenuItem(
                title: option.title,
                action: #selector(selectASREngine(_:)),
                keyEquivalent: ""
            )
            item.representedObject = option
            item.target = self
            item.isEnabled = isASRMenuOptionEnabled(option)
            item.state = isASRMenuOptionSelected(option) ? .on : .off
            asrMenu.addItem(item)
            asrEngineMenuItems.append(item)
        }

        let asrParentItem = NSMenuItem()
        asrParentItem.title = "语音识别模型"
        asrParentItem.submenu = asrMenu
        menu.addItem(asrParentItem)
    }

    private func addLLMProviderMenu() {
        AppLogger.general.debug("MenuBarCoordinator addLLMProviderMenu")
        llmProviderMenu.autoenablesItems = false
        rebuildLLMProviderMenu()

        let llmParentItem = NSMenuItem()
        llmParentItem.title = "智能模型服务"
        llmParentItem.submenu = llmProviderMenu
        menu.addItem(llmParentItem)
    }

    private func addCapabilityModelMenu(title: String, menu: NSMenu, kind: CapabilityModelKind) {
        AppLogger.general.debug("MenuBarCoordinator addCapabilityModelMenu title=\(title)")
        menu.autoenablesItems = false
        rebuildCapabilityModelMenu(menu, kind: kind)

        let parentItem = NSMenuItem()
        parentItem.title = title
        parentItem.submenu = menu
        self.menu.addItem(parentItem)
    }

    private func addCommandItems() {
        AppLogger.general.debug("MenuBarCoordinator addCommandItems")
        menu.addItem(makeItem(title: "打开工作台", action: #selector(openWorkbench(_:))))
        menu.addItem(makeItem(title: "划词动作", action: #selector(requestSelectionAction(_:))))
        menu.addItem(makeItem(title: "设置", action: #selector(openSettings(_:))))
        menu.addItem(makeItem(title: "GitHub", action: #selector(openGitHub(_:))))
        menu.addItem(.separator())

        refiningMenuItem = NSMenuItem(title: "正在进行智能纠错", action: nil, keyEquivalent: "")
        refiningMenuItem.isHidden = true
        menu.addItem(refiningMenuItem)

        menu.addItem(.separator())
        menu.addItem(makeItem(title: "检查权限", action: #selector(checkPermissions(_:))))
        menu.addItem(.separator())
        menu.addItem(makeItem(title: "退出码上写", action: #selector(quit(_:)), keyEquivalent: "q"))
    }

    private func makeItem(
        title: String,
        action: Selector,
        keyEquivalent: String = ""
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        return item
    }

    private func refreshDynamicState(includeASRState: Bool = true) {
        AppLogger.general.debug("MenuBarCoordinator refreshDynamicState includeASRState=\(includeASRState)")
        let language = currentLanguage()
        for item in languageMenuItems {
            item.state = (item.representedObject as? RecognitionLanguage) == language ? .on : .off
        }
        if includeASRState {
            for item in asrEngineMenuItems {
                guard let option = item.representedObject as? ASRMenuModel else { continue }
                item.isEnabled = isASRMenuOptionEnabled(option)
                item.state = isASRMenuOptionSelected(option) ? .on : .off
            }
        }
        rebuildLLMProviderMenu()
        rebuildCapabilityModelMenu(ttsModelMenu, kind: .tts)
        rebuildCapabilityModelMenu(translationModelMenu, kind: .translation)
    }

    private func rebuildLLMProviderMenu() {
        AppLogger.general.debug("MenuBarCoordinator rebuildLLMProviderMenu")
        llmProviderMenu.removeAllItems()
        let providers = llmProviders()
        guard !providers.isEmpty else {
            let item = NSMenuItem(title: "未配置智能模型服务", action: nil, keyEquivalent: "")
            item.isEnabled = false
            llmProviderMenu.addItem(item)
            return
        }
        let selectedID = selectedLLMProviderID()
        for provider in providers {
            let item = NSMenuItem(
                title: "\(provider.displayName) · \(provider.defaultModel)",
                action: #selector(selectLLMProvider(_:)),
                keyEquivalent: ""
            )
            item.representedObject = provider.id
            item.target = self
            item.isEnabled = provider.enabled
            item.state = provider.id == selectedID ? .on : .off
            llmProviderMenu.addItem(item)
        }
    }

    private func rebuildCapabilityModelMenu(_ menu: NSMenu, kind: CapabilityModelKind) {
        AppLogger.general.debug("MenuBarCoordinator rebuildCapabilityModelMenu kind=\(kind)")
        menu.removeAllItems()
        let selectedID = selectedCapabilityModelID(kind)
        for model in capabilityModels(kind) {
            let enabled = isCapabilityModelEnabled(model)
            let item = NSMenuItem(
                title: enabled ? model.displayName : "\(model.displayName)（未下载）",
                action: #selector(selectCapabilityModel(_:)),
                keyEquivalent: ""
            )
            item.representedObject = CapabilityMenuSelection(kind: kind, modelID: model.id)
            item.target = self
            item.isEnabled = enabled
            item.state = model.id == selectedID ? .on : .off
            menu.addItem(item)
        }
    }

    @objc private func selectLanguage(_ sender: NSMenuItem) {
        guard let language = sender.representedObject as? RecognitionLanguage else { return }
        AppLogger.general.info("MenuBarCoordinator selectLanguage=\(language.rawValue)")
        actions.selectLanguage(language)
        refreshDynamicState()
    }

    @objc private func selectASREngine(_ sender: NSMenuItem) {
        guard let option = sender.representedObject as? ASRMenuModel else { return }
        AppLogger.general.info("MenuBarCoordinator selectASREngine=\(option.title)")
        actions.selectASRMenuOption(option)
        refreshDynamicState()
    }

    @objc private func selectLLMProvider(_ sender: NSMenuItem) {
        guard let providerID = sender.representedObject as? String else { return }
        AppLogger.general.info("MenuBarCoordinator selectLLMProvider id=\(providerID)")
        actions.selectLLMProvider(providerID)
        refreshDynamicState()
    }

    @objc private func selectCapabilityModel(_ sender: NSMenuItem) {
        guard let selection = sender.representedObject as? CapabilityMenuSelection else { return }
        AppLogger.general.info("MenuBarCoordinator selectCapabilityModel kind=\(selection.kind) id=\(selection.modelID)")
        actions.selectCapabilityModel(selection.kind, selection.modelID)
        refreshDynamicState()
    }

    @objc private func openWorkbench(_ sender: NSMenuItem) {
        AppLogger.general.info("MenuBarCoordinator openWorkbench")
        actions.openWorkbench()
    }

    @objc private func requestSelectionAction(_ sender: NSMenuItem) {
        AppLogger.general.info("MenuBarCoordinator requestSelectionAction")
        actions.requestSelectionAction()
    }

    @objc private func openSettings(_ sender: NSMenuItem) {
        AppLogger.general.info("MenuBarCoordinator openSettings")
        actions.openSettings()
    }

    @objc private func openGitHub(_ sender: NSMenuItem) {
        AppLogger.general.info("MenuBarCoordinator openGitHub")
        actions.openGitHub()
    }

    @objc private func checkPermissions(_ sender: NSMenuItem) {
        AppLogger.general.info("MenuBarCoordinator checkPermissions")
        actions.checkPermissions()
    }

    @objc private func quit(_ sender: NSMenuItem) {
        AppLogger.general.info("MenuBarCoordinator quit")
        actions.quit()
    }
}

private struct CapabilityMenuSelection {
    let kind: CapabilityModelKind
    let modelID: String
}
