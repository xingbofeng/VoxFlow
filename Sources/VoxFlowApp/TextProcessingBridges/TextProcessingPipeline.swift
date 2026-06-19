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
    var llm: LLMRefinementTrace? = nil
    var output: OutputDeliveryTrace? = nil

    func safeForPersistence() -> TextProcessingTrace {
        TextProcessingTrace(
            llm: llm?.safeForPersistence(),
            output: output
        )
    }
}

struct OutputDeliveryTrace: Equatable, Codable {
    let resultKind: String
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
        guard errorMessage == nil else { return false }
        if responseText != nil {
            return true
        }
        if let statusCode {
            return (200..<300).contains(statusCode)
        }
        return false
    }

    func safeForPersistence() -> LLMRefinementTrace {
        LLMRefinementTrace(
            providerID: providerID,
            providerName: providerName,
            endpoint: endpoint,
            model: model,
            temperature: temperature,
            timeoutSeconds: timeoutSeconds,
            requestBodyJSON: #"{"messages":[{"role":"system","content":"[redacted: system prompt]"},{"role":"user","content":"[redacted: user content]"}]}"#,
            responseText: nil,
            statusCode: statusCode,
            durationMS: durationMS,
            errorMessage: errorMessage.map { _ in "[redacted: error message]" },
            completedAt: completedAt
        )
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
    func process(
        _ rawText: String,
        target: DictationTarget?,
        onRefinedTextUpdate: @escaping @MainActor (String) -> Void
    ) async -> TextProcessingResult
}

extension TextProcessing {
    func process(_ rawText: String, target: DictationTarget?) async -> TextProcessingResult {
        await process(rawText, target: target, onRefinedTextUpdate: { _ in })
    }

    func process(
        _ rawText: String,
        target: DictationTarget?,
        onRefinedTextUpdate: @escaping @MainActor (String) -> Void
    ) async -> TextProcessingResult {
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
        await process(rawText, target: nil, onRefinedTextUpdate: { _ in })
    }

    func process(_ rawText: String, target: DictationTarget?) async -> TextProcessingResult {
        await process(rawText, target: target, onRefinedTextUpdate: { _ in })
    }

    func process(
        _ rawText: String,
        target: DictationTarget?,
        onRefinedTextUpdate: @escaping @MainActor (String) -> Void
    ) async -> TextProcessingResult {
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
                let request = TextRefinementRequest(
                    text: text,
                    systemPrompt: prompt.result.systemPrompt,
                    model: prompt.result.model,
                    temperature: prompt.result.temperature
                )
                if let streamingRefiner = refiner as? any StreamingPromptAwareTextRefining {
                    refinedText = try await collectStream(
                        streamingRefiner.refineStream(request),
                        onUpdate: onRefinedTextUpdate
                    )
                } else {
                    refinedText = try await promptAwareRefiner.refine(request)
                }
                promptMetadata = prompt.result
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

    private func collectStream(
        _ stream: AsyncThrowingStream<String, Error>,
        onUpdate: @escaping @MainActor (String) -> Void
    ) async throws -> String {
        var refinedText = ""
        for try await snapshot in stream {
            refinedText = snapshot
            onUpdate(snapshot)
        }
        return refinedText
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
