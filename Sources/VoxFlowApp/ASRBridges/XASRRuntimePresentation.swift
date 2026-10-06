import Foundation
import VoxFlowASRCore
import VoxFlowModelStore
import VoxFlowProviderXASR

/// X-ASR-zh-en 预检结果的呈现映射。
///
/// Provider 侧只产出结构化 `XASRPreflightBlocker`，不产出自由文案；用户可见的原因在这里
/// 本地化，因此非中文界面不会看到 Provider 拼出来的中文句子。
enum XASRRuntimePresentation {
    private static let bytesPerGigabyte: UInt64 = 1_024 * 1_024 * 1_024

    static func reason(for blocker: XASRPreflightBlocker) -> String {
        switch blocker {
        case .architectureUnsupported:
            return L10n.localize(
                "asr.xasr.unsupported.architecture",
                fallback: "X-ASR-zh-en does not support this Mac's processor architecture.",
                comment: "X-ASR-zh-en architecture blocker"
            )
        case .operatingSystemTooOld(let requiredMajorVersion, _):
            return L10n.format(
                "asr.xasr.unsupported.os",
                comment: "X-ASR-zh-en macOS version blocker",
                requiredMajorVersion
            )
        case .insufficientMemory(let requiredBytes, _):
            return L10n.format(
                "asr.xasr.unsupported.memory",
                comment: "X-ASR-zh-en unified memory blocker",
                Int(requiredBytes / bytesPerGigabyte)
            )
        }
    }
}

enum XASRErrorPresentation {
    static func localizedError(_ error: Error) -> Error {
        let category: ASRErrorCategory
        let key: String
        if case .failure(let core) = error as? ASRCoreBackedASREngineError {
            category = core.category
            switch category {
            case .audioDropped: key = "asr.xasr.invalid_audio"
            case .modelNotInstalled, .modelCorrupt: key = "asr.xasr.files_missing"
            case .unsupportedLanguage: key = "asr.xasr.unsupported_language"
            case .emptyTranscript: key = "asr.error.no_effective_speech"
            case .cancelled: key = "asr.xasr.invalidated"
            default: key = "asr.xasr.start_failed"
            }
        } else if let runtime = error as? XASRRuntimeError {
            switch runtime {
            case .modelFilesMissing: category = .modelNotInstalled
            case .modelCorrupt: category = .modelCorrupt
            case .invalidated, .streamClosed: category = .cancelled
            default: category = .preparationFailed
            }
            switch runtime {
            case .busy: key = "asr.xasr.busy"
            case .invalidAudio: key = "asr.xasr.invalid_audio"
            case .modelFilesMissing, .modelCorrupt: key = "asr.xasr.files_missing"
            case .invalidated, .streamClosed: key = "asr.xasr.invalidated"
            case .recognizerCreationFailed, .streamCreationFailed: key = "asr.xasr.start_failed"
            }
        } else if let provider = error as? XASRProviderError {
            switch provider {
            case .preflightBlocked(let blocker):
                return ASRCoreBackedASREngineError.failure(.init(category: blocker.asrErrorCategory, message: XASRRuntimePresentation.reason(for: blocker)))
            case .modelNotInstalled: category = .modelNotInstalled; key = "asr.xasr.files_missing"
            case .unsupportedLanguage: category = .unsupportedLanguage; key = "asr.xasr.unsupported_language"
            case .emptyTranscript: category = .emptyTranscript; key = "asr.error.no_effective_speech"
            case .audioDropped: category = .audioDropped; key = "asr.xasr.invalid_audio"
            case .invalidSessionState, .preparationFailed: category = .preparationFailed; key = "asr.xasr.start_failed"
            }
        } else if error is ModelDownloadError {
            category = .preparationFailed; key = "asr.xasr.download_failed"
        } else {
            category = .preparationFailed; key = "asr.xasr.start_failed"
        }
        return ASRCoreBackedASREngineError.failure(.init(category: category, message: L10n.localize(key, comment: "X-ASR runtime failure")))
    }
}
