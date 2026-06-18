import AppKit

struct WaveformModel {
    static let barCount = 5
    static let weights: [CGFloat] = [0.5, 0.8, 1.0, 0.75, 0.55]
    static let barWidth: CGFloat = 4
    static let barSpacing: CGFloat = 6
    static let maxBarHeight: CGFloat = 32
    static let minBarHeight: CGFloat = 3
    static let attackRate: CGFloat = 0.40
    static let releaseRate: CGFloat = 0.15
    static let jitterRange: CGFloat = 0.04

    static var totalWidth: CGFloat {
        CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * barSpacing
    }

    private(set) var smoothedRMS: CGFloat = 0

    mutating func update(
        targetRMS: CGFloat,
        jitter: () -> CGFloat
    ) -> [CGFloat] {
        let clampedRMS = max(0, min(1, targetRMS))
        let rate = clampedRMS > smoothedRMS ? Self.attackRate : Self.releaseRate
        smoothedRMS += (clampedRMS - smoothedRMS) * rate

        let amplifiedRMS = min(smoothedRMS * 2.5, 1)
        return Self.weights.map { weight in
            let baseHeight = amplifiedRMS * weight * Self.maxBarHeight
            let jitterFraction = max(-Self.jitterRange, min(Self.jitterRange, jitter()))
            let jitterHeight = jitterFraction * Self.maxBarHeight * weight
            return max(Self.minBarHeight, min(Self.maxBarHeight, baseHeight + jitterHeight))
        }
    }
}
