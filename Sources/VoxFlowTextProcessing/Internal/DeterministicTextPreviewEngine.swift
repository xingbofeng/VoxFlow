import Foundation

/// Shared preview helper for settings UI. It runs the same deterministic
/// processors used by the post-LLM pipeline, but isolates one processor so a
/// threshold editor can show the direct effect of the value being dragged.
public enum DeterministicTextPreviewEngine {
    public enum Processor: Sendable, Equatable {
        case punctuationOptimization
        case longSentenceBreaking
    }

    public static func preview(
        _ text: String,
        processor: Processor,
        settings: DeterministicTextProcessingSettings
    ) -> String {
        let effective = settings.effectiveSettings()
        guard effective.enabled else { return text }

        let normalized = normalizeEscapedLineBreaks(text)
        switch processor {
        case .punctuationOptimization:
            return PunctuationOptimizer.process(
                normalized,
                context: .init(
                    cjkThreshold: effective.punctuationCJKThreshold,
                    wordThreshold: effective.punctuationWordThreshold
                )
            )
        case .longSentenceBreaking:
            return LongSentenceBreaker.process(
                normalized,
                context: .init(
                    wordThreshold: effective.longSentenceWordThreshold,
                    cjkThreshold: effective.longSentenceCJKThreshold
                )
            )
        }
    }

    private static func normalizeEscapedLineBreaks(_ text: String) -> String {
        text.replacingOccurrences(of: "\\r\\n", with: "\n")
            .replacingOccurrences(of: "\\n", with: "\n")
    }
}
