import VoxFlowVoiceCorrection
import XCTest
@testable import VoxFlowApp

@MainActor
final class FocusedTextObservationTests: XCTestCase {
    func testRecapturesTheSameFocusedElement() {
        let baseline = observation(identity: "element-1", value: "Please use teh")
        let edited = observation(identity: "element-1", value: "Please use the")
        let observer = FakeFocusedTextObserver()
        observer.captureResult = baseline
        observer.recaptureResult = edited
        let tracker = FocusedTextObservationTracker(observer: observer)

        XCTAssertEqual(tracker.captureBaseline(), baseline)
        XCTAssertEqual(tracker.recapture(matching: baseline), edited)
        XCTAssertEqual(observer.recaptureBaselines, [baseline])
    }

    func testCancelsWhenFocusChanges() {
        let baseline = observation(identity: "element-1", value: "teh")
        let observer = FakeFocusedTextObserver()
        observer.recaptureResult = observation(identity: "element-2", value: "the")

        XCTAssertNil(FocusedTextObservationTracker(observer: observer).recapture(matching: baseline))
    }

    func testCancelsWhenValueIsUnreadable() {
        let baseline = observation(identity: "element-1", value: "teh")
        let observer = FakeFocusedTextObserver()
        observer.captureResult = nil
        observer.recaptureResult = nil
        let tracker = FocusedTextObservationTracker(observer: observer)

        XCTAssertNil(tracker.captureBaseline())
        XCTAssertNil(tracker.recapture(matching: baseline))
    }

    func testCancelsForSecureFields() {
        let secure = observation(identity: "password", value: "", isSecureField: true)
        let observer = FakeFocusedTextObserver()
        observer.captureResult = secure
        observer.recaptureResult = secure
        let tracker = FocusedTextObservationTracker(observer: observer)

        XCTAssertNil(tracker.captureBaseline())
        XCTAssertNil(tracker.recapture(matching: secure))
    }

    func testFakeClockSupportsDefaultTwoFiveTenSecondPollSchedule() async {
        let clock = FakeCorrectionObservationClock()

        for offset in CorrectionObservationPollSchedule.defaultOffsets {
            await clock.sleep(for: offset)
        }

        let sleeps = await clock.sleeps
        XCTAssertEqual(sleeps, [.seconds(2), .seconds(5), .seconds(10)])
    }

    func testAccessibilityObserverCapsElementCache() throws {
        let source = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Sources/VoxFlowApp/VoiceCorrection/Observation/AccessibilityFocusedTextObserver.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("maximumCachedElements"))
        XCTAssertTrue(source.contains("pruneElementCacheIfNeeded"))
    }

    private func observation(
        identity: String,
        value: String,
        isSecureField: Bool = false
    ) -> FocusedTextObservation {
        FocusedTextObservation(
            elementIdentity: identity,
            value: value,
            selectedRange: CorrectionTextRange(location: value.utf16.count, length: 0),
            bundleIdentifier: "com.apple.TextEdit",
            isSecureField: isSecureField
        )
    }
}
