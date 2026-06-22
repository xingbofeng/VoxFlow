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
        AppLogger.dictation.debug("handlePress action=\(action.rawValue)")

        if action == .agentCompose && !isAgentComposeConfigured() {
            AppLogger.dictation.warning("handlePress blocked: agentCompose not configured")
            showAgentComposeSetupRequired()
            return
        }

        let permissionSnapshot = refreshRecordingPermissionSnapshot()
        guard permissionSnapshot.isResolved, permissionSnapshot.hasRequiredPermissions else {
            if permissionSnapshot.isResolved {
                AppLogger.dictation.warning("handlePress permission denied: show alert")
                showRecordingPermissionsAlert()
            }
            AppLogger.dictation.debug("handlePress permission snapshot unresolved")
            return
        }

        do {
            setVoiceEnhancementEnabled(voiceEnhancementEnabled())
            activeVoiceAction = action
            try startDictation(
                currentConfiguration(),
                taskMode(for: action)
            )
            AppLogger.dictation.info("handlePress started dictation action=\(action.rawValue)")
        } catch {
            activeVoiceAction = nil
            if isRecordingPermissionError(error) {
                AppLogger.dictation.error("handlePress failed permission error")
                showRecordingPermissionsAlert()
            } else {
                AppLogger.dictation.error("handlePress failed: \(error.localizedDescription)")
                showRecognitionError(error)
            }
        }
    }

    func handleRelease(action: VoiceAction = .dictation) {
        guard activeVoiceAction == action else {
            AppLogger.dictation.debug("handleRelease ignored active=\(activeVoiceAction?.rawValue ?? "nil") expected=\(action.rawValue)")
            return
        }
        AppLogger.dictation.info("handleRelease action=\(action.rawValue)")
        releaseDictation()
    }

    func handleStateChange(_ state: DictationState) {
        AppLogger.dictation.debug("handleStateChange state=\(state)")
        let result = presentState(state, activeVoiceAction)
        if result.shouldClearActiveVoiceAction {
            activeVoiceAction = nil
        }
    }

    func handleRecognitionError(_ error: Error) {
        AppLogger.dictation.error("handleRecognitionError \(error.localizedDescription)")
        showRecognitionError(error)
    }

    private func taskMode(for action: VoiceAction) -> VoiceTaskMode {
        switch action {
        case .dictation:
            return .dictation
        case .agentCompose:
            return .agentCompose
        case .agentDispatch:
            return .agentDispatch
        }
    }
}
