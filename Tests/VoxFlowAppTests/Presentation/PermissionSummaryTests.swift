import XCTest
@testable import VoxFlowApp

final class PermissionSummaryTests: XCTestCase {
    func testQwen3StillShowsActualAppleSpeechRecognitionPermissionState() {
        XCTAssertEqual(
            PermissionSummary.speechRecognitionStatus(
                engineType: .qwen3,
                speechPermission: .denied
            ),
            L10n.localize("permission.status.denied")
        )
        XCTAssertEqual(
            PermissionSummary.speechRecognitionStatus(
                engineType: .qwen3,
                speechPermission: .granted
            ),
            L10n.localize("permission.status.granted")
        )
    }

    func testAppleSpeechShowsSpeechRecognitionPermissionState() {
        XCTAssertEqual(
            PermissionSummary.speechRecognitionStatus(
                engineType: .apple,
                speechPermission: .denied
            ),
            L10n.localize("permission.status.denied")
        )
        XCTAssertEqual(
            PermissionSummary.speechRecognitionStatus(
                engineType: .apple,
                speechPermission: .granted
            ),
            L10n.localize("permission.status.granted")
        )
    }

    func testQwen3PermissionAlertOnlyMentionsMicrophoneRequirement() {
        let message = PermissionSummary.recordingPermissionAlertText(engineType: .qwen3)

        XCTAssertEqual(message.title, L10n.localize("permission.alert.title.microphone_only"))
        XCTAssertEqual(message.body, L10n.localize("permission.alert.body.microphone_only_local"))
    }
}
