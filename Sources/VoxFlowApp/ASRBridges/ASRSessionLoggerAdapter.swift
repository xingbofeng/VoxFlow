import Foundation
import VoxFlowASRRuntime

/// 将 `AppLogger.audio` 适配为跨平台 `ASRSessionLogger`，保留脱敏与 OSLog category 语义。
struct AppLoggerASRSessionLogger: ASRSessionLogger {
    private let logger: AppLogger

    init(_ logger: AppLogger = .audio) {
        self.logger = logger
    }

    func debug(_ message: String) {
        logger.debug(message)
    }

    func info(_ message: String) {
        logger.info(message)
    }

    func warning(_ message: String) {
        logger.warning(message)
    }
}
