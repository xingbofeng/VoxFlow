import XCTest
@testable import VoxFlowApp

@MainActor
final class RecordingAudioFeedbackControllerTests: XCTestCase {
    func testRecordingPlaysStartBeforeMutingAndCompletionRestoresBeforeSound() {
        var events: [String] = []
        let controller = RecordingAudioFeedbackController(
            soundFeedbackEnabled: { true },
            muteWhileRecordingEnabled: { true },
            capsLockIndicatorEnabled: { false },
            playSound: { events.append("sound:\($0)") },
            setMuted: { muted in events.append(muted ? "mute" : "restore") },
            setCapsLockIndicatorActive: { active in events.append(active ? "caps:on" : "caps:off") }
        )

        controller.handle(.recording)
        controller.handle(.idle)

        XCTAssertEqual(events, ["sound:start", "mute", "restore", "sound:complete"])
    }

    func testDisabledOptionsDoNotPlayOrMute() {
        var events: [String] = []
        let controller = RecordingAudioFeedbackController(
            soundFeedbackEnabled: { false },
            muteWhileRecordingEnabled: { false },
            capsLockIndicatorEnabled: { false },
            playSound: { events.append("sound:\($0)") },
            setMuted: { muted in events.append(muted ? "mute" : "restore") },
            setCapsLockIndicatorActive: { active in events.append(active ? "caps:on" : "caps:off") }
        )

        controller.handle(.recording)
        controller.handle(.failed("test"))

        XCTAssertTrue(events.isEmpty)
    }

    func testFailureRestoresAudioBeforeErrorSound() {
        var events: [String] = []
        let controller = RecordingAudioFeedbackController(
            soundFeedbackEnabled: { true },
            muteWhileRecordingEnabled: { true },
            capsLockIndicatorEnabled: { false },
            playSound: { events.append("sound:\($0)") },
            setMuted: { muted in events.append(muted ? "mute" : "restore") },
            setCapsLockIndicatorActive: { active in events.append(active ? "caps:on" : "caps:off") }
        )

        controller.handle(.recording)
        events.removeAll()
        controller.handle(.failed("test"))

        XCTAssertEqual(events, ["restore", "sound:error"])
    }

    func testCapsLockIndicatorTurnsOnDuringRecordingAndTurnsOffWhenRecordingEnds() {
        var events: [String] = []
        let controller = RecordingAudioFeedbackController(
            soundFeedbackEnabled: { false },
            muteWhileRecordingEnabled: { false },
            capsLockIndicatorEnabled: { true },
            playSound: { events.append("sound:\($0)") },
            setMuted: { muted in events.append(muted ? "mute" : "restore") },
            setCapsLockIndicatorActive: { active in events.append(active ? "caps:on" : "caps:off") }
        )

        controller.handle(.recording)
        controller.handle(.processing)

        XCTAssertEqual(events, ["caps:on", "caps:off"])
    }

    func testCapsLockIndicatorDoesNotRepeatStartForSameRecordingSession() {
        var events: [String] = []
        let controller = RecordingAudioFeedbackController(
            soundFeedbackEnabled: { false },
            muteWhileRecordingEnabled: { false },
            capsLockIndicatorEnabled: { true },
            playSound: { events.append("sound:\($0)") },
            setMuted: { muted in events.append(muted ? "mute" : "restore") },
            setCapsLockIndicatorActive: { active in events.append(active ? "caps:on" : "caps:off") }
        )

        controller.handle(.recording)
        controller.handle(.recording)
        controller.handle(.idle)

        XCTAssertEqual(events, ["caps:on", "caps:off"])
    }
}
