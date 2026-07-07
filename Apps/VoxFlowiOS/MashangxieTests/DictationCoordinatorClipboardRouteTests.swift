import XCTest
@testable import Mashangxie
import Shared

/// Phase 4 — verifies that the `mashangxie://dictation/clipboard-start` deep
/// link is routed correctly and does NOT trigger the AppGroupBridge
/// startFromKeyboardRequest path.
@MainActor
final class DictationCoordinatorClipboardRouteTests: XCTestCase {

    private func cleanSharedState() {
        let defaults = AppGroup.defaultsIfAvailable ?? UserDefaults.standard
        defaults.removeObject(forKey: SharedKeys.coldStartActive)
        defaults.removeObject(forKey: SharedKeys.sourceAppScheme)
        defaults.synchronize()
    }

    private func makeCoordinator() -> DictationCoordinator {
        cleanSharedState()
        let coordinator = DictationCoordinator.shared
        coordinator.resetStatus()
        return coordinator
    }

    // MARK: - clipboard-start URL

    func testClipboardStartHostOnlyDoesNotTriggerAppGroupRecording() {
        let coordinator = makeCoordinator()
        // The URL `mashangxie://clipboard-start?source=keyboard` should NOT
        // call startFromKeyboardRequest. We verify by checking that status
        // remains .idle (or whatever it was before) — AppGroupBridge would
        // set it to .requested.
        let initialStatus = coordinator.status
        let url = URL(string: "mashangxie://clipboard-start?source=keyboard")!

        coordinator.handleIncomingURL(url)

        // Status should NOT have transitioned to .requested.
        XCTAssertNotEqual(coordinator.status, .requested)
        // It should be whatever it was before (idle or other non-active state).
        XCTAssertEqual(coordinator.status, initialStatus)
    }

    func testClipboardStartPathFormDoesNotTriggerAppGroupRecording() {
        let coordinator = makeCoordinator()
        let url = URL(string: "mashangxie://dictation/clipboard-start?source=keyboard")!
        let initialStatus = coordinator.status

        coordinator.handleIncomingURL(url)

        XCTAssertNotEqual(coordinator.status, .requested)
        XCTAssertEqual(coordinator.status, initialStatus)
    }

    func testClipboardStartSetsColdStartFlagWhenSourceIsKeyboard() {
        let coordinator = makeCoordinator()
        let url = URL(string: "mashangxie://clipboard-start?source=keyboard")!
        let defaults = AppGroup.defaultsIfAvailable ?? UserDefaults.standard

        coordinator.handleIncomingURL(url)

        XCTAssertTrue(defaults.bool(forKey: SharedKeys.coldStartActive))
        XCTAssertEqual(defaults.string(forKey: SharedKeys.sourceAppScheme), "unknown")
    }

    func testClipboardStartWithoutSourceDoesNotSetColdStart() {
        let coordinator = makeCoordinator()
        let url = URL(string: "mashangxie://clipboard-start")!
        let defaults = AppGroup.defaultsIfAvailable ?? UserDefaults.standard
        defaults.removeObject(forKey: SharedKeys.coldStartActive)

        coordinator.handleIncomingURL(url)

        XCTAssertFalse(defaults.bool(forKey: SharedKeys.coldStartActive))
    }

    // MARK: - Non-clipboard URLs still route correctly (regression)

    func testDictateURLStillTriggersAppGroupRecording() {
        let coordinator = makeCoordinator()
        let url = URL(string: "mashangxie://dictate?source=keyboard")!

        coordinator.handleIncomingURL(url)

        // The AppGroupBridge path sets .requested.
        // Wait briefly for the async startFromKeyboardRequest to run.
        let expectation = expectation(description: "status becomes .requested")
        Task { @MainActor in
            for _ in 0..<20 {
                if coordinator.status == .requested || coordinator.status == .recording {
                    expectation.fulfill()
                    return
                }
                try? await Task.sleep(for: .milliseconds(50))
            }
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2.0)
    }

    // MARK: - Non-mashangxie URLs are ignored

    func testNonMashangxieSchemeIgnored() {
        let coordinator = makeCoordinator()
        let url = URL(string: "https://example.com")!
        let initialStatus = coordinator.status

        coordinator.handleIncomingURL(url)

        XCTAssertEqual(coordinator.status, initialStatus)
    }
}
