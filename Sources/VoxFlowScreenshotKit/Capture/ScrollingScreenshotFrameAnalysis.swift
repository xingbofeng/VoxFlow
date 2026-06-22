import CoreGraphics
import Foundation

public struct ScrollingScreenshotFrameChecksum: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public let bytesPerRow: Int
    public let value: UInt64

    public init(width: Int, height: Int, bytesPerRow: Int, value: UInt64) {
        self.width = width
        self.height = height
        self.bytesPerRow = bytesPerRow
        self.value = value
    }
}

public enum ScrollingScreenshotMatchFailureReason: Equatable, Sendable {
    case captureUnavailable
    case frameSizeChanged
    case duplicateFrame
    case shiftNotDetected
    case shiftTooSmall(Int)
    case bandVoteDisagreed
}

public enum ScrollingScreenshotCaptureHealth: Equatable, Sendable {
    case good
    case unstable(reason: ScrollingScreenshotMatchFailureReason, consecutiveFailures: Int)
    case paused(reason: ScrollingScreenshotMatchFailureReason, consecutiveFailures: Int)
    case reachedEnd
    case reachedHeightLimit
}

public struct ScrollingScreenshotShiftEstimate: Equatable, Sendable {
    public let rows: Int
    public let agreeingBandCount: Int
    public let totalBandCount: Int
    public let excludedTopRows: Int
    public let excludedRightColumns: Int

    public var confidence: Double {
        guard totalBandCount > 0 else { return 0 }
        return Double(agreeingBandCount) / Double(totalBandCount)
    }

    public init(
        rows: Int,
        agreeingBandCount: Int,
        totalBandCount: Int,
        excludedTopRows: Int = 0,
        excludedRightColumns: Int = 0
    ) {
        self.rows = rows
        self.agreeingBandCount = agreeingBandCount
        self.totalBandCount = totalBandCount
        self.excludedTopRows = excludedTopRows
        self.excludedRightColumns = excludedRightColumns
    }
}

public struct ScrollingScreenshotStitchResult: Equatable, @unchecked Sendable {
    public let image: CGImage?
    public let estimate: ScrollingScreenshotShiftEstimate?
    public let failureReason: ScrollingScreenshotMatchFailureReason?

    public static func stitched(_ image: CGImage, estimate: ScrollingScreenshotShiftEstimate) -> Self {
        Self(image: image, estimate: estimate, failureReason: nil)
    }

    public static func skipped(_ reason: ScrollingScreenshotMatchFailureReason) -> Self {
        Self(image: nil, estimate: nil, failureReason: reason)
    }
}

public struct ScrollingScreenshotSessionStatus: Equatable, Sendable {
    public let stripCount: Int
    public let pixelHeight: Int
    public let health: ScrollingScreenshotCaptureHealth
    public let isAutoScrolling: Bool

    public init(
        stripCount: Int,
        pixelHeight: Int,
        health: ScrollingScreenshotCaptureHealth,
        isAutoScrolling: Bool
    ) {
        self.stripCount = stripCount
        self.pixelHeight = pixelHeight
        self.health = health
        self.isAutoScrolling = isAutoScrolling
    }
}
