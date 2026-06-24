import Foundation
import NaturalLanguage

/// `PromptAwareTextRefining` 适配器，将 `AppleTranslationCoordinator`
/// 包装为 refiner。负责：
/// - 中文短路（简体/繁体直接返回原文）
/// - 空文本返回
/// - 非中文文本委托给 coordinator
/// - 错误透传
final class AppleSystemTranslationRefiner: PromptAwareTextRefining, @unchecked Sendable {
    private let coordinator: any AppleTranslationCoordinating
    private let dominantLanguage: @Sendable (String) -> NLLanguage?

    init(
        coordinator: any AppleTranslationCoordinating,
        dominantLanguage: @escaping @Sendable (String) -> NLLanguage? = {
            NLLanguageRecognizer.dominantLanguage(for: $0)
        }
    ) {
        self.coordinator = coordinator
        self.dominantLanguage = dominantLanguage
    }

    var isEnabled: Bool { isConfigured }

    var isConfigured: Bool {
        coordinator.isAvailable
    }

    func refine(_ text: String) async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        // best-effort 中文判断：明确的中文直接返回原文
        if let dominant = dominantLanguage(trimmed) {
            switch dominant {
            case .simplifiedChinese, .traditionalChinese:
                return trimmed
            default:
                break
            }
        }

        // nil/.undetermined 或非中文都交给 coordinator
        // source: nil 让系统自动识别
        return try await coordinator.translate(trimmed)
    }

    func refine(_ request: TextRefinementRequest) async throws -> String {
        try await refine(request.text)
    }
}
