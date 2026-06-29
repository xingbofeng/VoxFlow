import XCTest
@testable import VoxFlowApp

final class KnownApplicationRegistryTests: XCTestCase {
    func testRegistryContainsExpectedApps() {
        let registry = KnownApplicationRegistry.builtIn()

        XCTAssertNotNil(registry.lookup(bundleID: "com.tencent.xinWeChat"))
        XCTAssertNotNil(registry.lookup(bundleID: "com.apple.mail"))
        XCTAssertNotNil(registry.lookup(bundleID: "com.microsoft.VSCode"))
        XCTAssertNotNil(registry.lookup(bundleID: "com.apple.iWork.Pages"))
        XCTAssertNotNil(registry.lookup(bundleID: "com.apple.Safari"))
    }

    func testLookupByBundleID() {
        let registry = KnownApplicationRegistry.builtIn()

        let entry = registry.lookup(bundleID: "com.microsoft.VSCode")

        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.bundleID, "com.microsoft.VSCode")
        XCTAssertEqual(entry?.displayName, "VS Code")
        XCTAssertEqual(entry?.suggestedStyleID, "builtin.coding")
    }

    func testLookupCaseInsensitive() {
        let registry = KnownApplicationRegistry.builtIn()

        XCTAssertNotNil(registry.lookup(bundleID: "COM.MICROSOFT.VSCODE"))
        XCTAssertNotNil(registry.lookup(bundleID: "com.apple.safari"))
        XCTAssertNotNil(registry.lookup(bundleID: "COM.TENCENT.XINWECHAT"))
    }

    func testLookupMissReturnsNil() {
        let registry = KnownApplicationRegistry.builtIn()

        XCTAssertNil(registry.lookup(bundleID: "com.nonexistent.app"))
        XCTAssertNil(registry.lookup(bundleID: ""))
    }

    func testRegistryVersion() {
        let registry = KnownApplicationRegistry.builtIn()
        XCTAssertEqual(registry.version, 2)
    }

    func testTerminalMapsToCoding() {
        let registry = KnownApplicationRegistry.builtIn()
        XCTAssertEqual(registry.lookup(bundleID: "com.apple.Terminal")?.suggestedStyleID, "builtin.coding")
    }

    func testITermMapsToCoding() {
        let registry = KnownApplicationRegistry.builtIn()
        XCTAssertEqual(registry.lookup(bundleID: "com.googlecode.iterm2")?.suggestedStyleID, "builtin.coding")
    }

    func testGhosttyMapsToCoding() {
        let registry = KnownApplicationRegistry.builtIn()
        XCTAssertEqual(registry.lookup(bundleID: "dev.dirs.ghostty")?.suggestedStyleID, "builtin.coding")
    }

    func testChromeMapsToCasualBrowserStyle() {
        let registry = KnownApplicationRegistry.builtIn()
        XCTAssertEqual(registry.lookup(bundleID: "com.google.Chrome")?.suggestedStyleID, "builtin.casual")
    }

    func testVerifiedLocalApplicationsMapToExpectedStyles() {
        let registry = KnownApplicationRegistry.builtIn()
        let expected: [String: String] = [
            "com.openai.chat": "builtin.original",
            "com.anthropic.claudefordesktop": "builtin.original",
            "com.openai.codex": "builtin.coding",
            "com.aliyun.lingma.ide": "builtin.coding",
            "com.qoder.work.cn": "builtin.coding",
            "dev.kiro.desktop": "builtin.coding",
            "dev.zed.Zed": "builtin.coding",
            "ai.elementlabs.lmstudio": "builtin.coding",
            "com.postmanlabs.mac": "builtin.coding",
            "com.tinyapp.TablePlus": "builtin.coding",
            "com.mitchellh.ghostty": "builtin.coding",
            "com.raycast.macos": "builtin.casual",
            "com.tencent.meeting": "builtin.chat",
            "com.voxflow.app": "builtin.original",
        ]

        for (bundleID, styleID) in expected {
            XCTAssertEqual(
                registry.lookup(bundleID: bundleID)?.suggestedStyleID,
                styleID,
                "Unexpected style for \(bundleID)"
            )
        }

        XCTAssertNil(registry.lookup(bundleID: "com.example.unknown"))
    }
}
