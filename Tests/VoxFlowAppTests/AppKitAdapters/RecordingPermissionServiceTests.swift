import XCTest
@testable import VoxFlowApp

@MainActor
final class RecordingPermissionServiceTests: XCTestCase {
    func testQwenResolveRequestsOnlyMicrophonePermission() async {
        var microphoneStatus = AudioRecorder.PermissionStatus.notDetermined
        var microphoneRequests = 0
        var speechChecks = 0
        var speechRequests = 0
        let service = RecordingPermissionService(
            engineTypeProvider: { .qwen3 },
            microphonePermissionProvider: { microphoneStatus },
            speechPermissionProvider: {
                speechChecks += 1
                return .notDetermined
            },
            microphonePermissionRequester: {
                microphoneRequests += 1
                microphoneStatus = .granted
                return .granted
            },
            speechPermissionRequester: {
                speechRequests += 1
                return .granted
            }
        )

        let snapshot = await service.resolveRecordingPermissions()

        XCTAssertTrue(snapshot.isResolved)
        XCTAssertTrue(snapshot.hasRequiredPermissions)
        XCTAssertEqual(snapshot.engineType, .qwen3)
        XCTAssertEqual(snapshot.microphonePermission, .granted)
        XCTAssertEqual(snapshot.speechPermission, .denied)
        XCTAssertEqual(microphoneRequests, 1)
        XCTAssertEqual(speechChecks, 0)
        XCTAssertEqual(speechRequests, 0)
    }

    func testAppleResolveRequestsUndeterminedMicrophoneAndSpeechPermissions() async {
        var microphoneStatus = AudioRecorder.PermissionStatus.notDetermined
        var speechStatus = AudioRecorder.PermissionStatus.notDetermined
        var microphoneRequests = 0
        var speechRequests = 0
        let service = RecordingPermissionService(
            engineTypeProvider: { .apple },
            microphonePermissionProvider: { microphoneStatus },
            speechPermissionProvider: { speechStatus },
            microphonePermissionRequester: {
                microphoneRequests += 1
                microphoneStatus = .granted
                return .granted
            },
            speechPermissionRequester: {
                speechRequests += 1
                speechStatus = .granted
                return .granted
            }
        )

        let snapshot = await service.resolveRecordingPermissions()

        XCTAssertTrue(snapshot.isResolved)
        XCTAssertTrue(snapshot.hasRequiredPermissions)
        XCTAssertEqual(snapshot.engineType, .apple)
        XCTAssertEqual(snapshot.microphonePermission, .granted)
        XCTAssertEqual(snapshot.speechPermission, .granted)
        XCTAssertEqual(microphoneRequests, 1)
        XCTAssertEqual(speechRequests, 1)
    }

    func testRefreshUsesCurrentPermissionsWithoutRequesting() {
        var microphoneRequests = 0
        var speechRequests = 0
        let service = RecordingPermissionService(
            engineTypeProvider: { .apple },
            microphonePermissionProvider: { .granted },
            speechPermissionProvider: { .denied },
            microphonePermissionRequester: {
                microphoneRequests += 1
                return .granted
            },
            speechPermissionRequester: {
                speechRequests += 1
                return .granted
            }
        )

        let snapshot = service.refreshRecordingPermissions()

        XCTAssertTrue(snapshot.isResolved)
        XCTAssertFalse(snapshot.hasRequiredPermissions)
        XCTAssertEqual(snapshot.engineType, .apple)
        XCTAssertEqual(snapshot.microphonePermission, .granted)
        XCTAssertEqual(snapshot.speechPermission, .denied)
        XCTAssertEqual(microphoneRequests, 0)
        XCTAssertEqual(speechRequests, 0)
    }
}
