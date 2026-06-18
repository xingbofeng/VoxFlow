import AppKit
import XCTest
@testable import VoxFlowApp

final class AppMainMenuBuilderTests: XCTestCase {
    @MainActor
    func testBuilderCreatesApplicationAndEditMenus() throws {
        let menu = AppMainMenuBuilder.makeMainMenu()

        XCTAssertEqual(menu.items.count, 2)

        let applicationMenu = try XCTUnwrap(menu.items.first?.submenu)
        XCTAssertEqual(applicationMenu.items.map { $0.title }, [
            "关于随声写",
            "",
            "隐藏随声写",
            "隐藏其他",
            "",
            "退出随声写",
        ])
        XCTAssertEqual(applicationMenu.items[0].action, #selector(NSApplication.orderFrontStandardAboutPanel(_:)))
        XCTAssertEqual(applicationMenu.items[2].action, #selector(NSApplication.hide(_:)))
        XCTAssertEqual(applicationMenu.items[3].action, #selector(NSApplication.hideOtherApplications(_:)))
        XCTAssertEqual(
            applicationMenu.items[3].keyEquivalentModifierMask,
            NSEvent.ModifierFlags([.command, .option])
        )
        XCTAssertEqual(applicationMenu.items[5].action, #selector(NSApplication.terminate(_:)))

        let editMenu = try XCTUnwrap(menu.items.dropFirst().first?.submenu)
        XCTAssertEqual(editMenu.title, "编辑")
        XCTAssertEqual(editMenu.items.map { $0.title }, [
            "撤销",
            "重做",
            "",
            "剪切",
            "复制",
            "粘贴",
            "全选",
        ])
        XCTAssertEqual(editMenu.items[0].action, Selector(("undo:")))
        XCTAssertEqual(editMenu.items[1].action, Selector(("redo:")))
        XCTAssertEqual(editMenu.items[3].action, #selector(NSText.cut(_:)))
        XCTAssertEqual(editMenu.items[4].action, #selector(NSText.copy(_:)))
        XCTAssertEqual(editMenu.items[5].action, #selector(NSText.paste(_:)))
        XCTAssertEqual(editMenu.items[6].action, #selector(NSText.selectAll(_:)))
    }
}
