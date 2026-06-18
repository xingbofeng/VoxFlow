import AppKit

@MainActor
struct MenuBarActions {
    let selectLanguage: (RecognitionLanguage) -> Void
    let selectASRMenuOption: (ASRMenuModel) -> Void
    let openWorkbench: () -> Void
    let openSettings: () -> Void
    let openGitHub: () -> Void
    let checkPermissions: () -> Void
    let quit: () -> Void
    let menuWillOpen: () -> Void

    static let noop = MenuBarActions(
        selectLanguage: { _ in },
        selectASRMenuOption: { _ in },
        openWorkbench: {},
        openSettings: {},
        openGitHub: {},
        checkPermissions: {},
        quit: {},
        menuWillOpen: {}
    )
}

@MainActor
final class MenuBarCoordinator: NSObject, NSMenuDelegate {
    let menu = NSMenu()

    private var languageMenuItems: [NSMenuItem] = []
    private var asrEngineMenuItems: [NSMenuItem] = []
    private var refiningMenuItem: NSMenuItem!
    private let asrOptions: [ASRMenuModel]
    private let currentLanguage: () -> RecognitionLanguage
    private let isASRMenuOptionEnabled: (ASRMenuModel) -> Bool
    private let isASRMenuOptionSelected: (ASRMenuModel) -> Bool
    private let actions: MenuBarActions

    init(
        asrOptions: [ASRMenuModel],
        currentLanguage: @escaping () -> RecognitionLanguage,
        isASRMenuOptionEnabled: @escaping (ASRMenuModel) -> Bool,
        isASRMenuOptionSelected: @escaping (ASRMenuModel) -> Bool,
        actions: MenuBarActions
    ) {
        self.asrOptions = asrOptions
        self.currentLanguage = currentLanguage
        self.isASRMenuOptionEnabled = isASRMenuOptionEnabled
        self.isASRMenuOptionSelected = isASRMenuOptionSelected
        self.actions = actions
        super.init()
        buildMenu()
    }

    func attach(to statusItem: NSStatusItem) {
        statusItem.menu = menu
        statusItem.button?.target = nil
        statusItem.button?.action = nil
    }

    func menuWillOpen(_ menu: NSMenu) {
        refreshDynamicState(includeASRState: false)
        actions.menuWillOpen()
    }

    func setRefiningStatusVisible(_ isVisible: Bool) {
        refiningMenuItem?.isHidden = !isVisible
    }

    private func buildMenu() {
        menu.autoenablesItems = false
        menu.delegate = self

        addLanguageMenu()
        menu.addItem(.separator())
        addASREngineMenu()
        menu.addItem(.separator())
        addCommandItems()
    }

    private func addLanguageMenu() {
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
        asrParentItem.title = "语音识别引擎"
        asrParentItem.submenu = asrMenu
        menu.addItem(asrParentItem)
    }

    private func addCommandItems() {
        menu.addItem(makeItem(title: "打开工作台", action: #selector(openWorkbench(_:))))
        menu.addItem(makeItem(title: "设置", action: #selector(openSettings(_:))))
        menu.addItem(makeItem(title: "GitHub", action: #selector(openGitHub(_:))))
        menu.addItem(.separator())

        refiningMenuItem = NSMenuItem(title: "正在 LLM 纠错", action: nil, keyEquivalent: "")
        refiningMenuItem.isHidden = true
        menu.addItem(refiningMenuItem)

        menu.addItem(.separator())
        menu.addItem(makeItem(title: "检查权限", action: #selector(checkPermissions(_:))))
        menu.addItem(.separator())
        menu.addItem(makeItem(title: "退出随声写", action: #selector(quit(_:)), keyEquivalent: "q"))
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
        let language = currentLanguage()
        for item in languageMenuItems {
            item.state = (item.representedObject as? RecognitionLanguage) == language ? .on : .off
        }
        guard includeASRState else { return }
        for item in asrEngineMenuItems {
            guard let option = item.representedObject as? ASRMenuModel else { continue }
            item.isEnabled = isASRMenuOptionEnabled(option)
            item.state = isASRMenuOptionSelected(option) ? .on : .off
        }
    }

    @objc private func selectLanguage(_ sender: NSMenuItem) {
        guard let language = sender.representedObject as? RecognitionLanguage else { return }
        actions.selectLanguage(language)
        refreshDynamicState()
    }

    @objc private func selectASREngine(_ sender: NSMenuItem) {
        guard let option = sender.representedObject as? ASRMenuModel else { return }
        actions.selectASRMenuOption(option)
        refreshDynamicState()
    }

    @objc private func openWorkbench(_ sender: NSMenuItem) {
        actions.openWorkbench()
    }

    @objc private func openSettings(_ sender: NSMenuItem) {
        actions.openSettings()
    }

    @objc private func openGitHub(_ sender: NSMenuItem) {
        actions.openGitHub()
    }

    @objc private func checkPermissions(_ sender: NSMenuItem) {
        actions.checkPermissions()
    }

    @objc private func quit(_ sender: NSMenuItem) {
        actions.quit()
    }
}
