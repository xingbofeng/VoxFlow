import Foundation
import VoxFlowProviderFireRedASR

protocol FireRedASRModelReadinessPreparing: Sendable {
    func prepare(modelURL: URL) async throws
}

/// 把 Provider 的预热 runner 接到 App 的下载流程上。
///
/// 与 R2T2 一致：安装完成后先跑一次「加载 → 解码」的 canary，把 1.24 GB 权重与 ORT session
/// 的创建成本从首次听写挪到安装时；canary 失败就不标记为 ready，让用户走 repair。
///
/// 注意 Provider 侧的会话是**每次听写新建识别器**（与 FunASR 相同），所以这里预热的是「权重与
/// tokens 可用」这件事本身，而不是常驻缓存；它的价值是把「下载完却用不了」提前暴露在安装阶段。
struct FireRedASRModelReadinessPreparer: FireRedASRModelReadinessPreparing {
    private let runner: FireRedASRModelReadinessRunner

    init(runner: FireRedASRModelReadinessRunner = FireRedASRModelReadinessRunner()) {
        self.runner = runner
    }

    func prepare(modelURL: URL) async throws {
        AppLogger.general.debug("FireRedASR2-AED model readiness prepare start path=\(modelURL.lastPathComponent)")
        do {
            let report = try await runner.prepare(modelURL: modelURL)
            AppLogger.general.info(
                "FireRedASR2-AED model readiness prepare completed path=\(modelURL.lastPathComponent), "
                    + "ready=\(report.isReady)"
            )
        } catch {
            AppLogger.general.warning(
                "FireRedASR2-AED model readiness prepare failed path=\(modelURL.lastPathComponent), "
                    + "reason=\(error.localizedDescription)"
            )
            throw error
        }
    }
}
