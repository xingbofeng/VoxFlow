import Foundation
import VoxFlowProviderFireRedASR

/// FireRedASR2-AED 预检结果的呈现映射。
///
/// Provider 侧只产出结构化 `FireRedASRPreflightBlocker`，不产出自由文案；用户可见的原因在这里
/// 本地化，因此非中文界面不会看到 Provider 拼出来的中文句子。
enum FireRedASRRuntimePresentation {
    private static let bytesPerGigabyte: UInt64 = 1_024 * 1_024 * 1_024

    static func reason(for blocker: FireRedASRPreflightBlocker) -> String {
        switch blocker {
        case .architectureUnsupported:
            return L10n.localize(
                "asr.fireredasr.unsupported.architecture",
                fallback: "FireRedASR2-AED does not support this Mac's processor architecture.",
                comment: "FireRedASR2-AED architecture blocker"
            )
        case .operatingSystemTooOld(let requiredMajorVersion, _):
            return L10n.format(
                "asr.fireredasr.unsupported.os",
                comment: "FireRedASR2-AED macOS version blocker",
                requiredMajorVersion
            )
        case .insufficientMemory(let requiredBytes, _):
            return L10n.format(
                "asr.fireredasr.unsupported.memory",
                comment: "FireRedASR2-AED unified memory blocker",
                Int(requiredBytes / bytesPerGigabyte)
            )
        }
    }
}
