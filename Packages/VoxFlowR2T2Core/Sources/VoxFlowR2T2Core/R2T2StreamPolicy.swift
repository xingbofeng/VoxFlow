import Foundation

/// `R2T2Stream` 中不依赖模型权重的纯决策。
///
/// `R2T2Stream` 只有加载完 2.4 GB 权重后才能构造，所以写在它内部的分支无法在 model-free
/// 测试里钉住。VoxFlow 需要下面这两条行为可验证（见 `PROVENANCE.md` 的「源码的本地改动」），
/// 因此把它们抽成纯函数：`R2T2Stream` 只做调用，测试只喂输入。
public enum R2T2StreamPolicy {
    /// `finish()` 是否必须发起一次 final decode。
    ///
    /// 上游在尾部音频缓冲为空时直接返回。这会漏掉最后一个非 final step 回滚掉的 token：
    /// 那些 token 只有在一次 decode 里才会被重新生成并提交，而"下一次 chunk"通常就是那次
    /// decode。录音恰好结束在 chunk 边界上时没有下一次，末字因此丢失。
    ///
    /// 只要本次会话处理过音频就冲刷一次，让边界情形与普通情形一致；从未收到音频的会话仍然
    /// 直接返回空串，不触发模型调用。
    public static func shouldIssueFinalDecode(hasBufferedTail: Bool, consumedSamples: Int) -> Bool {
        hasBufferedTail || consumedSamples > 0
    }

    /// 追加一条诊断 step 前，`steps` 需要丢弃的前缀长度。
    ///
    /// `limit <= 0` 表示不记录（生产默认）。滚动窗口只约束音频，不约束 `steps`，
    /// 所以它必须有自己的上限。
    public static func stepHistoryDropCount(count: Int, limit: Int) -> Int {
        guard limit > 0, count >= limit else { return 0 }
        return count - limit + 1
    }
}
