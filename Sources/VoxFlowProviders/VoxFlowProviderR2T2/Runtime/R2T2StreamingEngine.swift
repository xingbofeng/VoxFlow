import Foundation

/// VoxFlow 对隔离 runtime（`Packages/VoxFlowR2T2Core`）的接缝。
///
/// 上游 `R2T2Stream` 需要已加载的 MLX 模型，无法在单元测试中构造；本协议把“已确认文本增量”
/// 这一唯一被 Provider 消费的语义抽出来，使 session 的映射行为可用确定性 fake 验证。
///
/// 契约（对应上游 `R2T2Stream` 的语义）：
/// - 增量只增不回滚；调用方按顺序把每次返回值追加到 `committedText`。
/// - 本协议不暴露上游的 speculative / 待回看内容，Provider 因此不会把未确认文本交给 HUD。
public protocol R2T2StreamingEngine: AnyObject, Sendable {
    /// 提交一段音频，返回本次新确认的文本增量（可能为空数组）。
    func push(_ samples: [Float]) -> [String]

    /// 冲刷尾部音频，返回最后一段已确认文本增量（可能为空串）。
    func finish() -> String

    /// 截至当前的完整已确认文本。
    var committedText: String { get }

    /// 尚未确认的尾部文本（本步被回滚的 `unfixedTokens` 个 token）。
    ///
    /// 它是模型对最近一小段音频的当前判断，会被下一步带着更多上下文重新解码，因此内容可能改写。
    /// 只允许作为实时预览交给 HUD（`PartialTranscript.unstableSuffix`），不能进入最终文本。
    var pendingText: String { get }

    /// 上游识别出的语言名，未识别时为空串。
    var detectedLanguage: String { get }

    /// 停止 core 并释放本次会话状态。
    func cancel()
}

public protocol R2T2StreamMaking: Sendable {
    func makeStream(
        modelURL: URL,
        languageHint: String?,
        contextPrompt: String?
    ) async throws -> any R2T2StreamingEngine
}
