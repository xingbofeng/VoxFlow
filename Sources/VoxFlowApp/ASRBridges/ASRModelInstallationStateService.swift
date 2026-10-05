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

    /// 权重装好了但跑不起来（预热 canary 失败）。
    ///
    /// 必须落成 `failed` 而不是停在 `notInstalled`：卡片只有看到 `failed`/`corrupt` 才会给出
    /// repair 入口，否则用户看到的是「下载」按钮，会以为再点一次就能解决。
    func markPreparationFailed(for key: ModelInstallKey?, engineType: ASREngineType, message: String) {
        guard let key, let repository else { return }
        AppLogger.general.error("Model preparation failed: \(engineType.rawValue), reason=\(message)")
        try? repository.save(.failed(message: message), for: key)
    }

    /// 下载成功但落盘的文件不全或不可读。
    func markCorrupt(for key: ModelInstallKey?, engineType: ASREngineType, reason: String) {
        guard let key, let repository else { return }
        AppLogger.general.error("Model corrupt after download: \(engineType.rawValue), reason=\(reason)")
        try? repository.save(.corrupt(reason: reason), for: key)
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
