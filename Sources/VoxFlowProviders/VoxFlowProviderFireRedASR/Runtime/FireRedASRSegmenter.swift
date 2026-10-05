import Foundation

/// 超长音频的分段策略。
///
/// FireRedASR2-AED 上游明确：AED 变体对超过约 60 秒的输入存在幻觉风险，超过约 200 秒会触发
/// 位置编码错误。而本 Provider 走的是离线整段解码（预览也是重解已累积音频，无法增量推进），
/// 没有流式可以规避，所以必须在解码时分段。
///
/// 策略：按 50 秒（留 10 秒余量）切成不超过门限的段，优先在**静音位置**下刀；搜索窗内
/// 找不到足够安静的切点时才按门限硬切，并把该段标记为降级，由调用方写进 trace。
///
/// 这是一个纯函数（只依赖采样值），因此可以在没有模型的情况下完整测试。
public enum FireRedASRSegmenter {
    /// 单段最长时长。官方幻觉边界约 60 s，这里留 10 s 余量。
    public static let maximumSegmentSeconds = 50

    /// 切点搜索窗占整段的比例：只在窗口末尾 20% 里找切点，避免把段切得过短。
    static let cutoffSearchFraction = 0.2

    /// 能量分析帧长。
    static let analysisFrameSeconds = 0.02

    /// 判定「静音」的 RMS 门限。低于它才算可用的切点。
    static let silenceRMSThreshold: Float = 0.01

    public struct Segment: Equatable, Sendable {
        /// 原始样本数组中该段覆盖的范围。
        public let range: Range<Int>
        /// true 表示这一段是按门限硬切的（搜索窗内没有找到足够安静的切点）。
        public let isHardCut: Bool

        public init(range: Range<Int>, isHardCut: Bool) {
            self.range = range
            self.isHardCut = isHardCut
        }
    }

    /// 把 `samples` 切成若干段。
    ///
    /// - 短于门限：返回单个 `isHardCut == false` 的整段，不做任何额外工作。
    /// - 长于门限：每段尽量不超过门限，切点优先落在静音上。
    public static func segments(samples: [Float], sampleRate: Int) -> [Segment] {
        let sampleCount = samples.count
        guard sampleCount > 0 else { return [] }

        let effectiveRate = sampleRate > 0 ? sampleRate : 16_000
        let maximumSegmentSamples = max(maximumSegmentSeconds * effectiveRate, 1)
        guard sampleCount > maximumSegmentSamples else {
            return [Segment(range: 0..<sampleCount, isHardCut: false)]
        }

        let frameLength = max(Int(Double(effectiveRate) * analysisFrameSeconds), 1)
        let searchWindowSamples = max(
            Int(Double(maximumSegmentSamples) * cutoffSearchFraction),
            frameLength
        )

        var segments: [Segment] = []
        var start = 0
        while start < sampleCount {
            let remaining = sampleCount - start
            if remaining <= maximumSegmentSamples {
                segments.append(Segment(range: start..<sampleCount, isHardCut: false))
                break
            }

            let hardBoundary = start + maximumSegmentSamples
            let searchStart = max(hardBoundary - searchWindowSamples, start + frameLength)
            let cutoff = quietestFrameBoundary(
                in: samples,
                searchStart: searchStart,
                searchEnd: hardBoundary,
                frameLength: frameLength
            )

            if let cutoff {
                segments.append(Segment(range: start..<cutoff, isHardCut: false))
                start = cutoff
            } else {
                segments.append(Segment(range: start..<hardBoundary, isHardCut: true))
                start = hardBoundary
            }
        }
        return segments
    }

    /// 在 `[searchStart, searchEnd)` 里找 RMS 最低的一帧；只有它低于静音门限才返回该帧起点。
    ///
    /// 返回 `nil` 表示整段搜索窗都不够安静，调用方应退化为硬切。
    static func quietestFrameBoundary(
        in samples: [Float],
        searchStart: Int,
        searchEnd: Int,
        frameLength: Int
    ) -> Int? {
        guard searchEnd - searchStart >= frameLength else { return nil }

        var bestBoundary: Int?
        var bestRMS = Float.greatestFiniteMagnitude
        var frameStart = searchStart
        while frameStart + frameLength <= searchEnd {
            var sumSquares: Float = 0
            for index in frameStart..<(frameStart + frameLength) {
                let sample = samples[index]
                sumSquares += sample * sample
            }
            let rms = (sumSquares / Float(frameLength)).squareRoot()
            if rms < bestRMS {
                bestRMS = rms
                bestBoundary = frameStart
            }
            frameStart += frameLength
        }

        guard bestRMS < silenceRMSThreshold else { return nil }
        return bestBoundary
    }
}
