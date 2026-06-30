import Foundation

public struct DeterministicProcessorStep: Sendable, Equatable {
    public let id: String
    public let input: String
    public let output: String

    public var changed: Bool { input != output }
}

/// The deterministic text processing pipeline.
///
/// Runs in two phases around the LLM correction step:
///
/// 1. **pre-LLM**: lightweight cleanup on ASR raw text before it's fed into
///    the prompt. Suitable for filler removal and context disambiguation
///    preparation.
/// 2. **post-LLM**: final formatting on the accepted LLM output before
///    insertion. Suitable for punctuation normalization, CJK-Latin spacing,
///    long sentence breaking, and capitalization.
///
/// When the master switch (`enabled`) is off, both phases are no-ops,
/// preserving current behavior.
public struct DeterministicTextPipeline: Sendable {
    public let settings: DeterministicTextProcessingSettings

    public init(settings: DeterministicTextProcessingSettings = .defaults) {
        self.settings = settings
    }

    /// Effective settings after applying the master switch. When the master
    /// switch is off, all sub-toggles are forced off so the pipeline is a
    /// guaranteed no-op regardless of stored sub-toggle values.
    private var effective: DeterministicTextProcessingSettings {
        settings.effectiveSettings()
    }

    /// Pre-LLM processing: runs on ASR raw text before prompt rendering.
    /// Lightweight cleanup that helps the LLM see a cleaner input:
    /// filler word filtering and conservative smart number recognition.
    /// Does NOT do punctuation, spacing, or capitalization (those run
    /// post-LLM to avoid conflicting with the LLM's own formatting).
    public func preLLM(_ text: String, isCodingContext: Bool = false) -> String {
        preLLMSteps(text, isCodingContext: isCodingContext).last?.output ?? text
    }

    public func preLLMSteps(_ text: String, isCodingContext: Bool = false) -> [DeterministicProcessorStep] {
        let s = effective
        guard s.enabled else { return [] }
        var result = text
        var steps: [DeterministicProcessorStep] = []
        if s.fillerWordFiltering {
            let input = result
            let output = FillerWordFilter.process(
                result,
                context: FillerWordFilter.Context(isCodingContext: isCodingContext)
            )
            result = output
            steps.append(DeterministicProcessorStep(
                id: "filler_word_filtering",
                input: input,
                output: output
            ))
        }
        // Smart number recognition is conservative: ProtectedRegions mask
        // URLs/paths/identifiers/emails/versions/backticks before conversion,
        // so code-like tokens are not mangled. Coding context does not disable
        // it entirely (dates/quantities still appear in coding speech), but
        // the protection layer keeps identifiers safe.
        if s.smartNumberRecognition {
            let input = result
            let output = SmartNumberRecognizer.process(result)
            result = output
            steps.append(DeterministicProcessorStep(
                id: "smart_number_recognition",
                input: input,
                output: output
            ))
        }
        return steps
    }

    /// Post-LLM processing: runs on accepted LLM output before insertion.
    /// Handles punctuation, spacing, line breaking, and capitalization.
    public func postLLM(
        _ text: String,
        isCodingContext: Bool = false,
        outputFormatPolicy: StyleOutputFormatPolicy? = nil
    ) -> String {
        postLLMSteps(
            text,
            isCodingContext: isCodingContext,
            outputFormatPolicy: outputFormatPolicy
        ).last?.output ?? text
    }

    public func postLLMSteps(
        _ text: String,
        isCodingContext: Bool = false,
        outputFormatPolicy: StyleOutputFormatPolicy? = nil
    ) -> [DeterministicProcessorStep] {
        let s = effective
        guard s.enabled || !(outputFormatPolicy?.isEmpty ?? true) else { return [] }
        var result = text
        var steps: [DeterministicProcessorStep] = []
        let shouldRunPunctuation: Bool = switch outputFormatPolicy?.punctuation {
        case .complete, .less:
            true
        case .noEnding, nil:
            s.enabled && s.punctuationOptimization
        case .preserve:
            false
        }
        let shouldRunAutoCapitalization: Bool = switch outputFormatPolicy?.capitalization {
        case .normal:
            !isCodingContext
        case nil:
            s.enabled && s.autoCapitalization && !isCodingContext
        case .relaxed, .preserve:
            false
        }

        if s.enabled, !isCodingContext {
            let input = result
            let output = normalizeEscapedLineBreaks(result)
            result = output
            if input != output {
                steps.append(DeterministicProcessorStep(
                    id: "escaped_line_break_normalization",
                    input: input,
                    output: output
                ))
            }
        }

        if shouldRunPunctuation {
            let input = result
            let output = PunctuationOptimizer.process(
                result,
                context: PunctuationOptimizer.Context(
                    cjkThreshold: s.punctuationCJKThreshold,
                    wordThreshold: s.punctuationWordThreshold
                )
            )
            result = output
            steps.append(DeterministicProcessorStep(
                id: "punctuation_optimization",
                input: input,
                output: output
            ))
        }

        if s.cjkLatinSpacing {
            let input = result
            let output = CJKLatinSpacer.process(result)
            result = output
            steps.append(DeterministicProcessorStep(
                id: "cjk_latin_spacing",
                input: input,
                output: output
            ))
        }

        if s.longSentenceBreaking {
            let input = result
            let output = LongSentenceBreaker.process(
                result,
                context: LongSentenceBreaker.Context(
                    wordThreshold: s.longSentenceWordThreshold,
                    cjkThreshold: s.longSentenceCJKThreshold
                )
            )
            result = output
            steps.append(DeterministicProcessorStep(
                id: "long_sentence_breaking",
                input: input,
                output: output
            ))
        }

        if shouldRunAutoCapitalization {
            let input = result
            let output = AutoCapitalizer.process(
                result,
                context: AutoCapitalizer.Context(isCodingContext: isCodingContext)
            )
            result = output
            steps.append(DeterministicProcessorStep(
                id: "auto_capitalization",
                input: input,
                output: output
            ))
        }

        if let outputFormatPolicy, !outputFormatPolicy.isEmpty {
            let input = result
            let output = StyleOutputFormatter.process(result, policy: outputFormatPolicy)
            result = output
            steps.append(DeterministicProcessorStep(
                id: "style_output_format",
                input: input,
                output: output
            ))
        }

        return steps
    }

    private func normalizeEscapedLineBreaks(_ text: String) -> String {
        text.replacingOccurrences(of: "\\r\\n", with: "\n")
            .replacingOccurrences(of: "\\n", with: "\n")
    }
}
