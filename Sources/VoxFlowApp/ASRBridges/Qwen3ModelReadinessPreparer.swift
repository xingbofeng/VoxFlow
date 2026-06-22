import Foundation
import VoxFlowProviderQwen3

protocol Qwen3ModelReadinessPreparing: Sendable {
    func prepare(modelURL: URL, size: ASRManager.ModelSize) async throws
}

struct Qwen3ModelReadinessPreparer: Qwen3ModelReadinessPreparing {
    private let runner: Qwen3ModelReadinessRunner

    init(
        runner: Qwen3ModelReadinessRunner = Qwen3ModelReadinessRunner()
    ) {
        self.runner = runner
    }

    func prepare(modelURL: URL, size: ASRManager.ModelSize) async throws {
        AppLogger.general.debug(
            "Qwen3 model readiness prepare start size=\(size.rawValue) path=\(modelURL.lastPathComponent)"
        )
        do {
            try await runner.prepare(
                modelURL: modelURL,
                variant: Qwen3ModelVariant(size: size)
            )
            AppLogger.general.info(
                "Qwen3 model readiness prepare completed size=\(size.rawValue) path=\(modelURL.lastPathComponent)"
            )
        } catch {
            AppLogger.general.warning(
                "Qwen3 model readiness prepare failed size=\(size.rawValue) path=\(modelURL.lastPathComponent), reason=\(error.localizedDescription)"
            )
            throw error
        }
    }
}
