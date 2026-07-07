import XCTest
@testable import Shared

/// Phase 3.5 — verifies that the keyboard's mic tap path correctly branches
/// between AppGroupBridge and ClipboardBridge based on BridgeMode + AppGroup
/// availability.
///
/// Also Phase 5 — verifies pending state read-once, insert, dismiss.
///
/// Note: the KeyboardTests target compiles Keyboard/ sources directly, so
/// `KeyboardState` and `PendingClipboardDictation` are available without
/// an explicit import.
@MainActor
final class KeyboardStateClipboardBridgeTests: XCTestCase {

    private var state: KeyboardState!

    override func setUp() async throws {
        try await super.setUp()
        // Reset BridgeMode to a known state before each test.
        let key = BridgeModeStore.key
        UserDefaults.standard.removeObject(forKey: key)
        AppGroup.defaultsIfAvailable?.removeObject(forKey: key)
        // Clear pending clipboard keys.
        for pendingKey in [
            SharedKeys.pendingClipboardLaunched,
            SharedKeys.pendingClipboardText,
            SharedKeys.pendingClipboardFailureReason,
            SharedKeys.pendingClipboardTimestamp
        ] {
            UserDefaults.standard.removeObject(forKey: pendingKey)
        }
        ClipboardBridgeEventLog.shared.clear()

        state = KeyboardState.shared
        if let owner = state.activeControllerID {
            state.registerControllerDisappearance(controllerID: owner)
        }
        state.openURL = nil
        state.pasteboardStringProvider = { nil }
        state.forceResetToIdle()
        state.resetMicDebounceForTesting()
        state.clearPendingClipboardForTesting()
    }

    override func tearDown() async throws {
        if let owner = state.activeControllerID {
            state.registerControllerDisappearance(controllerID: owner)
        }
        state.openURL = nil
        state.pasteboardStringProvider = { nil }
        state.forceResetToIdle()
        state.resetMicDebounceForTesting()
        state.clearPendingClipboardForTesting()
        let key = BridgeModeStore.key
        UserDefaults.standard.removeObject(forKey: key)
        AppGroup.defaultsIfAvailable?.removeObject(forKey: key)
        UserDefaults.standard.removeObject(forKey: SharedKeys.pendingClipboardFailureReason)
        try await super.tearDown()
    }

    // MARK: - ClipboardBridge mic tap

    func testClipboardModeOpensClipboardStartDeepLinkAndSetsPending() async throws {
        BridgeModeStore.write(.clipboard)

        let openedURL = expectation(description: "Deep link URL opened")
        var capturedURL: URL?
        state.openURL = { url in
            capturedURL = url
            openedURL.fulfill()
        }

        state.startRecording()

        await fulfillment(of: [openedURL], timeout: 1.0)

        XCTAssertEqual(capturedURL?.scheme, "mashangxie")
        XCTAssertEqual(capturedURL?.host, "dictation")
        XCTAssertEqual(capturedURL?.path, "/clipboard-start")
        let queryItems = URLComponents(url: capturedURL!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertTrue(queryItems.contains(where: { $0.name == "source" && $0.value == "keyboard" }))

        // Pending state should be set.
        XCTAssertTrue(state.pendingClipboard.launched)
        XCTAssertFalse(state.pendingClipboard.didAttemptPasteboardRead)

        // Status should remain .idle — ClipboardBridge does NOT trigger the
        // AppGroup recording overlay.
        XCTAssertEqual(state.dictationStatus, .idle)

        // Diagnostic event should be recorded.
        let events = ClipboardBridgeEventLog.shared.snapshot()
        XCTAssertTrue(events.contains(where: { $0.kind == .deepLinkOpened }))
    }

    func testClipboardModeDoesNotPostDarwinStartRecordingNotification() async throws {
        BridgeModeStore.write(.clipboard)

        // The AppGroupBridge path posts DarwinNotificationName.startRecording.
        // We can't directly observe Darwin notifications here, but we can verify
        // the dictationStatus stays .idle (AppGroupBridge would set it to .requested).
        let openedURL = expectation(description: "Deep link URL opened")
        state.openURL = { _ in openedURL.fulfill() }

        state.startRecording()

        await fulfillment(of: [openedURL], timeout: 1.0)
        XCTAssertEqual(state.dictationStatus, .idle)
    }

    // MARK: - AppGroupBridge mic tap (regression — must still work)

    func testAppGroupModeKeepsOriginalDarwinFallbackURL() async throws {
        BridgeModeStore.write(.appGroup)

        let openedURL = expectation(description: "AppGroup fallback URL opened")
        var capturedURL: URL?
        state.openURL = { url in
            capturedURL = url
            openedURL.fulfill()
        }

        state.startRecording()

        await fulfillment(of: [openedURL], timeout: 1.5)

        // AppGroupBridge uses the original mashangxie://dictate?source=keyboard URL.
        XCTAssertEqual(capturedURL?.absoluteString, "mashangxie://dictate?source=keyboard")

        // AppGroupBridge sets .requested status.
        XCTAssertEqual(state.dictationStatus, .requested)

        // No pending clipboard state.
        XCTAssertFalse(state.pendingClipboard.launched)
    }

    // MARK: - Pending state restore

    func testPendingStateRestoredFromLocalUserDefaultsOnInit() {
        // Simulate: keyboard was killed after launching clipboard-start,
        // pending state persisted in standard defaults.
        UserDefaults.standard.set(true, forKey: SharedKeys.pendingClipboardLaunched)
        UserDefaults.standard.set("restored pending text", forKey: SharedKeys.pendingClipboardText)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: SharedKeys.pendingClipboardTimestamp)
        UserDefaults.standard.synchronize()

        // Create a fresh state — simulates the keyboard process restarting.
        // KeyboardState is a singleton, so we test the restore method directly.
        state.restorePendingClipboardIfPresentForTesting()

        XCTAssertTrue(state.pendingClipboard.launched)
        XCTAssertEqual(state.pendingClipboard.fullText, "restored pending text")
        XCTAssertEqual(state.pendingClipboard.previewText, KeyboardState.middleTruncatedPreview("restored pending text"))
    }

    func testPendingFailureRestoredFromLocalUserDefaultsOnInit() {
        UserDefaults.standard.set(true, forKey: SharedKeys.pendingClipboardLaunched)
        UserDefaults.standard.set(
            ClipboardReadFailureReason.fullAccessRequired.rawValue,
            forKey: SharedKeys.pendingClipboardFailureReason
        )
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: SharedKeys.pendingClipboardTimestamp)
        UserDefaults.standard.synchronize()

        state.restorePendingClipboardIfPresentForTesting()

        XCTAssertTrue(state.pendingClipboard.launched)
        XCTAssertTrue(state.pendingClipboard.didAttemptPasteboardRead)
        XCTAssertNil(state.pendingClipboard.fullText)
        XCTAssertEqual(state.pendingClipboard.readFailureReason, .fullAccessRequired)
    }

    func testStalePendingStateOlderThan5MinutesDiscarded() {
        let staleTimestamp = Date().timeIntervalSince1970 - 400  // > 5 minutes
        UserDefaults.standard.set(true, forKey: SharedKeys.pendingClipboardLaunched)
        UserDefaults.standard.set("stale", forKey: SharedKeys.pendingClipboardText)
        UserDefaults.standard.set(staleTimestamp, forKey: SharedKeys.pendingClipboardTimestamp)
        UserDefaults.standard.synchronize()

        state.restorePendingClipboardIfPresentForTesting()

        XCTAssertFalse(state.pendingClipboard.launched)
        XCTAssertNil(state.pendingClipboard.fullText)
    }

    // MARK: - Middle truncation

    func testMiddleTruncatedPreviewShortTextReturnedAsIs() {
        XCTAssertEqual(KeyboardState.middleTruncatedPreview("短文本"), "短文本")
        XCTAssertEqual(KeyboardState.middleTruncatedPreview("hello"), "hello")
    }

    func testMiddleTruncatedPreviewLongTextTruncatedWithEllipsis() {
        let long = String(repeating: "字", count: 30)
        let preview = KeyboardState.middleTruncatedPreview(long)
        XCTAssertTrue(preview.contains("…"))
        XCTAssertLessThan(preview.count, long.count)
        // Should start with the first 6 chars and end with the last 6.
        XCTAssertTrue(preview.hasPrefix(String(repeating: "字", count: 6)))
        XCTAssertTrue(preview.hasSuffix(String(repeating: "字", count: 6)))
    }

    func testMiddleTruncatedPreviewReplacesNewlinesWithSpaces() {
        let multiLine = "line1\nline2\nline3"
        let preview = KeyboardState.middleTruncatedPreview(multiLine)
        XCTAssertFalse(preview.contains("\n"))
    }

    // MARK: - Dismiss

    func testDismissPendingClearsStateWithoutInserting() {
        // Manually set pending state.
        state.setPendingClipboardForTesting(
            .init(
                launched: true,
                didAttemptPasteboardRead: true,
                previewText: "preview",
                fullText: "full text",
                readFailureReason: nil,
                dismissed: false
            )
        )

        state.dismissPendingAndClear()

        XCTAssertFalse(state.pendingClipboard.launched)
        XCTAssertNil(state.pendingClipboard.fullText)

        // Diagnostic event recorded.
        let events = ClipboardBridgeEventLog.shared.snapshot()
        XCTAssertTrue(events.contains(where: { $0.kind == .dismissed }))
    }

    func testEmptyPasteboardReadKeepsPendingForRetry() {
        state.setPendingClipboardForTesting(
            .init(
                launched: true,
                didAttemptPasteboardRead: false,
                previewText: nil,
                fullText: nil,
                readFailureReason: nil,
                dismissed: false
            )
        )
        state.pasteboardStringProvider = { nil }

        state.registerControllerAppearance(controllerID: "clipboard-retry-test")

        XCTAssertTrue(state.pendingClipboard.launched)
        XCTAssertNil(state.pendingClipboard.fullText)
        XCTAssertFalse(state.pendingClipboard.didAttemptPasteboardRead)
    }

    func testSecondPasteboardReadCanCaptureLateClipboardText() {
        state.setPendingClipboardForTesting(
            .init(
                launched: true,
                didAttemptPasteboardRead: false,
                previewText: nil,
                fullText: nil,
                readFailureReason: nil,
                dismissed: false
            )
        )
        var values: [String?] = [nil, "  late clipboard text  "]
        state.pasteboardStringProvider = {
            values.removeFirst()
        }

        state.readPasteboardOnceIfPending()
        XCTAssertNil(state.pendingClipboard.fullText)

        state.readPasteboardOnceIfPending()

        XCTAssertEqual(state.pendingClipboard.fullText, "late clipboard text")
        XCTAssertEqual(
            state.pendingClipboard.previewText,
            KeyboardState.middleTruncatedPreview("late clipboard text")
        )
        XCTAssertTrue(state.pendingClipboard.didAttemptPasteboardRead)
    }
}
