import Foundation
import VoxFlowContextBoost
import VoxFlowVoiceCorrection

struct TextProcessingResult: Equatable, Sendable {
    let rawText: String
    let finalText: String
    let llmProviderID: String?
    let styleID: String?
    let warnings: [String]
    let trace: TextProcessingTrace?
    let correctionEvents: [CorrectionEvent]
    let appliedCorrectionEvents: [CorrectionEvent]

    init(
        rawText: String,
        finalText: String,
        llmProviderID: String? = nil,
        styleID: String? = nil,
        warnings: [String] = [],
        trace: TextProcessingTrace? = nil,
        correctionEvents: [CorrectionEvent] = [],
        appliedCorrectionEvents: [CorrectionEvent]? = nil
    ) {
        self.rawText = rawText
        self.finalText = finalText
        self.llmProviderID = llmProviderID
        self.styleID = styleID
        self.warnings = warnings
        self.trace = trace
        self.correctionEvents = correctionEvents
        self.appliedCorrectionEvents = appliedCorrectionEvents ?? correctionEvents
    }
}

struct TextProcessingTrace: Equatable, Codable, Sendable {
    var llm: LLMRefinementTrace? = nil
    var output: OutputDeliveryTrace? = nil
    var contextBoost: ContextBoostTrace? = nil
    var voiceCorrection: VoiceCorrectionTrace? = nil

    func safeForPersistence() -> TextProcessingTrace {
        TextProcessingTrace(
            llm: llm?.safeForPersistence(),
            output: output,
            contextBoost: contextBoost?.safeForPersistence(),
            voiceCorrection: voiceCorrection?.safeForPersistence()
        )
    }
}

struct VoiceCorrectionTrace: Equatable, Codable, Sendable {
    let candidateEvents: [CorrectionEvent]
    let appliedEvents: [CorrectionEvent]
    let warnings: [String]
    let failureReason: String?

    init(
        candidateEvents: [CorrectionEvent] = [],
        appliedEvents: [CorrectionEvent] = [],
        warnings: [String] = [],
        failureReason: String? = nil
    ) {
        self.candidateEvents = candidateEvents
        self.appliedEvents = appliedEvents
        self.warnings = warnings
        self.failureReason = failureReason
    }

    func safeForPersistence() -> VoiceCorrectionTrace {
        VoiceCorrectionTrace(
            candidateEvents: candidateEvents,
            appliedEvents: appliedEvents,
            warnings: warnings,
            failureReason: failureReason.map { _ in "[redacted: failure reason]" }
        )
    }
}

struct ContextBoostTrace: Equatable, Codable, Sendable {
    let appName: String?
    let bundleID: String?
    let hotwords: [String]
    let hotwordDetails: [ContextBoostHotwordTrace]
    let source: String
    let ttlSeconds: Int
    let ocrCharacterCount: Int?
    let candidateCount: Int?
    let appliedToLLMPrompt: Bool
    let failureReason: String?

    init(
        appName: String?,
        bundleID: String?,
        hotwords: [String],
        hotwordDetails: [ContextBoostHotwordTrace] = [],
        source: String,
        ttlSeconds: Int,
        ocrCharacterCount: Int? = nil,
        candidateCount: Int? = nil,
        appliedToLLMPrompt: Bool,
        failureReason: String?
    ) {
        self.appName = appName
        self.bundleID = bundleID
        self.hotwords = hotwords
        self.hotwordDetails = hotwordDetails
        self.source = source
        self.ttlSeconds = ttlSeconds
        self.ocrCharacterCount = ocrCharacterCount
        self.candidateCount = candidateCount
        self.appliedToLLMPrompt = appliedToLLMPrompt
        self.failureReason = failureReason
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.appName = try container.decodeIfPresent(String.self, forKey: .appName)
        self.bundleID = try container.decodeIfPresent(String.self, forKey: .bundleID)
        self.hotwords = try container.decodeIfPresent([String].self, forKey: .hotwords) ?? []
        self.hotwordDetails = try container.decodeIfPresent(
            [ContextBoostHotwordTrace].self,
            forKey: .hotwordDetails
        ) ?? []
        self.source = try container.decodeIfPresent(String.self, forKey: .source) ?? "current_window_ocr"
        self.ttlSeconds = try container.decodeIfPresent(Int.self, forKey: .ttlSeconds) ?? 0
        self.ocrCharacterCount = try container.decodeIfPresent(Int.self, forKey: .ocrCharacterCount)
        self.candidateCount = try container.decodeIfPresent(Int.self, forKey: .candidateCount)
        self.appliedToLLMPrompt = try container.decodeIfPresent(
            Bool.self,
            forKey: .appliedToLLMPrompt
        ) ?? false
        self.failureReason = try container.decodeIfPresent(String.self, forKey: .failureReason)
    }

    func safeForPersistence() -> ContextBoostTrace {
        ContextBoostTrace(
            appName: appName,
            bundleID: bundleID,
            hotwords: hotwords,
            hotwordDetails: hotwordDetails.map { $0.safeForPersistence() },
            source: source,
            ttlSeconds: ttlSeconds,
            ocrCharacterCount: ocrCharacterCount,
            candidateCount: candidateCount,
            appliedToLLMPrompt: appliedToLLMPrompt,
            failureReason: failureReason
        )
    }
}

struct ContextBoostHotwordTrace: Equatable, Codable, Sendable {
    let text: String
    let score: Double
    let source: String
    let evidenceReasons: [String]

    func safeForPersistence() -> ContextBoostHotwordTrace {
        ContextBoostHotwordTrace(
            text: text,
            score: score,
            source: source,
            evidenceReasons: evidenceReasons
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

enum ContextBoostCaptureOutcome: Sendable {
    case captured(OCRContextSnapshot)
    case unavailable(String)
}

@MainActor
protocol TextProcessing {
    func prepareContextBoost(target: DictationTarget?)
    func cancelContextBoost()
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
    func prepareContextBoost(target: DictationTarget?) {}
    func cancelContextBoost() {}

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
    private let contextBoostProvider: (any CurrentWindowOCRContextProviding)?
    private let contextBoostCoordinator: ContextBoostPrefetchCoordinator?
    private let contextBoostEnabled: @Sendable () -> Bool
    private let contextBoostSuppressed: @Sendable () -> Bool
    private let contextBoostTimeoutNanoseconds: UInt64

    init(
        refiner: any TextRefining,
        styleRepository: (any StyleRepository)? = nil,
        styleSelector: (any StyleSelecting)? = nil,
        promptBuilder: PromptBuilder = PromptBuilder(),
        voiceCorrectionProcessor: (any VoiceCorrectionTextProcessing)? = nil,
        contextBoostProvider: (any CurrentWindowOCRContextProviding)? = nil,
        contextBoostCoordinator: ContextBoostPrefetchCoordinator? = nil,
        contextBoostEnabled: @escaping @Sendable () -> Bool = { ContextBoostSettings.isEnabled() },
        contextBoostSuppressed: @escaping @Sendable () -> Bool = { ContextBoostSuppression.isSuppressed() },
        contextBoostTimeoutNanoseconds: UInt64 = 1_000_000_000
    ) {
        self.refiner = refiner
        self.styleRepository = styleRepository
        self.styleSelector = styleSelector
        self.promptBuilder = promptBuilder
        self.voiceCorrectionProcessor = voiceCorrectionProcessor
        self.contextBoostProvider = contextBoostProvider
        self.contextBoostCoordinator = contextBoostCoordinator
        self.contextBoostEnabled = contextBoostEnabled
        self.contextBoostSuppressed = contextBoostSuppressed
        self.contextBoostTimeoutNanoseconds = contextBoostTimeoutNanoseconds
    }

    func prepareContextBoost(target: DictationTarget?) {
        guard contextBoostEnabled(),
              !contextBoostSuppressed(),
              target?.bundleID != ProductBrand.bundleIdentifier,
              refiner is any PromptAwareTextRefining else {
            contextBoostCoordinator?.cancel()
            return
        }
        contextBoostCoordinator?.start(target: target)
    }

    func cancelContextBoost() {
        contextBoostCoordinator?.cancel()
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
        defer { contextBoostCoordinator?.cancel() }
        var text = rawText
        var warnings: [String] = []
        var llmProviderID: String?
        var styleID: String?
        var trace: TextProcessingTrace?
        var contextBoostTrace: ContextBoostTrace?
        var correctionEvents: [CorrectionEvent] = []
        var appliedCorrectionEvents: [CorrectionEvent] = []

        if refiner.isEnabled, refiner.isConfigured {
            do {
                let contextBoostOutcome = await captureContextBoostIfNeeded(target: target)
                let contextSnapshot = contextBoostOutcome?.snapshot
                contextBoostTrace = contextTrace(from: contextBoostOutcome, target: target)
                let prompt = await buildPrompt(
                    target: target,
                    temporaryHotwords: contextSnapshot?.hotwords ?? []
                )
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
                trace = TextProcessingTrace(
                    llm: localLLMTrace ?? (refiner as? RefinementTraceProviding)?.lastTrace,
                    contextBoost: contextBoostTrace
                )
            } catch {
                AppLogger.general.error("LLM refinement failed: \(error.localizedDescription)")
                warnings.append("llm_refinement_failed")
                trace = TextProcessingTrace(
                    llm: (refiner as? RefinementTraceProviding)?.lastTrace,
                    contextBoost: contextBoostTrace
                )
            }
        }

        if let correctionContext,
           correctionContext.mode == .dictation,
           correctionContext.isFinalTranscript,
           !correctionContext.isSecureField,
           let voiceCorrectionProcessor {
            do {
                let textBeforeCorrection = text
                let result = try voiceCorrectionProcessor.process(
                    text,
                    context: correctionContext
                )
                text = result.correctedText
                correctionEvents = result.events
                appliedCorrectionEvents = result.correctedText == textBeforeCorrection ? [] : result.events
                let correctionWarnings = result.warnings.map(\.rawValue)
                warnings.append(contentsOf: correctionWarnings)
                var updatedTrace = trace ?? TextProcessingTrace()
                updatedTrace.voiceCorrection = VoiceCorrectionTrace(
                    candidateEvents: correctionEvents,
                    appliedEvents: appliedCorrectionEvents,
                    warnings: correctionWarnings
                )
                trace = updatedTrace
            } catch {
                AppLogger.general.error("Voice correction failed: \(error.localizedDescription)")
                warnings.append("voice_correction_failed")
                var updatedTrace = trace ?? TextProcessingTrace()
                updatedTrace.voiceCorrection = VoiceCorrectionTrace(
                    warnings: ["voice_correction_failed"],
                    failureReason: error.localizedDescription
                )
                trace = updatedTrace
            }
        }

        return TextProcessingResult(
            rawText: rawText,
            finalText: text,
            llmProviderID: llmProviderID,
            styleID: styleID,
            warnings: warnings,
            trace: trace,
            correctionEvents: correctionEvents,
            appliedCorrectionEvents: appliedCorrectionEvents
        )
    }

    private func buildPrompt(
        target: DictationTarget?,
        temporaryHotwords: [TemporaryHotword] = []
    ) async -> (result: PromptBuildResult, warnings: [String]) {
        do {
            let style: StyleProfileRecord?
            if let styleSelector {
                style = try await styleSelector.style(for: target)
            } else {
                style = try styleRepository?.defaultProfile()
            }
            return (
                promptBuilder.build(
                    style: style,
                    temporaryHotwords: temporaryHotwords
                ),
                []
            )
        } catch {
            return (
                promptBuilder.build(
                    style: nil,
                    temporaryHotwords: temporaryHotwords
                ),
                ["prompt_context_failed"]
            )
        }
    }

    private func captureContextBoostIfNeeded(target: DictationTarget?) async -> ContextBoostCaptureOutcome? {
        guard contextBoostEnabled(),
              !contextBoostSuppressed(),
              target?.bundleID != ProductBrand.bundleIdentifier,
              refiner is any PromptAwareTextRefining else {
            return nil
        }

        if let contextBoostCoordinator,
           let outcome = await contextBoostCoordinator.resolve(
               postReleaseTimeoutNanoseconds: contextBoostTimeoutNanoseconds
           ) {
            return outcome
        }

        guard let contextBoostProvider else { return nil }

        return await withTaskGroup(of: ContextBoostCaptureOutcome.self) { group in
            group.addTask {
                if let snapshot = await contextBoostProvider.captureContext(for: target) {
                    return .captured(snapshot)
                }
                return .unavailable("no_ocr_context")
            }
            group.addTask { [contextBoostTimeoutNanoseconds] in
                try? await Task.sleep(nanoseconds: contextBoostTimeoutNanoseconds)
                return .unavailable("context_boost_timeout")
            }
            let result = await group.next()
            group.cancelAll()
            return result
        }
    }

    private func contextTrace(
        from outcome: ContextBoostCaptureOutcome?,
        target: DictationTarget?
    ) -> ContextBoostTrace? {
        guard let outcome else { return nil }
        switch outcome {
        case .captured(let snapshot):
            return ContextBoostTrace(
                appName: snapshot.appName,
                bundleID: snapshot.bundleID,
                hotwords: snapshot.hotwords.map(\.text),
                hotwordDetails: snapshot.hotwords.map {
                    ContextBoostHotwordTrace(
                        text: $0.text,
                        score: $0.score,
                        source: $0.source.rawValue,
                        evidenceReasons: $0.evidence.map(\.reason)
                    )
                },
                source: "current_window_ocr",
                ttlSeconds: 120,
                ocrCharacterCount: snapshot.ocrCharacterCount,
                candidateCount: snapshot.candidateCount,
                appliedToLLMPrompt: !snapshot.hotwords.isEmpty,
                failureReason: nil
            )
        case .unavailable(let reason):
            return ContextBoostTrace(
                appName: target?.appName,
                bundleID: target?.bundleID,
                hotwords: [],
                source: "current_window_ocr",
                ttlSeconds: 0,
                ocrCharacterCount: nil,
                candidateCount: nil,
                appliedToLLMPrompt: false,
                failureReason: reason
            )
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

private extension ContextBoostCaptureOutcome {
    var snapshot: OCRContextSnapshot? {
        guard case .captured(let snapshot) = self else {
            return nil
        }
        return snapshot
    }
}

extension LLMRefiner: TextRefining, PromptAwareTextRefining {}
