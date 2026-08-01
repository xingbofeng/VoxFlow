import Foundation
import OSLog

/// 平台无关的 ASR session 日志接口。
/// macOS 适配到 AppLogger.audio（含脱敏），iOS 用默认 OSLog 实现。
public protocol ASRSessionLogger: Sendable {
    func debug(_ message: String)
    func info(_ message: String)
    func warning(_ message: String)
}

/// 默认基于 OSLog 的 logger，iOS App 直接使用。
public struct OSLogASRSessionLogger: ASRSessionLogger {
    private let logger: Logger

    public init(subsystem: String = Bundle.main.bundleIdentifier ?? "com.voxflow.app", category: String = "audio") {
        logger = Logger(subsystem: subsystem, category: category)
    }

    public func debug(_ message: String) {
        logger.debug("\(message, privacy: .public)")
    }

    public func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
    }

    public func warning(_ message: String) {
        logger.warning("\(message, privacy: .public)")
    }
}
