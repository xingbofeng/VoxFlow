import Foundation

struct ModelDownloadProgressViewState: Equatable {
    let providerID: String
    let componentName: String
    let statusText: String
    let fractionCompleted: Double?
    let bytesWritten: Int64?
    let totalBytes: Int64?
    let totalModelBytes: Int64?
    let speedBytesPerSecond: Int64?

    var progressValue: Double? {
        guard let fractionCompleted else { return nil }
        return min(1, max(0, fractionCompleted))
    }

    var detailText: String {
        var parts: [String] = []
        if let effectiveBytesWritten, let effectiveTotalBytes {
            parts.append("\(Self.formatBytes(effectiveBytesWritten)) / \(Self.formatBytes(effectiveTotalBytes))")
        }
        if let progressValue {
            parts.append(Self.formatPercent(progressValue))
        }
        if let speedBytesPerSecond, speedBytesPerSecond > 0 {
            parts.append("\(Self.formatBytes(speedBytesPerSecond))/s")
        }
        return parts.isEmpty ? statusText : parts.joined(separator: " · ")
    }

    var modelSizeText: String {
        if let totalModelBytes {
            return "模型大小 \(Self.formatBytes(totalModelBytes))"
        }
        if let totalBytes {
            return "模型大小 \(Self.formatBytes(totalBytes))"
        }
        return "模型大小 下载时检测"
    }

    private var effectiveTotalBytes: Int64? {
        totalBytes ?? totalModelBytes
    }

    private var effectiveBytesWritten: Int64? {
        if let bytesWritten {
            return bytesWritten
        }
        guard let progressValue, let effectiveTotalBytes else {
            return nil
        }
        return Int64((Double(effectiveTotalBytes) * progressValue).rounded())
    }

    static func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
            .replacingOccurrences(of: "\u{2006}", with: " ")
            .replacingOccurrences(of: "\u{202F}", with: " ")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
    }

    private static func formatPercent(_ value: Double) -> String {
        let percent = Int((value * 100).rounded())
        return "\(min(100, max(0, percent)))%"
    }
}
