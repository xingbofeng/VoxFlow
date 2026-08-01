import Foundation

/// 移动端听写状态机状态。
///
/// - idle: 未开始
/// - requestingPermission: 正在请求麦克风权限
/// - recording: 录音中，可能伴随实时 partial 文本
/// - transcribing: 录音已停止，等待 final 文本
/// - finished: 已拿到 final 文本
/// - failed: 失败（权限拒绝、配置缺失、录音失败、ASR 错误等）
public enum MobileDictationState: Equatable, Sendable {
    case idle
    case requestingPermission
    case recording(liveText: String)
    case transcribing(liveText: String)
    case finished(text: String)
    case failed(message: String)

    /// 当前可见文本（partial 或 final），用于 UI 展示。
    public var visibleText: String {
        switch self {
        case .idle, .requestingPermission, .failed:
            return ""
        case let .recording(liveText):
            return liveText
        case let .transcribing(liveText):
            return liveText
        case let .finished(text):
            return text
        }
    }

    /// 是否处于可停止的活跃状态。
    public var isStoppable: Bool {
        switch self {
        case .recording, .transcribing:
            return true
        default:
            return false
        }
    }
}
