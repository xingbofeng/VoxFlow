import Foundation

@MainActor
final class DictationFeatureController {
    typealias CurrentState = () -> DictationState
    typealias IsAgentComposeConfigured = () -> Bool
    typealias VoidAction = () -> Void
    typealias PermissionSnapshotProvider = () -> RecordingPermissionSnapshot
    typealias BoolProvider = () -> Bool
    typealias SetVoiceEnhancementEnabled = (Bool) -> Void
    typealias CurrentConfiguration = () -> DictationConfiguration
    typealias StartDictation = (DictationConfiguration, VoiceTaskMode) throws -> Void
    typealias IsRecordingPermissionError = (Error) -> Bool
    typealias ShowRecognitionError = (Error) -> Void
    typealias PresentState = (DictationState, VoiceAction?) -> DictationStatePresentationResult

    private let currentState: CurrentState
    private let isAgentComposeConfigured: IsAgentComposeConfigured
    private let showAgentComposeSetupRequired: VoidAction
    private let refreshRecordingPermissionSnapshot: PermissionSnapshotProvider
    private let showRecordingPermissionsAlert: VoidAction
    private let voiceEnhancementEnabled: BoolProvider
    private let setVoiceEnhancementEnabled: SetVoiceEnhancementEnabled
    private let currentConfiguration: CurrentConfiguration
    private let startDictation: StartDictation
    private let releaseDictation: VoidAction
    private let isRecordingPermissionError: IsRecordingPermissionError
    private let showRecognitionError: ShowRecognitionError
    private let presentState: PresentState

    private(set) var activeVoiceAction: VoiceAction?

    init(
        currentState: @escaping CurrentState,
        isAgentComposeConfigured: @escaping IsAgentComposeConfigured,
        showAgentComposeSetupRequired: @escaping VoidAction,
        refreshRecordingPermissionSnapshot: @escaping PermissionSnapshotProvider,
        showRecordingPermissionsAlert: @escaping VoidAction,
        voiceEnhancementEnabled: @escaping BoolProvider,
        setVoiceEnhancementEnabled: @escaping SetVoiceEnhancementEnabled,
        currentConfiguration: @escaping CurrentConfiguration,
        startDictation: @escaping StartDictation,
        releaseDictation: @escaping VoidAction,
        isRecordingPermissionError: @escaping IsRecordingPermissionError,
        showRecognitionError: @escaping ShowRecognitionError,
        presentState: @escaping PresentState
    ) {
        self.currentState = currentState
        self.isAgentComposeConfigured = isAgentComposeConfigured
        self.showAgentComposeSetupRequired = showAgentComposeSetupRequired
        self.refreshRecordingPermissionSnapshot = refreshRecordingPermissionSnapshot
        self.showRecordingPermissionsAlert = showRecordingPermissionsAlert
        self.voiceEnhancementEnabled = voiceEnhancementEnabled
        self.setVoiceEnhancementEnabled = setVoiceEnhancementEnabled
        self.currentConfiguration = currentConfiguration
        self.startDictation = startDictation
        self.releaseDictation = releaseDictation
        self.isRecordingPermissionError = isRecordingPermissionError
        self.showRecognitionError = showRecognitionError
        self.presentState = presentState
    }

    func handlePress(action: VoiceAction = .dictation) {
        guard currentState().isIdle else { return }

        if action == .agentCompose && !isAgentComposeConfigured() {
            showAgentComposeSetupRequired()
            return
        }

        let permissionSnapshot = refreshRecordingPermissionSnapshot()
        guard permissionSnapshot.isResolved, permissionSnapshot.hasRequiredPermissions else {
            if permissionSnapshot.isResolved {
                showRecordingPermissionsAlert()
            }
            return
        }

        do {
            setVoiceEnhancementEnabled(voiceEnhancementEnabled())
            try startDictation(
                currentConfiguration(),
                action == .agentCompose ? .agentCompose : .dictation
            )
            activeVoiceAction = action
        } catch {
            if isRecordingPermissionError(error) {
                showRecordingPermissionsAlert()
            } else {
                showRecognitionError(error)
            }
        }
    }

    func handleRelease(action: VoiceAction = .dictation) {
        guard activeVoiceAction == action else {
            return
        }
        releaseDictation()
    }

    func handleStateChange(_ state: DictationState) {
        let result = presentState(state, activeVoiceAction)
        if result.shouldClearActiveVoiceAction {
            activeVoiceAction = nil
        }
    }

    func handleRecognitionError(_ error: Error) {
        showRecognitionError(error)
    }
}
