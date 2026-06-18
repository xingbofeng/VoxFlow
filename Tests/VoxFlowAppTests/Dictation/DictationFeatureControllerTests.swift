import Foundation
import XCTest
@testable import VoxFlowApp

@MainActor
final class DictationFeatureControllerTests: XCTestCase {
    func testDictationPressStartsConfiguredDictationAndTracksActiveAction() {
        let recorder = DictationFeatureRecorder()
        recorder.voiceEnhancementEnabled = true
        let controller = recorder.makeController()

        controller.handlePress(action: .dictation)

        XCTAssertEqual(controller.activeVoiceAction, .dictation)
        XCTAssertEqual(recorder.permissionRefreshCount, 1)
        XCTAssertEqual(recorder.voiceEnhancementUpdates, [true])
        XCTAssertEqual(recorder.startCalls, [
            .init(configuration: recorder.configuration, mode: .dictation)
        ])
        XCTAssertEqual(recorder.permissionAlertCount, 0)
        XCTAssertTrue(recorder.recognitionErrors.isEmpty)
    }

    func testAgentComposePressRequiresConfiguredLLMBeforePermissionChecks() {
        let recorder = DictationFeatureRecorder()
        recorder.isAgentComposeConfigured = false
        let controller = recorder.makeController()

        controller.handlePress(action: .agentCompose)

        XCTAssertNil(controller.activeVoiceAction)
        XCTAssertEqual(recorder.agentComposeSetupPromptCount, 1)
        XCTAssertEqual(recorder.permissionRefreshCount, 0)
        XCTAssertTrue(recorder.startCalls.isEmpty)
    }

    func testPressWithoutRecordingPermissionsShowsPermissionAlertAndDoesNotStart() {
        let recorder = DictationFeatureRecorder()
        recorder.permissionSnapshot = .deniedApple
        let controller = recorder.makeController()

        controller.handlePress(action: .dictation)

        XCTAssertNil(controller.activeVoiceAction)
        XCTAssertEqual(recorder.permissionRefreshCount, 1)
        XCTAssertEqual(recorder.permissionAlertCount, 1)
        XCTAssertTrue(recorder.voiceEnhancementUpdates.isEmpty)
        XCTAssertTrue(recorder.startCalls.isEmpty)
    }

    func testRecordingPermissionStartErrorShowsPermissionAlertAndDoesNotTrackActiveAction() {
        let recorder = DictationFeatureRecorder()
        recorder.startError = AudioRecorder.AudioRecorderError.microphoneUnavailable
        let controller = recorder.makeController()

        controller.handlePress(action: .dictation)

        XCTAssertNil(controller.activeVoiceAction)
        XCTAssertEqual(recorder.permissionAlertCount, 1)
        XCTAssertTrue(recorder.recognitionErrors.isEmpty)
    }

    func testGenericStartErrorShowsRecognitionErrorAndDoesNotTrackActiveAction() {
        let recorder = DictationFeatureRecorder()
        recorder.startError = DictationFeatureTestError.startFailed
        let controller = recorder.makeController()

        controller.handlePress(action: .dictation)

        XCTAssertNil(controller.activeVoiceAction)
        XCTAssertEqual(recorder.permissionAlertCount, 0)
        XCTAssertEqual(recorder.recognitionErrors.count, 1)
    }

    func testReleaseOnlyForwardsMatchingActiveAction() {
        let recorder = DictationFeatureRecorder()
        let controller = recorder.makeController()
        controller.handlePress(action: .dictation)

        controller.handleRelease(action: .agentCompose)
        controller.handleRelease(action: .dictation)

        XCTAssertEqual(recorder.releaseCount, 1)
    }

    func testStateChangePresentsWithActiveActionAndClearsWhenResultRequiresIt() {
        let recorder = DictationFeatureRecorder()
        let controller = recorder.makeController()
        controller.handlePress(action: .agentCompose)

        controller.handleStateChange(.recording)
        recorder.presentationResult = .init(shouldClearActiveVoiceAction: true)
        controller.handleStateChange(.idle)

        XCTAssertEqual(recorder.presentationCalls, [
            .init(state: .recording, action: .agentCompose),
            .init(state: .idle, action: .agentCompose)
        ])
        XCTAssertNil(controller.activeVoiceAction)
    }

    func testRecognitionErrorCallbackForwardsToErrorPresenter() {
        let recorder = DictationFeatureRecorder()
        let controller = recorder.makeController()

        controller.handleRecognitionError(DictationFeatureTestError.startFailed)

        XCTAssertEqual(recorder.recognitionErrors.count, 1)
    }
}

@MainActor
private final class DictationFeatureRecorder {
    var state: DictationState = .idle
    var isAgentComposeConfigured = true
    var permissionSnapshot = RecordingPermissionSnapshot.grantedApple
    var voiceEnhancementEnabled = false
    var startError: Error?
    var presentationResult = DictationStatePresentationResult(shouldClearActiveVoiceAction: false)

    private(set) var agentComposeSetupPromptCount = 0
    private(set) var permissionRefreshCount = 0
    private(set) var permissionAlertCount = 0
    private(set) var voiceEnhancementUpdates: [Bool] = []
    private(set) var startCalls: [StartCall] = []
    private(set) var releaseCount = 0
    private(set) var recognitionErrors: [Error] = []
    private(set) var presentationCalls: [PresentationCall] = []

    let configuration = DictationConfiguration(
        engineType: .apple,
        locale: Locale(identifier: "zh-Hans"),
        languageIdentifier: "zh-CN"
    )

    func makeController() -> DictationFeatureController {
        DictationFeatureController(
            currentState: { [weak self] in self?.state ?? .idle },
            isAgentComposeConfigured: { [weak self] in self?.isAgentComposeConfigured ?? false },
            showAgentComposeSetupRequired: { [weak self] in
                self?.agentComposeSetupPromptCount += 1
            },
            refreshRecordingPermissionSnapshot: { [weak self] in
                self?.permissionRefreshCount += 1
                return self?.permissionSnapshot ?? .deniedApple
            },
            showRecordingPermissionsAlert: { [weak self] in
                self?.permissionAlertCount += 1
            },
            voiceEnhancementEnabled: { [weak self] in
                self?.voiceEnhancementEnabled ?? false
            },
            setVoiceEnhancementEnabled: { [weak self] isEnabled in
                self?.voiceEnhancementUpdates.append(isEnabled)
            },
            currentConfiguration: { [weak self] in
                self?.configuration ?? DictationConfiguration(
                    engineType: .apple,
                    locale: Locale(identifier: "zh-Hans"),
                    languageIdentifier: "zh-CN"
                )
            },
            startDictation: { [weak self] configuration, mode in
                if let error = self?.startError {
                    throw error
                }
                self?.startCalls.append(StartCall(configuration: configuration, mode: mode))
                self?.state = .recording
            },
            releaseDictation: { [weak self] in
                self?.releaseCount += 1
            },
            isRecordingPermissionError: { error in
                error is AudioRecorder.AudioRecorderError
            },
            showRecognitionError: { [weak self] error in
                self?.recognitionErrors.append(error)
            },
            presentState: { [weak self] state, action in
                self?.presentationCalls.append(PresentationCall(state: state, action: action))
                return self?.presentationResult ?? DictationStatePresentationResult(
                    shouldClearActiveVoiceAction: false
                )
            }
        )
    }
}

private struct StartCall: Equatable {
    let configuration: DictationConfiguration
    let mode: VoiceTaskMode
}

private struct PresentationCall: Equatable {
    let state: DictationState
    let action: VoiceAction?
}

private enum DictationFeatureTestError: Error {
    case startFailed
}

private extension RecordingPermissionSnapshot {
    static let grantedApple = RecordingPermissionSnapshot(
        engineType: .apple,
        microphonePermission: .granted,
        speechPermission: .granted,
        isResolved: true,
        hasRequiredPermissions: true
    )

    static let deniedApple = RecordingPermissionSnapshot(
        engineType: .apple,
        microphonePermission: .denied,
        speechPermission: .denied,
        isResolved: true,
        hasRequiredPermissions: false
    )
}
