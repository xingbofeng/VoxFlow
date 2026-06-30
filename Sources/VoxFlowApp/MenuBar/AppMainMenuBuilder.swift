import AppKit

enum AppMainMenuBuilder {
    private static let logger = AppLogger.general

    @MainActor
    static func makeMainMenu() -> NSMenu {
        logger.debug("AppMainMenuBuilder makeMainMenu start")
        let aboutTitle = L10n.localize("menu.main.about", comment: "About menu title")
        let checkForUpdatesTitle = L10n.localize("menu.main.check_updates", comment: "Check for updates menu title")
        let openWorkbenchTitle = L10n.localize("menu.main.open_workbench", comment: "Open workbench menu title")
        let settingsTitle = L10n.localize("menu.main.settings", comment: "Settings menu title")
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
        let actionsMenuTitle = L10n.localize("menu.main.actions", comment: "Actions menu title")
        let openPaletteTitle = L10n.localize("menu.main.open_palette", comment: "Open palette menu title")
        let screenshotOCRTitle = L10n.localize("menu.main.screenshot_ocr", comment: "Screenshot OCR menu title")
        let selectionActionTitle = L10n.localize("menu.main.selection_action", comment: "Selection action menu title")
        let windowMenuTitle = L10n.localize("menu.main.window", comment: "Window menu title")
        let closeWindowTitle = L10n.localize("menu.main.close_window", comment: "Close window menu title")
        let minimizeTitle = L10n.localize("menu.main.minimize", comment: "Minimize window menu title")
        let zoomTitle = L10n.localize("menu.main.zoom", comment: "Zoom window menu title")
        let bringAllToFrontTitle = L10n.localize("menu.main.bring_all_to_front", comment: "Bring all windows to front menu title")
        let checkPermissionsTitle = L10n.localize("menu.main.check_permissions", comment: "Check permissions menu title")
        let helpMenuTitle = L10n.localize("menu.main.help", comment: "Help menu title")
        let githubTitle = L10n.localize("menu.main.github", comment: "GitHub menu title")
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
            withTitle: openWorkbenchTitle,
            action: #selector(AppDelegate.openWorkbenchFromMainMenu(_:)),
            keyEquivalent: ""
        )
        applicationMenu.addItem(
            withTitle: settingsTitle,
            action: #selector(AppDelegate.openSettingsFromMainMenu(_:)),
            keyEquivalent: ","
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

        let actionsMenuItem = NSMenuItem()
        let actionsMenu = NSMenu(title: actionsMenuTitle)
        actionsMenu.addItem(
            withTitle: openPaletteTitle,
            action: #selector(AppDelegate.showPaletteFromMainMenu(_:)),
            keyEquivalent: ""
        )
        actionsMenu.addItem(
            withTitle: screenshotOCRTitle,
            action: #selector(AppDelegate.performScreenshotOCRFromMenu(_:)),
            keyEquivalent: ""
        )
        actionsMenu.addItem(
            withTitle: selectionActionTitle,
            action: #selector(AppDelegate.requestSelectionActionFromMainMenu(_:)),
            keyEquivalent: ""
        )
        actionsMenu.addItem(.separator())
        actionsMenu.addItem(
            withTitle: MainMenuDictationActionPresentation.title(isRecording: false),
            action: #selector(AppDelegate.startDictationFromMainMenu(_:)),
            keyEquivalent: ""
        )
        actionsMenuItem.submenu = actionsMenu
        mainMenu.addItem(actionsMenuItem)

        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: windowMenuTitle)
        windowMenu.addItem(
            withTitle: closeWindowTitle,
            action: #selector(NSWindow.performClose(_:)),
            keyEquivalent: "w"
        )
        windowMenu.addItem(
            withTitle: minimizeTitle,
            action: #selector(NSWindow.performMiniaturize(_:)),
            keyEquivalent: "m"
        )
        windowMenu.addItem(
            withTitle: zoomTitle,
            action: #selector(NSWindow.performZoom(_:)),
            keyEquivalent: ""
        )
        windowMenu.addItem(.separator())
        windowMenu.addItem(
            withTitle: bringAllToFrontTitle,
            action: #selector(NSApplication.arrangeInFront(_:)),
            keyEquivalent: ""
        )
        windowMenu.addItem(.separator())
        windowMenu.addItem(
            withTitle: openWorkbenchTitle,
            action: #selector(AppDelegate.openWorkbenchFromMainMenu(_:)),
            keyEquivalent: ""
        )
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)

        let helpMenuItem = NSMenuItem()
        let helpMenu = NSMenu(title: helpMenuTitle)
        helpMenu.addItem(
            withTitle: githubTitle,
            action: #selector(AppDelegate.openGitHubFromMainMenu(_:)),
            keyEquivalent: ""
        )
        helpMenu.addItem(.separator())
        helpMenu.addItem(
            withTitle: checkPermissionsTitle,
            action: #selector(AppDelegate.checkPermissionsFromMainMenu(_:)),
            keyEquivalent: ""
        )
        helpMenu.addItem(
            withTitle: checkForUpdatesTitle,
            action: #selector(AppDelegate.checkForUpdates(_:)),
            keyEquivalent: ""
        )
        helpMenuItem.submenu = helpMenu
        mainMenu.addItem(helpMenuItem)

        logger.debug("AppMainMenuBuilder makeMainMenu completed items=\(mainMenu.items.count)")
        return mainMenu
    }
}

enum MainMenuDictationActionPresentation {
    static func title(isRecording: Bool) -> String {
        L10n.localize(
            isRecording ? "menu.main.stop_dictation" : "menu.main.start_dictation",
            comment: "Dictation action menu title"
        )
    }
}
