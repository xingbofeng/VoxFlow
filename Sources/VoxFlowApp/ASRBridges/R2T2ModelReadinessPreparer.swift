import Foundation
import VoxFlowProviderR2T2

protocol R2T2ModelReadinessPreparing: Sendable {
    func prepare(modelURL: URL) async throws
}

/// 把 Provider 的预热 runner 接到 App 的下载流程上。
///
/// 与 Qwen3 一致：安装完成后先跑一次「加载 → 解码 → finish」的 canary，把 2.4 GB 权重的
/// 加载与 Metal 编译从首次听写挪到安装时；canary 失败则不标记为 ready，让用户走 repair。
struct R2T2ModelReadinessPreparer: R2T2ModelReadinessPreparing {
    private let runner: R2T2ModelReadinessRunner

    init(runner: R2T2ModelReadinessRunner = R2T2ModelReadinessRunner()) {
        self.runner = runner
    }

    func prepare(modelURL: URL) async throws {
        AppLogger.general.debug("R2T2 model readiness prepare start path=\(modelURL.lastPathComponent)")
        do {
            let report = try await runner.prepare(modelURL: modelURL)
            AppLogger.general.info(
                "R2T2 model readiness prepare completed path=\(modelURL.lastPathComponent), ready=\(report.isReady)"
            )
        } catch {
            AppLogger.general.warning(
                "R2T2 model readiness prepare failed path=\(modelURL.lastPathComponent), reason=\(error.localizedDescription)"
            )
            throw error
        }
    }
}
