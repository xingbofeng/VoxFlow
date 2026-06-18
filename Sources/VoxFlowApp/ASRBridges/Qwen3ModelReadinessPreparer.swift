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
        try await runner.prepare(
            modelURL: modelURL,
            variant: Qwen3ModelVariant(size: size)
        )
    }
}
