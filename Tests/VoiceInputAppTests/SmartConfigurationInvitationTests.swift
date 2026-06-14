import XCTest
@testable import VoiceInputApp

final class SmartConfigurationInvitationTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var manager: SmartConfigInvitationManager!

    override func setUp() {
        super.setUp()
        suiteName = "com.voiceinput.tests.invitation.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        manager = SmartConfigInvitationManager(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        manager = nil
        suiteName = nil
        super.tearDown()
    }

    func testInvitationPendingBeforeFirstLLMSuccess() {
        XCTAssertEqual(manager.state, .pending)
    }

    func testInvitationShownAfterFirstLLMSuccess() {
        manager.notifyLLMSuccess()
        XCTAssertEqual(manager.state, .shown)
    }

    func testInvitationNotRepeatedAfterDismissed() {
        manager.notifyLLMSuccess()
        XCTAssertEqual(manager.state, .shown)

        manager.markDismissed()
        XCTAssertEqual(manager.state, .dismissed)

        // Trying to notify again should not change state
        manager.notifyLLMSuccess()
        XCTAssertEqual(manager.state, .dismissed)
    }

    func testInvitationNotRepeatedAfterStarted() {
        manager.notifyLLMSuccess()
        XCTAssertEqual(manager.state, .shown)

        manager.markStarted()
        XCTAssertEqual(manager.state, .started)

        // Trying to notify again should not change state
        manager.notifyLLMSuccess()
        XCTAssertEqual(manager.state, .started)
    }
}
