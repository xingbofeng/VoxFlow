import Foundation

/// 分段结果的观测点。
///
/// `FireRedASRASRSession` 不依赖任何日志框架（Provider target 只依赖 ASR Core / Audio / CSherpaOnnx），
/// 因此把「这次录音被怎么切」的结果通过一个可选回调交给调用方，由 App 侧写进处理链路 trace。
public struct FireRedASRSegmentationReport: Equatable, Sendable {
    /// 总段数。短录音为 1。
    public let segmentCount: Int
    /// 其中被硬切（搜索窗内没找到静音切点）的段数。非 0 表示发生了一次降级。
    public let hardCutSegmentCount: Int
    public let sampleCount: Int

    public init(segmentCount: Int, hardCutSegmentCount: Int, sampleCount: Int) {
        self.segmentCount = segmentCount
        self.hardCutSegmentCount = hardCutSegmentCount
        self.sampleCount = sampleCount
    }
}
