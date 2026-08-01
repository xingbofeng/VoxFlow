import Foundation

/// 跨平台云实时 ASR 转写状态，承载不同 provider 的拼接策略所需中间态。
public struct CloudRealtimeASRTranscriptState {
    /// 腾讯云：按 stable index 缓存的稳定分段。
    public var stableSegments: [Int: String] = [:]
    /// 阿里云 DashScope：已 committed 的文本前缀。
    public var committedText: String = ""
    /// 三家 provider 共用：最新可见文本。
    public var latestText: String = ""

    public init() {}

    /// 当前拼接后的可见文本。
    public var visibleText: String {
        latestText
    }
}

/// 单条消息解析后的对外发射。
public struct CloudRealtimeASREmission: Equatable, Sendable {
    public let text: String
    public let isFinal: Bool

    public init(text: String, isFinal: Bool) {
        self.text = text
        self.isFinal = isFinal
    }
}

/// 转写拼接工具，三家云 provider 共用。
public enum CloudRealtimeASRTranscriptAssembler {
    /// 腾讯云：stable prefix + live text 拼接。
    public static func combine(stablePrefix: String, liveText: String) -> String {
        guard !stablePrefix.isEmpty else { return liveText }
        guard !liveText.hasPrefix(stablePrefix) else { return liveText }
        return stablePrefix + liveText
    }

    /// 阿里云：committed prefix + 当前 text 拼接。
    public static func combine(prefix: String, text: String) -> String {
        guard !prefix.isEmpty else { return text }
        guard !text.hasPrefix(prefix) else { return text }
        return prefix + text
    }

    /// 腾讯云：将 stable segments 按 index 排序后拼接为稳定前缀。
    public static func joinedStablePrefix(_ segments: [Int: String]) -> String {
        segments.keys.sorted().compactMap { segments[$0] }.joined()
    }
}
