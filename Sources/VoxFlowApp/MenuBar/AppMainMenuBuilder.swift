import AppKit

enum AppMainMenuBuilder {
    private static let logger = AppLogger.general

    @MainActor
    static func makeMainMenu() -> NSMenu {
        logger.debug("AppMainMenuBuilder makeMainMenu start")
        let aboutTitle = L10n.localize("menu.main.about", comment: "About menu title")
        let checkForUpdatesTitle = L10n.localize("menu.main.check_updates", comment: "Check for updates menu title")
        let hideTitle = L10n.localize("menu.main.hide", comment: "Hide menu title")
        let hideOthersTitle = L10n.localize("menu.main.hide_others", comment: "Hide Other Applications menu title")
        let quitTitle = L10n.localize("menu.main.quit", comment: "Quit menu title")
        let editMenuTitle = L10n.localize("menu.main.edit", comment: "Edit menu title")
        let undoTitle = L10n.localize("menu.main.undo", comment: "Undo menu title")
        let redoTitle = L10n.localize("menu.main.redo", comment: "Redo menu title")
        let cutTitle = L10n.localize("menu.main.cut", comment: "Cut menu title")
        let copyTitle = L10n.localize("menu.main.copy", comment: "Copy menu title")
        let pasteTitle = L10n.localize("menu.main.paste", comment: "Paste menu title")
        let selectAllTitle = L10n.localize("menu.main.select_all", comment: "Select All menu title")
        let mainMenu = NSMenu()

        let applicationMenuItem = NSMenuItem()
        let applicationMenu = NSMenu()
        applicationMenu.addItem(
            withTitle: aboutTitle,
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        )
        applicationMenu.addItem(
            withTitle: checkForUpdatesTitle,
            action: #selector(AppDelegate.checkForUpdates(_:)),
            keyEquivalent: ""
        )
        applicationMenu.addItem(.separator())
        applicationMenu.addItem(
            withTitle: hideTitle,
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h"
        )
        applicationMenu.addItem(
            withTitle: hideOthersTitle,
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h"
        ).keyEquivalentModifierMask = [.command, .option]
        applicationMenu.addItem(.separator())
        applicationMenu.addItem(
            withTitle: quitTitle,
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        applicationMenuItem.submenu = applicationMenu
        mainMenu.addItem(applicationMenuItem)

        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: editMenuTitle)
        editMenu.addItem(withTitle: undoTitle, action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: redoTitle, action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: cutTitle, action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: copyTitle, action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: pasteTitle, action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: selectAllTitle, action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        logger.debug("AppMainMenuBuilder makeMainMenu completed items=\(mainMenu.items.count)")
        return mainMenu
    }
}
