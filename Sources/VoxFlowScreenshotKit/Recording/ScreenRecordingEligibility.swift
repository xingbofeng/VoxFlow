import CoreGraphics

/// 区域录屏被禁用的原因，用于 tooltip 提示。
public enum ScreenRecordingDisabledReason: Equatable, Sendable {
    /// 选区跨越多个显示器。
    case crossDisplay
    /// 选区尺寸小于最小录屏尺寸。
    case tooSmall

    public var tooltip: String {
        switch self {
        case .crossDisplay:
            return "区域录屏暂不支持跨显示器，请只选择一个屏幕内的区域"
        case .tooSmall:
            return "选区录屏区域太小"
        }
    }
}

/// 区域录屏资格判定结果。
///
/// 纯函数，不依赖 overlay 内部状态。overlay 据此决定录屏 toolbar 是否可用，
/// 并在被禁用时仅禁用录屏动作，不影响截图/OCR/标注/翻译。
public enum ScreenRecordingEligibility: Equatable, Sendable {
    /// 可以录屏，并给出选区所在的唯一显示器。
    case eligible(display: ScreenshotDisplay)
    /// 不可录屏及原因。
    case disabled(reason: ScreenRecordingDisabledReason)

    /// 最小录屏尺寸（点）。小于此尺寸的选区禁用录屏。
    public static let minimumSizePoints: CGFloat = 64

    /// 根据选区状态与可用显示器判定录屏资格。
    public static func evaluate(
        selection: SelectionState,
        displays: [ScreenshotDisplay]
    ) -> ScreenRecordingEligibility {
        evaluate(selectionRect: selection.normalizedRect, displays: displays)
    }

    /// 根据选区矩形与可用显示器判定录屏资格。
    ///
    /// 规则：选区必须恰好与一个显示器相交，且宽高均不小于 `minimumSizePoints`。
    /// 跨显示器（相交 0 个或 >1 个）返回 `.crossDisplay`；单显示器但太小返回 `.tooSmall`。
    public static func evaluate(
        selectionRect: CGRect,
        displays: [ScreenshotDisplay]
    ) -> ScreenRecordingEligibility {
        let intersected = displays.filter { selectionRect.intersects($0.frame) }
        guard intersected.count == 1, let display = intersected.first else {
            return .disabled(reason: .crossDisplay)
        }
        guard selectionRect.width >= minimumSizePoints,
              selectionRect.height >= minimumSizePoints else {
            return .disabled(reason: .tooSmall)
        }
        return .eligible(display: display)
    }

    public var isEligible: Bool {
        if case .eligible = self {
            return true
        }
        return false
    }
}
