import Foundation
import VoxFlowASRCore

public enum R2T2ProviderError: Error, Equatable, Sendable, LocalizedError {
    case modelNotInstalled
    case modelCorrupt
    /// Provider / 预热侧自己跑预检后得出的否决：保留结构化原因，文案交给 App 层。
    case preflightBlocked(R2T2PreflightBlocker)
    /// 安装状态已由 App 侧判为不支持：分类是结构化的，原因文案原样带回。
    case unsupportedInstallationState(category: ASRErrorCategory, reason: String)
    case preparationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .modelNotInstalled:
            return "Confucius4-R2T2 model is not installed."
        case .modelCorrupt:
            return "Confucius4-R2T2 model is corrupt."
        case .preflightBlocked(let blocker):
            return "Confucius4-R2T2 runtime is unavailable on this Mac. \(blocker)"
        case .unsupportedInstallationState(_, let reason):
            return reason
        case .preparationFailed(let reason):
            return reason
        }
    }
}

extension R2T2ProviderError {
    /// 映射到 ASR Core 的既有错误分类，使 Provider 失败沿用当前可解释状态呈现。
    var asrError: VoxFlowASRCore.ASRError {
        let category: VoxFlowASRCore.ASRErrorCategory
        switch self {
        case .modelNotInstalled:
            category = .modelNotInstalled
        case .modelCorrupt:
            category = .modelCorrupt
        case .preflightBlocked(let blocker):
            category = blocker.asrErrorCategory
        case .unsupportedInstallationState(let providedCategory, _):
            category = providedCategory
        case .preparationFailed:
            category = .preparationFailed
        }
        return VoxFlowASRCore.ASRError(category: category, message: localizedDescription)
    }
}
