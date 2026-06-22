import Foundation
import Speech

struct RecordingPermissionSnapshot: Equatable {
    let engineType: ASREngineType
    let microphonePermission: AudioRecorder.PermissionStatus
    let speechPermission: AudioRecorder.PermissionStatus
    let isResolved: Bool
    let hasRequiredPermissions: Bool
}

@MainActor
final class RecordingPermissionService {
    typealias EngineTypeProvider = () -> ASREngineType
    typealias PermissionProvider = () -> AudioRecorder.PermissionStatus
    typealias PermissionRequester = () async -> AudioRecorder.PermissionStatus

    private let engineTypeProvider: EngineTypeProvider
    private let microphonePermissionProvider: PermissionProvider
    private let speechPermissionProvider: PermissionProvider
    private let microphonePermissionRequester: PermissionRequester
    private let speechPermissionRequester: PermissionRequester

    init(
        engineTypeProvider: @escaping EngineTypeProvider,
        microphonePermissionProvider: @escaping PermissionProvider = AudioRecorder.checkPermission,
        speechPermissionProvider: @escaping PermissionProvider = SpeechRecognizer.checkPermission,
        microphonePermissionRequester: @escaping PermissionRequester = {
            await AudioRecorder.requestPermission() ? .granted : .denied
        },
        speechPermissionRequester: @escaping PermissionRequester = {
            switch await SpeechRecognizer.requestPermission() {
            case .authorized:
                return .granted
            case .denied, .restricted:
                return .denied
            case .notDetermined:
                return .notDetermined
            @unknown default:
                return .notDetermined
            }
        }
    ) {
        self.engineTypeProvider = engineTypeProvider
        self.microphonePermissionProvider = microphonePermissionProvider
        self.speechPermissionProvider = speechPermissionProvider
        self.microphonePermissionRequester = microphonePermissionRequester
        self.speechPermissionRequester = speechPermissionRequester
    }

    func resolveRecordingPermissions() async -> RecordingPermissionSnapshot {
        let engineType = engineTypeProvider()
        AppLogger.general.debug("解析录音权限：engine=\(engineType.rawValue)")
        var microphonePermission = microphonePermissionProvider()

        if microphonePermission == .notDetermined {
            microphonePermission = await microphonePermissionRequester()
        }

        let speechPermission: AudioRecorder.PermissionStatus
        if engineType == .apple {
            var currentSpeechPermission = speechPermissionProvider()
            if currentSpeechPermission == .notDetermined {
                currentSpeechPermission = await speechPermissionRequester()
            }
            speechPermission = currentSpeechPermission
        } else {
            speechPermission = .denied
        }
        AppLogger.general.debug("权限解析结果：microphone=\(microphonePermission), speech=\(speechPermission), engine=\(engineType.rawValue)")

        return makeSnapshot(
            engineType: engineType,
            microphonePermission: microphonePermission,
            speechPermission: speechPermission
        )
    }

    func refreshRecordingPermissions() -> RecordingPermissionSnapshot {
        AppLogger.general.debug("刷新录音权限快照")
        return makeSnapshot(
            engineType: engineTypeProvider(),
            microphonePermission: microphonePermissionProvider(),
            speechPermission: speechPermissionProvider()
        )
    }

    private func makeSnapshot(
        engineType: ASREngineType,
        microphonePermission: AudioRecorder.PermissionStatus,
        speechPermission: AudioRecorder.PermissionStatus
    ) -> RecordingPermissionSnapshot {
        RecordingPermissionSnapshot(
            engineType: engineType,
            microphonePermission: microphonePermission,
            speechPermission: speechPermission,
            isResolved: true,
            hasRequiredPermissions: RecordingPermissionPolicy.hasRequiredPermissions(
                engineType: engineType,
                microphonePermission: microphonePermission,
                speechPermission: speechPermission
            )
        )
    }
}
