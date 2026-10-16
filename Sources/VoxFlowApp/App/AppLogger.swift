import Foundation
import OSLog

struct AppLogger {
    static let general = AppLogger(category: "general")
    static let audio = AppLogger(category: "audio")
    static let dictation = AppLogger(category: "dictation")
    static let database = AppLogger(category: "database")
    static let network = AppLogger(category: "network")
    static let injection = AppLogger(category: "injection")
    static let modelDownload = AppLogger(category: "modelDownload")

    private let logger: Logger

    init(
        subsystem: String = Bundle.main.bundleIdentifier ?? ProductBrand.bundleIdentifier,
        category: String
    ) {
        logger = Logger(subsystem: subsystem, category: category)
    }

    func debug(_ message: String) {
        logger.debug("\(Self.redact(message), privacy: .public)")
    }

    func info(_ message: String) {
        logger.info("\(Self.redact(message), privacy: .public)")
    }

    /// `.notice` 是 os_log 的默认持久化级别：debug/info 只在内存里存活，排查历史问题时
    /// 查不到，所以设备切换、丢帧、音频摄入汇总这类事故现场必须走这里。
    func notice(_ message: String) {
        logger.notice("\(Self.redact(message), privacy: .public)")
    }

    func error(_ message: String) {
        logger.error("\(Self.redact(message), privacy: .public)")
    }

    func warning(_ message: String) {
        logger.warning("\(Self.redact(message), privacy: .public)")
    }

    static func redact(_ message: String) -> String {
        redactionPatterns.reduce(message) { current, rule in
            guard let regex = try? NSRegularExpression(pattern: rule.pattern) else {
                return current
            }
            let range = NSRange(current.startIndex..<current.endIndex, in: current)
            return regex.stringByReplacingMatches(
                in: current,
                range: range,
                withTemplate: rule.replacement
            )
        }
    }

    private static let redactionPatterns: [(pattern: String, replacement: String)] = [
        (#"(?i)("(?:api[_-]?key|apikey)"\s*:\s*")[^"]*(")"#, #"$1[REDACTED]$2"#),
        (#"(?i)("authorization"\s*:\s*")(?:bearer\s+)?[^"]*(")"#, #"$1[REDACTED]$2"#),
        (#"(?i)(bearer\s+)[A-Za-z0-9._~+/=-]+"#, "$1[REDACTED]"),
        (#"(?i)((?:api[_-]?key|apikey)=)[^&\s]+"#, "$1[REDACTED]"),
        (#"(?i)((?:api[_ -]?key|apikey)\s*[:=]\s*)[^\s,;&]+"#, "$1[REDACTED]"),
        (#"(?i)((?:token|access_token)=)[^&\s]+"#, "$1[REDACTED]"),
        (#"/Users/[^/\s"]+[^"\s]*"#, "~"),
        // Context text redaction
        (#"(?i)(visibleText|selectedText|inputAreaText|contextText)\s*[:=]\s*"[^"]*""#, #"$1: [REDACTED]"#),
        // Screenshot reference redaction
        (#"(?i)(screenshot|screenCapture|screenImage|visualContent)\s*[:=]\s*"[^"]*""#, #"$1: [REDACTED]"#),
        (#"(?i)(screenshot|screenCapture|screenImage)\s*[:=]\s*<[^>]*>"#, #"$1: [REDACTED]"#),
    ]
}
