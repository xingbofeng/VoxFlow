import Foundation
import VoxFlowVoiceCorrection

struct TextProcessingResult: Equatable, Sendable {
    let rawText: String
    let finalText: String
    let llmProviderID: String?
    let styleID: String?
    let warnings: [String]
    let trace: TextProcessingTrace?
    let correctionEvents: [CorrectionEvent]

    init(
        rawText: String,
        finalText: String,
        llmProviderID: String? = nil,
        styleID: String? = nil,
        warnings: [String] = [],
        trace: TextProcessingTrace? = nil,
        correctionEvents: [CorrectionEvent] = []
    ) {
        self.rawText = rawText
        self.finalText = finalText
        self.llmProviderID = llmProviderID
        self.styleID = styleID
        self.warnings = warnings
        self.trace = trace
        self.correctionEvents = correctionEvents
    }
}

struct TextProcessingTrace: Equatable, Codable, Sendable {
    var llm: LLMRefinementTrace? = nil
    var output: OutputDeliveryTrace? = nil

    func safeForPersistence() -> TextProcessingTrace {
        TextProcessingTrace(
            llm: llm?.safeForPersistence(),
            output: output
        )
    }
}

struct OutputDeliveryTrace: Equatable, Codable, Sendable {
    let resultKind: String
}

struct LLMRefinementTrace: Equatable, Codable, Sendable {
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

struct TextRefinementTraceResult: Equatable, Sendable {
    let text: String
    let providerID: String
    let trace: LLMRefinementTrace
}

protocol TraceablePromptAwareTextRefining: PromptAwareTextRefining {
    func refineWithTrace(_ request: TextRefinementRequest) async throws -> TextRefinementTraceResult
}

final class TextRefinementTraceHandle: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<LLMRefinementTrace, Error>?
    private var continuations: [CheckedContinuation<LLMRefinementTrace, Error>] = []

    func complete(_ trace: LLMRefinementTrace) {
        resolve(.success(trace))
    }

    func fail(_ error: Error) {
        resolve(.failure(error))
    }

    func value() async throws -> LLMRefinementTrace {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            if let result {
                lock.unlock()
                continuation.resume(with: result)
                return
            }
            continuations.append(continuation)
            lock.unlock()
        }
    }

    private func resolve(_ result: Result<LLMRefinementTrace, Error>) {
        lock.lock()
        guard self.result == nil else {
            lock.unlock()
            return
        }
        self.result = result
        let continuations = self.continuations
        self.continuations.removeAll()
        lock.unlock()

        for continuation in continuations {
            continuation.resume(with: result)
        }
    }
}

struct TextRefinementStreamTraceResult: Sendable {
    let stream: AsyncThrowingStream<String, Error>
    let providerID: String?
    let trace: TextRefinementTraceHandle
}

protocol TraceableStreamingPromptAwareTextRefining: StreamingPromptAwareTextRefining {
    func refineStreamWithTrace(_ request: TextRefinementRequest) -> TextRefinementStreamTraceResult
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
    func process(
        _ rawText: String,
        target: DictationTarget?,
        correctionContext: CorrectionContext?,
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
        correctionContext: CorrectionContext?
    ) async -> TextProcessingResult {
        await process(
            rawText,
            target: target,
            correctionContext: correctionContext,
            onRefinedTextUpdate: { _ in }
        )
    }

    func process(
        _ rawText: String,
        target: DictationTarget?,
        onRefinedTextUpdate: @escaping @MainActor (String) -> Void
    ) async -> TextProcessingResult {
        await process(rawText)
    }

    func process(
        _ rawText: String,
        target: DictationTarget?,
        correctionContext: CorrectionContext?,
        onRefinedTextUpdate: @escaping @MainActor (String) -> Void
    ) async -> TextProcessingResult {
        await process(rawText, target: target, onRefinedTextUpdate: onRefinedTextUpdate)
    }
}

@MainActor
final class DefaultTextProcessingPipeline: TextProcessing {
    private let refiner: any TextRefining
    private let styleRepository: (any StyleRepository)?
    private let styleSelector: (any StyleSelecting)?
    private let promptBuilder: PromptBuilder
    private let voiceCorrectionProcessor: (any VoiceCorrectionTextProcessing)?

    init(
        refiner: any TextRefining,
        styleRepository: (any StyleRepository)? = nil,
        styleSelector: (any StyleSelecting)? = nil,
        promptBuilder: PromptBuilder = PromptBuilder(),
        voiceCorrectionProcessor: (any VoiceCorrectionTextProcessing)? = nil
    ) {
        self.refiner = refiner
        self.styleRepository = styleRepository
        self.styleSelector = styleSelector
        self.promptBuilder = promptBuilder
        self.voiceCorrectionProcessor = voiceCorrectionProcessor
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
        await process(
            rawText,
            target: target,
            correctionContext: nil,
            onRefinedTextUpdate: onRefinedTextUpdate
        )
    }

    func process(
        _ rawText: String,
        target: DictationTarget?,
        correctionContext: CorrectionContext?
    ) async -> TextProcessingResult {
        await process(
            rawText,
            target: target,
            correctionContext: correctionContext,
            onRefinedTextUpdate: { _ in }
        )
    }

    func process(
        _ rawText: String,
        target: DictationTarget?,
        correctionContext: CorrectionContext?,
        onRefinedTextUpdate: @escaping @MainActor (String) -> Void
    ) async -> TextProcessingResult {
        var text = rawText
        var warnings: [String] = []
        var llmProviderID: String?
        var styleID: String?
        var trace: TextProcessingTrace?
        var correctionEvents: [CorrectionEvent] = []

        if refiner.isEnabled, refiner.isConfigured {
            do {
                let prompt = await buildPrompt(target: target)
                warnings.append(contentsOf: prompt.warnings)
                var refinedText: String
                let promptMetadata: PromptBuildResult?
                var localLLMProviderID: String?
                var localLLMTrace: LLMRefinementTrace?
                if let promptAwareRefiner = refiner as? any PromptAwareTextRefining {
                    (refiner as? RefinementTraceProviding)?.clearLastTrace()
                    let request = TextRefinementRequest(
                        text: text,
                        systemPrompt: prompt.result.systemPrompt,
                        model: prompt.result.model,
                        temperature: prompt.result.temperature
                    )
                    if let traceableStreamingRefiner = refiner as? any TraceableStreamingPromptAwareTextRefining {
                        let streamResult = traceableStreamingRefiner.refineStreamWithTrace(request)
                        refinedText = try await collectStream(
                            streamResult.stream,
                            onUpdate: onRefinedTextUpdate
                        )
                        localLLMTrace = try await streamResult.trace.value()
                        localLLMProviderID = streamResult.providerID ?? localLLMTrace?.providerID
                    } else if let streamingRefiner = refiner as? any StreamingPromptAwareTextRefining {
                        refinedText = try await collectStream(
                            streamingRefiner.refineStream(request),
                            onUpdate: onRefinedTextUpdate
                        )
                    } else if let traceableRefiner = refiner as? any TraceablePromptAwareTextRefining {
                        let traceResult = try await traceableRefiner.refineWithTrace(request)
                        refinedText = traceResult.text
                        localLLMProviderID = traceResult.providerID
                        localLLMTrace = traceResult.trace
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
                llmProviderID = localLLMProviderID ?? (refiner as? any ActiveLLMProviderIdentifying)?.activeProviderID
                styleID = promptMetadata?.styleID
                trace = TextProcessingTrace(llm: localLLMTrace ?? (refiner as? RefinementTraceProviding)?.lastTrace)
            } catch {
                AppLogger.general.error("LLM refinement failed: \(error.localizedDescription)")
                warnings.append("llm_refinement_failed")
                trace = TextProcessingTrace(llm: (refiner as? RefinementTraceProviding)?.lastTrace)
            }
        }

        if let correctionContext,
           correctionContext.mode == .dictation,
           correctionContext.isFinalTranscript,
           !correctionContext.isSecureField,
           let voiceCorrectionProcessor {
            do {
                let result = try voiceCorrectionProcessor.process(
                    text,
                    context: correctionContext
                )
                text = result.correctedText
                correctionEvents = result.events
                warnings.append(contentsOf: result.warnings.map(\.rawValue))
            } catch {
                AppLogger.general.error("Voice correction failed: \(error.localizedDescription)")
                warnings.append("voice_correction_failed")
            }
        }

        return TextProcessingResult(
            rawText: rawText,
            finalText: text,
            llmProviderID: llmProviderID,
            styleID: styleID,
            warnings: warnings,
            trace: trace,
            correctionEvents: correctionEvents
        )
    }

    private func buildPrompt(target: DictationTarget?) async -> (result: PromptBuildResult, warnings: [String]) {
        do {
            let style: StyleProfileRecord?
            if let styleSelector {
                style = try await styleSelector.style(for: target)
            } else {
                style = try styleRepository?.defaultProfile()
            }
            return (promptBuilder.build(style: style, glossaryTerms: []), [])
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
}

extension LLMRefiner: TextRefining, PromptAwareTextRefining {}
