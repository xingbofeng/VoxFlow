import XCTest
@testable import VoxFlowApp

final class ShortcutManagerAskAITests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var sut: ShortcutManager!

    override func setUp() {
        super.setUp()
        suiteName = "com.voiceinput.tests.askai.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        sut = ShortcutManager(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        sut = nil
        suiteName = nil
        super.tearDown()
    }

    func testDefaultSelectionAskAIShortcutIsCommandShiftP() {
        XCTAssertEqual(
            sut.shortcutKeyCode(for: .selectionAskAI),
            ShortcutManager.defaultSelectionAskAIShortcutKeyCode
        )
        XCTAssertEqual(
            ShortcutManager.baseKeyCode(for: ShortcutManager.defaultSelectionAskAIShortcutKeyCode),
            HotKeyShortcutRouting.pKeyCode
        )
        XCTAssertEqual(
            ShortcutManager.modifierMask(for: ShortcutManager.defaultSelectionAskAIShortcutKeyCode),
            ShortcutManager.commandModifierMask | ShortcutManager.shiftModifierMask
        )
    }

    func testPKeyCodeIs0x23() {
        XCTAssertEqual(HotKeyShortcutRouting.pKeyCode, 0x23)
    }

    func testSelectionAskAIShortcutCanBeChangedAndCleared() {
        let custom = ShortcutManager.encodeShortcut(
            keyCode: 0x10,
            modifierMask: ShortcutManager.commandModifierMask | ShortcutManager.optionModifierMask
        )

        sut.setShortcutKeyCode(custom, for: .selectionAskAI)

        XCTAssertEqual(sut.shortcutKeyCode(for: .selectionAskAI), custom)

        sut.setShortcutKeyCode(nil, for: .selectionAskAI)

        XCTAssertNil(sut.shortcutKeyCode(for: .selectionAskAI))
    }

    func testSelectionAskAIShortcutDisabledFlagPersists() {
        sut.setShortcutKeyCode(nil, for: .selectionAskAI)

        XCTAssertNil(sut.shortcutKeyCode(for: .selectionAskAI))

        // Re-instantiate to verify persistence
        let restored = ShortcutManager(defaults: defaults)
        XCTAssertNil(restored.shortcutKeyCode(for: .selectionAskAI))

        // Re-enabling restores default
        restored.setShortcutKeyCode(
            ShortcutManager.defaultSelectionAskAIShortcutKeyCode,
            for: .selectionAskAI
        )
        XCTAssertEqual(
            restored.shortcutKeyCode(for: .selectionAskAI),
            ShortcutManager.defaultSelectionAskAIShortcutKeyCode
        )
    }

    func testResetToDefaultsRestoresSelectionAskAIShortcut() {
        sut.setShortcutKeyCode(nil, for: .selectionAskAI)
        XCTAssertNil(sut.shortcutKeyCode(for: .selectionAskAI))

        sut.resetToDefaults()

        XCTAssertEqual(
            sut.shortcutKeyCode(for: .selectionAskAI),
            ShortcutManager.defaultSelectionAskAIShortcutKeyCode
        )
    }

    func testSelectionAskAIRouteIsRoutedByHotKeyRouter() {
        XCTAssertEqual(
            HotKeyRouter.route(
                keyCode: HotKeyShortcutRouting.pKeyCode,
                flags: [.maskCommand, .maskShift],
                dictationKeyCode: 54,
                agentComposeKeyCode: ShortcutManager.defaultAgentComposeShortcutKeyCode,
                selectionAskAIKeyCode: ShortcutManager.defaultSelectionAskAIShortcutKeyCode
            ),
            .workflowShortcut(.selectionAskAI)
        )
    }

    func testSelectionAskAIDoesNotRouteWithOnlyCommandFlag() {
        XCTAssertNotEqual(
            HotKeyRouter.route(
                keyCode: HotKeyShortcutRouting.pKeyCode,
                flags: [.maskCommand],
                dictationKeyCode: 54,
                agentComposeKeyCode: ShortcutManager.defaultAgentComposeShortcutKeyCode,
                selectionAskAIKeyCode: ShortcutManager.defaultSelectionAskAIShortcutKeyCode
            ),
            .workflowShortcut(.selectionAskAI)
        )
    }

    func testWorkflowRoutingPolicyAllowsSelectionAskAIOnlyWhenIdle() {
        XCTAssertTrue(
            HotKeyWorkflowRoutingPolicy.shouldStartEphemeralWorkflow(
                .selectionAskAI,
                dictationState: .idle
            )
        )
        XCTAssertFalse(
            HotKeyWorkflowRoutingPolicy.shouldStartEphemeralWorkflow(
                .selectionAskAI,
                dictationState: .recording
            )
        )
    }
}
