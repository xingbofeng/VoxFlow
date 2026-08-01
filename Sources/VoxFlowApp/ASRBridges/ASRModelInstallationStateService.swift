import Foundation
import VoxFlowModelStore

final class ASRModelInstallationStateService {
    private let repository: (any ModelInstallationStateStoring)?

    init(repository: (any ModelInstallationStateStoring)?) {
        self.repository = repository
    }

    func markReady(at path: String, for key: ModelInstallKey?) {
        guard let key, let repository else { return }
        let installation = ModelInstallation(
            modelID: key.modelID,
            version: key.version,
            installedRoot: URL(fileURLWithPath: path, isDirectory: true)
        )
        try? repository.save(.ready(installation), for: key)
    }

    func markDownloading(for key: ModelInstallKey?, progress: ModelDownloadProgress) {
        guard let key, let repository else { return }
        try? repository.save(.downloading(progress: progress), for: key)
    }

    func removeState(for key: ModelInstallKey?) {
        guard let key, let repository else { return }
        try? repository.removeState(for: key)
    }

    func markDeleting(for key: ModelInstallKey?, engineType: ASREngineType) {
        guard let key,
              let repository,
              case let .ready(installation) = (try? repository.state(for: key)) ?? .notInstalled else {
            return
        }
        AppLogger.general.info("Marking model deleting: \(engineType.rawValue)")
        try? repository.save(.deleting(installation), for: key)
    }

    func markDeletionFailed(for key: ModelInstallKey?, engineType: ASREngineType, message: String) {
        guard let key, let repository else { return }
        AppLogger.general.error("Model deletion failed: \(engineType.rawValue), reason=\(message)")
        try? repository.save(.failed(message: message), for: key)
    }

    func restore(_ state: ModelInstallationState, for key: ModelInstallKey?) {
        guard let key, let repository else { return }
        switch state {
        case .notInstalled:
            try? repository.removeState(for: key)
        default:
            try? repository.save(state, for: key)
        }
    }

    func state(for key: ModelInstallKey?) -> ModelInstallationState {
        guard let key, let repository else {
            return .notInstalled
        }
        return (try? repository.state(for: key)) ?? .notInstalled
    }
}
