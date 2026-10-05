import Foundation
import VoxFlowProviderR2T2

/// R2T2 预检结果的呈现映射。
///
/// Provider 侧只产出结构化 `R2T2PreflightBlocker`，不产出自由文案；用户可见的原因在这里本地化，
/// 因此非中文界面不会看到 Provider 拼出来的中文句子。
enum R2T2RuntimePresentation {
    private static let bytesPerGigabyte: UInt64 = 1_024 * 1_024 * 1_024

    static func reason(for blocker: R2T2PreflightBlocker) -> String {
        switch blocker {
        case .architectureUnsupported:
            return L10n.localize(
                "asr.r2t2.unsupported.architecture",
                fallback: "Confucius4-R2T2 requires an Apple Silicon (arm64) Mac.",
                comment: "R2T2 architecture blocker"
            )
        case .operatingSystemTooOld(let requiredMajorVersion, _):
            return L10n.format(
                "asr.r2t2.unsupported.os",
                comment: "R2T2 macOS version blocker",
                requiredMajorVersion
            )
        case .insufficientMemory(let requiredBytes, _):
            return L10n.format(
                "asr.r2t2.unsupported.memory",
                comment: "R2T2 unified memory blocker",
                Int(requiredBytes / bytesPerGigabyte)
            )
        }
    }

    static func caution(for caution: R2T2PreflightCaution) -> String {
        switch caution {
        case .memoryBelowRecommended:
            return L10n.format(
                "asr.r2t2.caution.memory",
                comment: "R2T2 unified memory below recommendation",
                Int(R2T2RuntimePreflight.recommendedMemoryBytes / bytesPerGigabyte)
            )
        }
    }
}
