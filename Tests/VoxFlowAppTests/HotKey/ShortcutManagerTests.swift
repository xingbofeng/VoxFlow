import XCTest
@testable import VoxFlowApp

final class ShortcutManagerTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var sut: ShortcutManager!

    override func setUp() {
        super.setUp()
        suiteName = "com.voiceinput.tests.\(UUID().uuidString)"
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

    // MARK: - Key Code

    func testDefaultKeyCodeIsRightCommand() {
        XCTAssertEqual(sut.shortcutKeyCode, 54)
    }

    func testDefaultAgentComposeKeyCodeIsRightOption() {
        XCTAssertEqual(sut.shortcutKeyCode(for: .agentCompose), 61)
    }

    func testSupportedVoiceShortcutKeyCodesAreModifierOnly() {
        XCTAssertTrue(ShortcutManager.isSupportedVoiceShortcutKeyCode(54))
        XCTAssertTrue(ShortcutManager.isSupportedVoiceShortcutKeyCode(61))
        XCTAssertFalse(ShortcutManager.isSupportedVoiceShortcutKeyCode(0x09))
    }

    func testSetAndGetCustomKeyCode() {
        sut.shortcutKeyCode = 63
        XCTAssertEqual(sut.shortcutKeyCode, 63)
    }

    // MARK: - Long Press Threshold

    func testDefaultLongPressThresholdIs500ms() {
        XCTAssertEqual(sut.longPressThreshold, 0.5, accuracy: 0.001)
    }

    func testSetAndGetLongPressThreshold() {
        sut.longPressThreshold = 1.0
        XCTAssertEqual(sut.longPressThreshold, 1.0, accuracy: 0.001)
    }

    // MARK: - Short Press Behavior

    func testDefaultShortPressBehaviorIsToggleListening() {
        XCTAssertEqual(sut.shortPressBehavior, .toggleListening)
    }
}
