import XCTest
@testable import VoxFlowApp

final class RecordingPermissionPolicyTests: XCTestCase {
    func testQwen3RequiresMicrophoneButNotAppleSpeechPermission() {
        XCTAssertTrue(
            RecordingPermissionPolicy.hasRequiredPermissions(
                engineType: .qwen3,
                microphonePermission: .granted,
                speechPermission: .denied
            )
        )
    }

    func testAppleSpeechRequiresMicrophoneAndSpeechPermission() {
        XCTAssertFalse(
            RecordingPermissionPolicy.hasRequiredPermissions(
                engineType: .apple,
                microphonePermission: .granted,
                speechPermission: .denied
            )
        )
        XCTAssertTrue(
            RecordingPermissionPolicy.hasRequiredPermissions(
                engineType: .apple,
                microphonePermission: .granted,
                speechPermission: .granted
            )
        )
    }
}
