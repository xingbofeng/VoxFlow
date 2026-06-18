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
        var openedWorkbench = false
        var openedSettings = false
        var openedGitHub = false
        var checkedPermissions = false
        var quitRequested = false
        let coordinator = MenuBarCoordinator(
            asrOptions: [asrOption],
            currentLanguage: { .simplifiedChinese },
            isASRMenuOptionEnabled: { _ in true },
            isASRMenuOptionSelected: { _ in false },
            actions: MenuBarActions(
                selectLanguage: { selectedLanguage = $0 },
                selectASRMenuOption: { selectedASR = $0 },
                openWorkbench: { openedWorkbench = true },
                openSettings: { openedSettings = true },
                openGitHub: { openedGitHub = true },
                checkPermissions: { checkedPermissions = true },
                quit: { quitRequested = true },
                menuWillOpen: {}
            )
        )

        let languageItem = try XCTUnwrap(
            coordinator.menu.item(withTitle: "语言 / Language")?.submenu?.item(withTitle: "English")
        )
        let asrItem = try XCTUnwrap(
            coordinator.menu.item(withTitle: "语音识别引擎")?.submenu?.item(withTitle: "系统自带")
        )

        sendAction(for: languageItem)
        sendAction(for: asrItem)
        sendAction(for: try XCTUnwrap(coordinator.menu.item(withTitle: "打开工作台")))
        sendAction(for: try XCTUnwrap(coordinator.menu.item(withTitle: "设置")))
        sendAction(for: try XCTUnwrap(coordinator.menu.item(withTitle: "GitHub")))
        sendAction(for: try XCTUnwrap(coordinator.menu.item(withTitle: "检查权限")))
        sendAction(for: try XCTUnwrap(coordinator.menu.item(withTitle: "退出随声写")))

        XCTAssertEqual(selectedLanguage, .english)
        XCTAssertEqual(selectedASR, asrOption)
        XCTAssertTrue(openedWorkbench)
        XCTAssertTrue(openedSettings)
        XCTAssertTrue(openedGitHub)
        XCTAssertTrue(checkedPermissions)
        XCTAssertTrue(quitRequested)
    }

    func testCoordinatorRefreshesLanguageAndRefiningStateWhenMenuOpensWithoutASRChecks() throws {
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
            coordinator.menu.item(withTitle: "语音识别引擎")?.submenu?.item(withTitle: "系统自带")
        )
        let qwenItem = try XCTUnwrap(
            coordinator.menu.item(withTitle: "语音识别引擎")?.submenu?.item(withTitle: "Qwen3-ASR 0.6B")
        )

        XCTAssertEqual(englishItem.state, .off)
        XCTAssertEqual(chineseItem.state, .on)
        XCTAssertNotNil(languageMenu.item(withTitle: "繁體中文"))
        XCTAssertNotNil(languageMenu.item(withTitle: "日本語"))
        XCTAssertNotNil(languageMenu.item(withTitle: "한국어"))
        XCTAssertEqual(appleItem.state, .off)
        XCTAssertTrue(appleItem.isEnabled)
        XCTAssertEqual(qwenItem.state, .on)
        XCTAssertFalse(qwenItem.isEnabled)
        XCTAssertFalse(try XCTUnwrap(coordinator.menu.item(withTitle: "正在 LLM 纠错")).isHidden)
        XCTAssertEqual(enabledChecks, 0)
        XCTAssertEqual(selectedChecks, 0)
        XCTAssertEqual(menuWillOpenCount, 1)
    }

    private func sendAction(for item: NSMenuItem) {
        guard let action = item.action else {
            XCTFail("Expected menu item \(item.title) to have an action.")
            return
        }
        XCTAssertTrue(NSApplication.shared.sendAction(action, to: item.target, from: item))
    }
}
