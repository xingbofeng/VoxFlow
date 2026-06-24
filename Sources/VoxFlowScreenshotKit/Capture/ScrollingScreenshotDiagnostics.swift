import CoreGraphics
import OSLog

enum ScrollingScreenshotDiagnostics {
    static let logger = Logger(
        subsystem: "com.voxflow.app",
        category: "scrolling-screenshot"
    )

    static func rect(_ rect: CGRect) -> String {
        "x=\(rounded(rect.minX)) y=\(rounded(rect.minY)) w=\(rounded(rect.width)) h=\(rounded(rect.height))"
    }

    static func size(_ image: CGImage?) -> String {
        guard let image else { return "nil" }
        return "\(image.width)x\(image.height)"
    }

    private static func rounded(_ value: CGFloat) -> String {
        String(format: "%.1f", Double(value))
    }
}
