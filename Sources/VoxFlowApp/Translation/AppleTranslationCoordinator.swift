import Foundation
import NaturalLanguage
@preconcurrency import Translation

// MARK: - Public protocols

protocol AppleTranslationCoordinating: AnyObject, Sendable {
    var isAvailable: Bool { get }
    func translate(_ text: String) async throws -> String
}

@MainActor
protocol AppleTranslationSessionRunning: AnyObject {
    func translate(_ text: String) async throws -> String
}

// MARK: - Errors

enum AppleSystemTranslationError: LocalizedError, Equatable {
    case unavailableOnCurrentSystem
    case unableToIdentifyLanguage
    case unsupportedLanguage
    case languagePackDownloadFailed
    case sessionHostUnavailable
    case cancelled
    case internalFailure

    var errorDescription: String? {
        switch self {
        case .unavailableOnCurrentSystem:
            return "Apple 系统翻译在当前系统版本不可用，请使用已配置模型或安装本地翻译模型"
        case .unableToIdentifyLanguage:
            return "无法识别原文语言，请增加一些完整文字后重试"
        case .unsupportedLanguage:
            return "Apple 系统翻译暂不支持这种语言，请切换翻译模型"
        case .languagePackDownloadFailed:
            return "系统翻译语言包下载失败，请检查网络和磁盘空间后重试"
        case .sessionHostUnavailable:
            return "系统翻译窗口未就绪，请关闭结果窗口后重试"
        case .cancelled:
            return "已取消翻译"
        case .internalFailure:
            return "Apple 系统翻译失败，请稍后重试或切换翻译模型"
        }
    }
}

// MARK: - System adapter

@MainActor
final class SystemAppleTranslationSessionAdapter: AppleTranslationSessionRunning {
    private let session: TranslationSession

    init(session: TranslationSession) {
        self.session = session
    }

    func translate(_ text: String) async throws -> String {
        let response = try await session.translate(text)
        return response.targetText
    }
}

// MARK: - Coordinator

@MainActor
final class AppleTranslationCoordinator: ObservableObject, AppleTranslationCoordinating {
    @Published private(set) var configuration: TranslationSession.Configuration?

    nonisolated var isAvailable: Bool { true }

    /// 串行请求队列
    private var pendingRequest: PendingRequest?
    private var isExecutingRequest = false
    private var sessionHostTimeoutTask: Task<Void, Never>?
    private let sessionHostTimeout: Duration
    private let sourceLanguageDetector: @Sendable (String) -> Locale.Language?

    init(
        sessionHostTimeout: Duration = .seconds(15),
        sourceLanguageDetector: @escaping @Sendable (String) -> Locale.Language? = AppleTranslationCoordinator.detectSourceLanguage
    ) {
        self.sessionHostTimeout = sessionHostTimeout
        self.sourceLanguageDetector = sourceLanguageDetector
    }

    func translate(_ text: String) async throws -> String {
        // 空文本直接返回
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ""
        }

        try Task.checkCancellation()
        let requestID = UUID()

        // 等待上一个请求完成后才能排队
        if pendingRequest != nil || isExecutingRequest {
            throw AppleSystemTranslationError.internalFailure
        }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                    return
                }

                pendingRequest = PendingRequest(
                    id: requestID,
                    text: text,
                    sourceLanguage: sourceLanguage(for: text),
                    continuation: continuation
                )
                publishConfiguration(source: pendingRequest?.sourceLanguage)

                // 超时兜底：宿主窗口未挂载时释放
                sessionHostTimeoutTask?.cancel()
                let deadline = ContinuousClock.now.advanced(by: sessionHostTimeout)
                sessionHostTimeoutTask = Task { [weak self] in
                    do {
                        try await Task.sleep(until: deadline, clock: .continuous)
                    } catch {
                        return // cancelled before timeout
                    }
                    guard let self else { return }
                    guard self.pendingRequest != nil else { return }
                    self.failPending(with: .sessionHostUnavailable)
                }

                if Task.isCancelled {
                    cancelPendingRequest(id: requestID)
                }
            }
        } onCancel: { [weak self] in
            Task { @MainActor [weak self] in
                self?.cancelPendingRequest(id: requestID)
            }
        }
    }

    /// 由可见 SwiftUI host 在获得 `TranslationSession` 后调用。
    /// host 通过 adapter 包装系统 session，传递给 coordinator 执行。
    func executePendingRequest(using session: any AppleTranslationSessionRunning) async {
        sessionHostTimeoutTask?.cancel()
        sessionHostTimeoutTask = nil

        guard let request = pendingRequest else { return }

        // 原子领取：清空 pending，防止其他 host 重复执行
        pendingRequest = nil
        isExecutingRequest = true

        do {
            let result = try await session.translate(request.text)
            isExecutingRequest = false
            configuration = nil
            request.continuation.resume(returning: result)
        } catch {
            isExecutingRequest = false
            configuration = nil
            AppLogger.general.error(
                "Apple system translation session failed type=\(String(reflecting: type(of: error))) localized=\(error.localizedDescription) reflected=\(String(reflecting: error))"
            )
            let mappedError = Self.mapError(error)
            request.continuation.resume(throwing: mappedError)
        }
    }

    /// 取消当前请求
    func cancelCurrentRequest() {
        sessionHostTimeoutTask?.cancel()
        sessionHostTimeoutTask = nil
        if let request = pendingRequest {
            pendingRequest = nil
            configuration = nil
            request.continuation.resume(throwing: CancellationError())
        }
    }

    // MARK: - Private

    private func cancelPendingRequest(id: UUID) {
        guard pendingRequest?.id == id else { return }
        cancelCurrentRequest()
    }

    private func publishConfiguration(source: Locale.Language?) {
        // 每次发布新的 configuration 以触发 .translationTask 重新执行
        configuration = TranslationSession.Configuration(
            source: source,
            target: Locale.Language(identifier: "zh-Hans")
        )
    }

    private func failPending(with error: AppleSystemTranslationError) {
        guard let request = pendingRequest else { return }
        pendingRequest = nil
        configuration = nil
        request.continuation.resume(throwing: error)
    }

    nonisolated private static func mapError(_ error: Error) -> AppleSystemTranslationError {
        if error is CancellationError {
            return .cancelled
        }
        if TranslationError.unsupportedSourceLanguage ~= error ||
            TranslationError.unsupportedTargetLanguage ~= error ||
            TranslationError.unsupportedLanguagePairing ~= error {
            return .unsupportedLanguage
        }
        if TranslationError.unableToIdentifyLanguage ~= error {
            return .unableToIdentifyLanguage
        }
        if TranslationError.nothingToTranslate ~= error {
            return .unableToIdentifyLanguage
        }
        if TranslationError.internalError ~= error {
            return .internalFailure
        }
        // TranslationError cases vary across macOS SDK versions;
        // use localizedDescription-based heuristics instead of exhaustive switch.
        let desc = error.localizedDescription.lowercased()
        if desc.contains("language") && (desc.contains("identify") || desc.contains("recogni")) {
            return .unableToIdentifyLanguage
        }
        if desc.contains("unsupported") || desc.contains("not support") {
            return .unsupportedLanguage
        }
        if desc.contains("network") || desc.contains("download") || desc.contains("not installed") || desc.contains("space") {
            return .languagePackDownloadFailed
        }
        if error is URLError {
            return .languagePackDownloadFailed
        }
        if let cocoaError = error as? CocoaError, cocoaError.code == .fileWriteOutOfSpace {
            return .languagePackDownloadFailed
        }
        _ = (error as? TranslationError) // keep the import useful
        return .internalFailure
    }

    private func sourceLanguage(for text: String) -> Locale.Language? {
        sourceLanguageDetector(text) ?? Self.fallbackSourceLanguage(for: text)
    }

    nonisolated private static func detectSourceLanguage(_ text: String) -> Locale.Language? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let language = recognizer.dominantLanguage else {
            return nil
        }
        let confidence = recognizer.languageHypotheses(withMaximum: 1)[language] ?? 0
        guard confidence >= 0.45 else {
            return nil
        }
        return Locale.Language(identifier: language.rawValue)
    }

    nonisolated private static func fallbackSourceLanguage(for text: String) -> Locale.Language? {
        if text.unicodeScalars.contains(where: CharacterSet.letters.contains),
           text.unicodeScalars.contains(where: CharacterSet.alphanumerics.contains),
           text.range(of: #"\p{Latin}"#, options: .regularExpression) != nil {
            return Locale.Language(identifier: "en")
        }
        return nil
    }
}

// MARK: - Internal types

private extension AppleTranslationCoordinator {
    struct PendingRequest {
        let id: UUID
        let text: String
        let sourceLanguage: Locale.Language?
        let continuation: CheckedContinuation<String, any Error>
    }
}
