import AppKit
import XCTest
@testable import VoxFlowApp

final class AppMainMenuBuilderTests: XCTestCase {
    @MainActor
    func testBuilderCreatesMainMenuSections() throws {
        let menu = AppMainMenuBuilder.makeMainMenu()
        XCTAssertEqual(menu.items.compactMap(\.submenu?.title), [
            "",
            mainMenuTitle("edit"),
            mainMenuTitle("actions"),
            mainMenuTitle("window"),
            mainMenuTitle("help"),
        ])
    }

    @MainActor
    func testBuilderCreatesApplicationMenuActions() throws {
        let menu = AppMainMenuBuilder.makeMainMenu()
        let aboutTitle = L10n.localize("menu.main.about")
        let checkForUpdatesTitle = L10n.localize("menu.main.check_updates")
        let openWorkbenchTitle = L10n.localize("menu.main.open_workbench")
        let settingsTitle = L10n.localize("menu.main.settings")
        let hideTitle = L10n.localize("menu.main.hide")
        let hideOthersTitle = L10n.localize("menu.main.hide_others")
        let quitTitle = L10n.localize("menu.main.quit")

        let applicationMenu = try XCTUnwrap(menu.items.first?.submenu)
        XCTAssertEqual(applicationMenu.items.map { $0.title }, [
            aboutTitle,
            checkForUpdatesTitle,
            "",
            openWorkbenchTitle,
            settingsTitle,
            "",
            hideTitle,
            hideOthersTitle,
            "",
            quitTitle,
        ])
        XCTAssertEqual(applicationMenu.items[0].action, #selector(NSApplication.orderFrontStandardAboutPanel(_:)))
        XCTAssertEqual(applicationMenu.items[1].action, #selector(AppDelegate.checkForUpdates(_:)))
        XCTAssertEqual(applicationMenu.items[3].action, Selector(("openWorkbenchFromMainMenu:")))
        XCTAssertEqual(applicationMenu.items[4].action, Selector(("openSettingsFromMainMenu:")))
        XCTAssertEqual(applicationMenu.items[4].keyEquivalent, ",")
        XCTAssertEqual(applicationMenu.items[4].keyEquivalentModifierMask, .command)
        XCTAssertEqual(applicationMenu.items[6].action, #selector(NSApplication.hide(_:)))
        XCTAssertEqual(applicationMenu.items[7].action, #selector(NSApplication.hideOtherApplications(_:)))
        XCTAssertEqual(
            applicationMenu.items[7].keyEquivalentModifierMask,
            NSEvent.ModifierFlags([.command, .option])
        )
        XCTAssertEqual(applicationMenu.items[9].action, #selector(NSApplication.terminate(_:)))
    }

    @MainActor
    func testBuilderCreatesStandardEditMenuOnly() throws {
        let menu = AppMainMenuBuilder.makeMainMenu()
        let editMenuTitle = L10n.localize("menu.main.edit")
        let undoTitle = L10n.localize("menu.main.undo")
        let redoTitle = L10n.localize("menu.main.redo")
        let cutTitle = L10n.localize("menu.main.cut")
        let copyTitle = L10n.localize("menu.main.copy")
        let pasteTitle = L10n.localize("menu.main.paste")
        let selectAllTitle = L10n.localize("menu.main.select_all")

        let editMenu = try XCTUnwrap(menu.items.dropFirst().first?.submenu)
        XCTAssertEqual(editMenu.title, editMenuTitle)
        XCTAssertEqual(editMenu.items.map { $0.title }, [
            undoTitle,
            redoTitle,
            "",
            cutTitle,
            copyTitle,
            pasteTitle,
            selectAllTitle,
        ])
        XCTAssertEqual(editMenu.items[0].action, Selector(("undo:")))
        XCTAssertEqual(editMenu.items[1].action, Selector(("redo:")))
        XCTAssertEqual(editMenu.items[3].action, #selector(NSText.cut(_:)))
        XCTAssertEqual(editMenu.items[4].action, #selector(NSText.copy(_:)))
        XCTAssertEqual(editMenu.items[5].action, #selector(NSText.paste(_:)))
        XCTAssertEqual(editMenu.items[6].action, #selector(NSText.selectAll(_:)))
        XCTAssertNil(editMenu.item(withTitle: mainMenuTitle("open_palette")))
        XCTAssertNil(editMenu.item(withTitle: mainMenuTitle("screenshot_ocr")))
    }

    @MainActor
    func testBuilderCreatesActionsMenuForExistingWorkflows() throws {
        let menu = AppMainMenuBuilder.makeMainMenu()
        let actionsMenu = try XCTUnwrap(menu.item(withSubmenuTitle: mainMenuTitle("actions"))?.submenu)

        XCTAssertEqual(actionsMenu.items.map(\.title), [
            mainMenuTitle("open_palette"),
            mainMenuTitle("screenshot_ocr"),
            mainMenuTitle("selection_action"),
            "",
            mainMenuTitle("start_dictation"),
        ])
        XCTAssertEqual(actionsMenu.items[0].action, Selector(("showPaletteFromMainMenu:")))
        XCTAssertEqual(actionsMenu.items[1].action, #selector(AppDelegate.performScreenshotOCRFromMenu(_:)))
        XCTAssertEqual(actionsMenu.items[2].action, Selector(("requestSelectionActionFromMainMenu:")))
        XCTAssertEqual(actionsMenu.items[4].action, Selector(("startDictationFromMainMenu:")))
    }

    @MainActor
    func testBuilderCreatesWindowDiagnosticsAndHelpMenus() throws {
        let menu = AppMainMenuBuilder.makeMainMenu()
        let windowMenu = try XCTUnwrap(menu.item(withSubmenuTitle: mainMenuTitle("window"))?.submenu)
        let helpMenu = try XCTUnwrap(menu.item(withSubmenuTitle: mainMenuTitle("help"))?.submenu)

        XCTAssertEqual(windowMenu.items.map(\.title), [
            mainMenuTitle("close_window"),
            mainMenuTitle("minimize"),
            mainMenuTitle("zoom"),
            "",
            mainMenuTitle("bring_all_to_front"),
            "",
            mainMenuTitle("open_workbench"),
        ])
        XCTAssertEqual(windowMenu.items[0].action, #selector(NSWindow.performClose(_:)))
        XCTAssertEqual(windowMenu.items[1].action, #selector(NSWindow.performMiniaturize(_:)))
        XCTAssertEqual(windowMenu.items[2].action, #selector(NSWindow.performZoom(_:)))
        XCTAssertEqual(windowMenu.items[4].action, #selector(NSApplication.arrangeInFront(_:)))
        XCTAssertEqual(windowMenu.items[6].action, Selector(("openWorkbenchFromMainMenu:")))

        XCTAssertNil(menu.item(withSubmenuTitle: mainMenuTitle("diagnostics")))

        XCTAssertEqual(helpMenu.items.map(\.title), [
            mainMenuTitle("github"),
            "",
            mainMenuTitle("check_permissions"),
            mainMenuTitle("check_updates"),
        ])
        XCTAssertEqual(helpMenu.items[0].action, Selector(("openGitHubFromMainMenu:")))
        XCTAssertEqual(helpMenu.items[2].action, Selector(("checkPermissionsFromMainMenu:")))
        XCTAssertEqual(helpMenu.items[3].action, #selector(AppDelegate.checkForUpdates(_:)))
    }

    @MainActor
    func testDictationMenuTitleChangesWithRecordingState() {
        XCTAssertEqual(
            MainMenuDictationActionPresentation.title(isRecording: false),
            mainMenuTitle("start_dictation")
        )
        XCTAssertEqual(
            MainMenuDictationActionPresentation.title(isRecording: true),
            mainMenuTitle("stop_dictation")
        )
    }

    @MainActor
    func testBuilderDoesNotDuplicateStatusMenuDynamicSwitchers() {
        let menu = AppMainMenuBuilder.makeMainMenu()
        let allTitles = menu.allMenuItemTitles

        XCTAssertFalse(allTitles.contains(L10n.localize("menu.status.language", comment: "")))
        XCTAssertFalse(allTitles.contains(L10n.localize("menu.status.asr_model", comment: "")))
        XCTAssertFalse(allTitles.contains(L10n.localize("menu.status.llm_service", comment: "")))
        XCTAssertFalse(allTitles.contains(L10n.localize("menu.status.tts_model", comment: "")))
        XCTAssertFalse(allTitles.contains(L10n.localize("menu.status.translation_model", comment: "")))
    }

    private func mainMenuTitle(_ suffix: String) -> String {
        L10n.localize("menu.main.\(suffix)", comment: "")
    }
}

private extension NSMenu {
    func item(withSubmenuTitle title: String) -> NSMenuItem? {
        items.first { $0.submenu?.title == title }
    }

    var allMenuItemTitles: [String] {
        items.flatMap { item -> [String] in
            let submenuTitles = item.submenu?.allMenuItemTitles ?? []
            return [item.title] + submenuTitles
        }
    }
}
