import Foundation

@MainActor
final class PendingCorrectionFallbackController {
    private let logger = AppLogger.dictation

    struct Token: Equatable {
        fileprivate let id = UUID()
    }

    private var pending: (token: Token, rawText: String)?

    var hasPending: Bool {
        pending != nil
    }

    func begin(rawText: String) -> Token? {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            logger.debug("PendingCorrectionFallbackController begin ignored: empty rawText")
            return nil
        }

        let token = Token()
        if let current = pending {
            logger.warning(
                "PendingCorrectionFallbackController replace pending: old=\(current.token.id.uuidString) new=\(token.id.uuidString)"
            )
        }
        pending = (token, trimmed)
        logger.debug(
            "PendingCorrectionFallbackController begin token=\(token.id.uuidString) " +
            "len=\(trimmed.count)"
        )
        return token
    }

    func finish(_ token: Token?) {
        guard let token,
              pending?.token == token else {
            logger.debug("PendingCorrectionFallbackController finish ignored: tokenMismatch token=\(token?.id.uuidString ?? "nil")")
            return
        }
        pending = nil
        logger.debug("PendingCorrectionFallbackController finish token=\(token.id.uuidString)")
    }

    func consumeRawText() -> String? {
        guard let rawText = pending?.rawText else { return nil }
        pending = nil
        logger.debug("PendingCorrectionFallbackController consumeRawText cleared")
        return rawText
    }
}
