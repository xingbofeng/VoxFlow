import AppKit
import XCTest
@testable import VoxFlowApp

final class AppMainMenuBuilderTests: XCTestCase {
    @MainActor
    func testBuilderCreatesApplicationAndEditMenus() throws {
        let menu = AppMainMenuBuilder.makeMainMenu()
        let aboutTitle = L10n.localize("menu.main.about")
        let checkForUpdatesTitle = L10n.localize("menu.main.check_updates")
        let hideTitle = L10n.localize("menu.main.hide")
        let hideOthersTitle = L10n.localize("menu.main.hide_others")
        let quitTitle = L10n.localize("menu.main.quit")
        let editMenuTitle = L10n.localize("menu.main.edit")
        let undoTitle = L10n.localize("menu.main.undo")
        let redoTitle = L10n.localize("menu.main.redo")
        let cutTitle = L10n.localize("menu.main.cut")
        let copyTitle = L10n.localize("menu.main.copy")
        let pasteTitle = L10n.localize("menu.main.paste")
        let selectAllTitle = L10n.localize("menu.main.select_all")

        XCTAssertEqual(menu.items.count, 2)

        let applicationMenu = try XCTUnwrap(menu.items.first?.submenu)
        XCTAssertEqual(applicationMenu.items.map { $0.title }, [
            aboutTitle,
            checkForUpdatesTitle,
            "",
            hideTitle,
            hideOthersTitle,
            "",
            quitTitle,
        ])
        XCTAssertEqual(applicationMenu.items[0].action, #selector(NSApplication.orderFrontStandardAboutPanel(_:)))
        XCTAssertEqual(applicationMenu.items[1].action, #selector(AppDelegate.checkForUpdates(_:)))
        XCTAssertEqual(applicationMenu.items[3].action, #selector(NSApplication.hide(_:)))
        XCTAssertEqual(applicationMenu.items[4].action, #selector(NSApplication.hideOtherApplications(_:)))
        XCTAssertEqual(
            applicationMenu.items[4].keyEquivalentModifierMask,
            NSEvent.ModifierFlags([.command, .option])
        )
        XCTAssertEqual(applicationMenu.items[6].action, #selector(NSApplication.terminate(_:)))

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
    }
}
