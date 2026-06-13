import XCTest
@testable import VoiceInputApp

@MainActor
final class RecordingAudioFeedbackControllerTests: XCTestCase {
    func testRecordingPlaysStartBeforeMutingAndCompletionRestoresBeforeSound() {
        var events: [String] = []
        let controller = RecordingAudioFeedbackController(
            soundFeedbackEnabled: { true },
            muteWhileRecordingEnabled: { true },
            playSound: { events.append("sound:\($0)") },
            setMuted: { muted in events.append(muted ? "mute" : "restore") }
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
            playSound: { events.append("sound:\($0)") },
            setMuted: { muted in events.append(muted ? "mute" : "restore") }
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
            playSound: { events.append("sound:\($0)") },
            setMuted: { muted in events.append(muted ? "mute" : "restore") }
        )

        controller.handle(.recording)
        events.removeAll()
        controller.handle(.failed("test"))

        XCTAssertEqual(events, ["restore", "sound:error"])
    }
}
