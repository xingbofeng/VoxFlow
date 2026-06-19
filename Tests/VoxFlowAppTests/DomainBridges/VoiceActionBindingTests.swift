import XCTest
@testable import VoxFlowApp

final class VoiceActionBindingTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var manager: ShortcutManager!

    override func setUp() {
        super.setUp()
        suiteName = "com.voiceinput.tests.action.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        manager = ShortcutManager(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        manager = nil
        suiteName = nil
        super.tearDown()
    }

    func testDictationBindingMigratedFromExistingConfig() {
        // Simulate a legacy config: only ShortcutKeyCode is set
        defaults.set(Int(54), forKey: "ShortcutKeyCode")
        defaults.removeObject(forKey: "ShortcutManager_MigrationDone_V2")

        let migrated = ShortcutManager(defaults: defaults)

        XCTAssertEqual(migrated.dictationShortcutKeyCode, 54)
        XCTAssertEqual(migrated.shortcutKeyCode, 54)
    }

    func testAgentComposeBindingDefaultsToRightOption() {
        XCTAssertEqual(manager.shortcutKeyCode(for: .agentCompose), 61)
    }

    func testAgentComposeDefaultDoesNotConflictWithExistingDictationOptionBinding() {
        manager.dictationShortcutKeyCode = 61

        XCTAssertNil(manager.shortcutKeyCode(for: .agentCompose))
        XCTAssertFalse(manager.hasConflict())
    }

    func testConflictingBindingsBlocked() {
        manager.dictationShortcutKeyCode = 42
        manager.agentComposeShortcutKeyCode = 42

        XCTAssertTrue(manager.hasConflict())

        let conflicts = manager.conflictingActions()
        XCTAssertEqual(conflicts.count, 1)
        XCTAssertEqual(conflicts[0].0, .dictation)
        XCTAssertEqual(conflicts[0].1, .agentCompose)
    }

    func testInitClearsAgentComposeWhenPersistedBindingsConflict() {
        defaults.set(Int(54), forKey: "DictationShortcutKeyCode")
        defaults.set(Int(54), forKey: "AgentComposeShortcutKeyCode")
        defaults.set(true, forKey: "ShortcutManager_MigrationDone_V2")

        let normalized = ShortcutManager(defaults: defaults)

        XCTAssertEqual(normalized.shortcutKeyCode(for: .dictation), 54)
        XCTAssertEqual(normalized.shortcutKeyCode(for: .agentCompose), 61)
        XCTAssertFalse(normalized.hasConflict())
    }

    func testExistingDictationBindingPreservedAfterMigration() {
        // Set legacy shortcut
        defaults.set(Int(63), forKey: "ShortcutKeyCode")
        defaults.removeObject(forKey: "ShortcutManager_MigrationDone_V2")

        let migrated = ShortcutManager(defaults: defaults)

        // Legacy binding preserved
        XCTAssertEqual(migrated.shortcutKeyCode, 63)
        XCTAssertEqual(migrated.dictationShortcutKeyCode, 63)

        // Updating through new API updates both
        migrated.dictationShortcutKeyCode = 48
        XCTAssertEqual(migrated.shortcutKeyCode, 48)
        XCTAssertEqual(migrated.dictationShortcutKeyCode, 48)
    }

    func testAgentComposeUsesDefaultShortcutWhenUnbound() {
        XCTAssertNil(manager.agentComposeShortcutKeyCode)
        XCTAssertEqual(manager.shortcutKeyCode(for: .agentCompose), 61)

        // Dictation should always have a value
        XCTAssertNotNil(manager.shortcutKeyCode(for: .dictation))
    }

    func testAgentComposeCanBeExplicitlyDisabled() {
        manager.agentComposeShortcutKeyCode = nil

        XCTAssertNil(manager.agentComposeShortcutKeyCode)
        XCTAssertNil(manager.shortcutKeyCode(for: .agentCompose))
    }
}
