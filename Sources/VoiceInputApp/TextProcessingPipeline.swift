import Foundation

struct TextProcessingResult: Equatable {
    let rawText: String
    let finalText: String
    let llmProviderID: String?
    let styleID: String?
    let warnings: [String]
    let trace: TextProcessingTrace?

    init(
        rawText: String,
        finalText: String,
        llmProviderID: String? = nil,
        styleID: String? = nil,
        warnings: [String] = [],
        trace: TextProcessingTrace? = nil
    ) {
        self.rawText = rawText
        self.finalText = finalText
        self.llmProviderID = llmProviderID
        self.styleID = styleID
        self.warnings = warnings
        self.trace = trace
    }
}

struct TextProcessingTrace: Equatable, Codable {
    var llm: LLMRefinementTrace?
}

struct LLMRefinementTrace: Equatable, Codable {
    let providerID: String
    let providerName: String
    let endpoint: String
    let model: String
    let temperature: Double
    let timeoutSeconds: Double
    let requestBodyJSON: String
    var responseText: String?
    var statusCode: Int?
    var durationMS: Int?
    var errorMessage: String?
    var completedAt: Date?

    var succeeded: Bool {
        errorMessage == nil && responseText != nil
    }
}

protocol TextRefining: AnyObject, Sendable {
    var isEnabled: Bool { get }
    var isConfigured: Bool { get }
    func refine(_ text: String) async throws -> String
}

protocol RefinementTraceProviding: AnyObject {
    var lastTrace: LLMRefinementTrace? { get }
    func clearLastTrace()
}

@MainActor
protocol TextProcessing {
    func process(_ rawText: String) async -> TextProcessingResult
    func process(_ rawText: String, target: DictationTarget?) async -> TextProcessingResult
}

extension TextProcessing {
    func process(_ rawText: String, target: DictationTarget?) async -> TextProcessingResult {
        await process(rawText)
    }
}

@MainActor
final class DefaultTextProcessingPipeline: TextProcessing {
    private let refiner: any TextRefining
    private let replacementRuleRepository: (any ReplacementRuleRepository)?
    private let replacementRuleEngine: ReplacementRuleEngine
    private let glossaryRepository: (any GlossaryRepository)?
    private let styleRepository: (any StyleRepository)?
    private let styleSelector: (any StyleSelecting)?
    private let promptBuilder: PromptBuilder

    init(
        refiner: any TextRefining,
        replacementRuleRepository: (any ReplacementRuleRepository)? = nil,
        replacementRuleEngine: ReplacementRuleEngine = ReplacementRuleEngine(),
        glossaryRepository: (any GlossaryRepository)? = nil,
        styleRepository: (any StyleRepository)? = nil,
        styleSelector: (any StyleSelecting)? = nil,
        promptBuilder: PromptBuilder = PromptBuilder()
    ) {
        self.refiner = refiner
        self.replacementRuleRepository = replacementRuleRepository
        self.replacementRuleEngine = replacementRuleEngine
        self.glossaryRepository = glossaryRepository
        self.styleRepository = styleRepository
        self.styleSelector = styleSelector
        self.promptBuilder = promptBuilder
    }

    func process(_ rawText: String) async -> TextProcessingResult {
        await process(rawText, target: nil)
    }

    func process(_ rawText: String, target: DictationTarget?) async -> TextProcessingResult {
        var text = rawText
        var warnings: [String] = []

        let beforeResult = applyReplacementRules(stage: .beforeLLM, to: text)
        text = beforeResult.text
        warnings.append(contentsOf: beforeResult.warnings)

        guard refiner.isEnabled, refiner.isConfigured else {
            let afterResult = applyReplacementRules(stage: .afterLLM, to: text)
            warnings.append(contentsOf: afterResult.warnings)
            return TextProcessingResult(rawText: rawText, finalText: afterResult.text, warnings: warnings)
        }

        do {
            let prompt = await buildPrompt(target: target)
            warnings.append(contentsOf: prompt.warnings)
            var refinedText: String
            let promptMetadata: PromptBuildResult?
            if let promptAwareRefiner = refiner as? any PromptAwareTextRefining {
                (refiner as? RefinementTraceProviding)?.clearLastTrace()
                refinedText = try await promptAwareRefiner.refine(
                    TextRefinementRequest(
                        text: text,
                        systemPrompt: prompt.result.systemPrompt,
                        model: prompt.result.model,
                        temperature: prompt.result.temperature
                    )
                )
                promptMetadata = prompt.result
                if prompt.result.styleID != nil,
                   refinedText.trimmingCharacters(in: .whitespacesAndNewlines)
                    == text.trimmingCharacters(in: .whitespacesAndNewlines) {
                    warnings.append("llm_echo_retry")
                    (refiner as? RefinementTraceProviding)?.clearLastTrace()
                    refinedText = try await promptAwareRefiner.refine(
                        TextRefinementRequest(
                            text: PromptBuilder.retryUserMessage(text),
                            systemPrompt: PromptBuilder.retrySystemPrompt(
                                prompt.result.systemPrompt
                            ),
                            model: prompt.result.model,
                            temperature: prompt.result.temperature
                        )
                    )
                }
            } else {
                refinedText = try await refiner.refine(text)
                promptMetadata = nil
            }
            let trimmedRefinedText = refinedText.trimmingCharacters(in: .whitespacesAndNewlines)
            text = trimmedRefinedText.isEmpty ? text : trimmedRefinedText
            let afterResult = applyReplacementRules(stage: .afterLLM, to: text)
            text = afterResult.text
            warnings.append(contentsOf: afterResult.warnings)
            return TextProcessingResult(
                rawText: rawText,
                finalText: text,
                llmProviderID: (refiner as? any ActiveLLMProviderIdentifying)?.activeProviderID,
                styleID: promptMetadata?.styleID,
                warnings: warnings,
                trace: TextProcessingTrace(llm: (refiner as? RefinementTraceProviding)?.lastTrace)
            )
        } catch {
            AppLogger.general.error("LLM refinement failed: \(error.localizedDescription)")
            let afterResult = applyReplacementRules(stage: .afterLLM, to: text)
            warnings.append(contentsOf: afterResult.warnings)
            warnings.append("llm_refinement_failed")
            return TextProcessingResult(
                rawText: rawText,
                finalText: afterResult.text,
                warnings: warnings,
                trace: TextProcessingTrace(llm: (refiner as? RefinementTraceProviding)?.lastTrace)
            )
        }
    }

    private func buildPrompt(target: DictationTarget?) async -> (result: PromptBuildResult, warnings: [String]) {
        do {
            let style: StyleProfileRecord?
            if let styleSelector {
                style = try await styleSelector.style(for: target)
            } else {
                style = try styleRepository?.defaultProfile()
            }
            let terms = try glossaryRepository?.list(category: nil) ?? []
            return (promptBuilder.build(style: style, glossaryTerms: terms), [])
        } catch {
            return (promptBuilder.build(style: nil, glossaryTerms: []), ["prompt_context_failed"])
        }
    }

    private func applyReplacementRules(
        stage: ReplacementApplyStage,
        to text: String
    ) -> ReplacementRuleApplicationResult {
        guard let replacementRuleRepository,
              let rules = try? replacementRuleRepository.listEnabled(stage: stage),
              !rules.isEmpty else {
            return ReplacementRuleApplicationResult(text: text, warnings: [])
        }
        return replacementRuleEngine.apply(rules, to: text)
    }
}

extension LLMRefiner: TextRefining, PromptAwareTextRefining {}
