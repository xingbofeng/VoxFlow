import Foundation
import VoxFlowContextBoost
import VoxFlowVoiceCorrection
import VoxFlowPromptKit
import VoxFlowTextProcessing

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

struct ConservativeRefinementGuard: Sendable {
    enum Decision: Equatable, Sendable {
        case accept
        case reject(String)
    }

    func validate(
        raw: String,
        refined: String,
        temporaryHotwords: [String]
    ) -> Decision {
        let rawTrimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let refinedTrimmed = refined.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !refinedTrimmed.isEmpty else {
            return .reject("empty")
        }
        guard !looksLikeExplanation(refinedTrimmed) else {
            return .reject("explanation")
        }
        guard preservedTokens(in: rawTrimmed).allSatisfy({ refinedTrimmed.contains($0) }) else {
            return .reject("protected_token_missing")
        }
        let introducedHotwords = temporaryHotwords.filter {
            !rawTrimmed.localizedCaseInsensitiveContains($0)
                && refinedTrimmed.localizedCaseInsensitiveContains($0)
        }
        guard introducedHotwords.count <= 1 else {
            return .reject("too_many_hotwords")
        }
        return .accept
    }

    private func looksLikeExplanation(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefixes = [
            "修改说明", "说明：", "说明:", "以下是", "标题：", "标题:",
            "我已", "已经帮你", "```", "# "
        ]
        return prefixes.contains { trimmed.hasPrefix($0) }
    }

    private func preservedTokens(in text: String) -> [String] {
        let patterns = [
            #"https?://[^\s，。！？、]+"#,
            #"(?:^|[\s，。])/[A-Za-z0-9._~/%+-]+"#,
            #"\b\d+(?:\.\d+)*\b"#,
            #"`[^`]+`"#
        ]
        return patterns.flatMap { matches(pattern: $0, in: text) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)) }
            .filter { !$0.isEmpty }
    }

    private func matches(pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard let swiftRange = Range(match.range, in: text) else { return nil }
            return String(text[swiftRange])
        }
    }

}

struct TextProcessingTrace: Equatable, Codable, Sendable {
    var llm: LLMRefinementTrace? = nil
    var output: OutputDeliveryTrace? = nil
    var contextBoost: ContextBoostTrace? = nil
    var voiceCorrection: VoiceCorrectionTrace? = nil
    var styleRoute: StyleRouteTrace? = nil
    var deterministic: DeterministicProcessingTrace? = nil

    func safeForPersistence() -> TextProcessingTrace {
        TextProcessingTrace(
            llm: llm?.safeForPersistence(),
            output: output,
            contextBoost: contextBoost?.safeForPersistence(),
            voiceCorrection: voiceCorrection?.safeForPersistence(),
            // StyleRouteTrace is safe (IDs, version, hash, latency, reason
            // code) but the raw routerResponse may echo model output that
            // could contain user-derived text on invalid responses, so it is
            // dropped during persistence.
            styleRoute: styleRoute?.safeForPersistence(),
            deterministic: deterministic?.safeForPersistence()
        )
    }
}

struct DeterministicProcessingTrace: Equatable, Codable, Sendable {
    let enabled: Bool
    let isCodingContext: Bool
    let preLLM: DeterministicProcessingPhaseTrace
    let postLLM: DeterministicProcessingPhaseTrace

    var changed: Bool { preLLM.changed || postLLM.changed }

    func safeForPersistence() -> DeterministicProcessingTrace {
        self
    }
}

struct DeterministicProcessingPhaseTrace: Equatable, Codable, Sendable {
    let phase: String
    let enabledProcessors: [String]
    let displayProcessorIDs: [String]?
    let changedProcessorIDs: [String]?
    let inputCharacterCount: Int
    let outputCharacterCount: Int
    let inputText: String?
    let outputText: String?
    let inputHash: String
    let outputHash: String

    var ran: Bool { !enabledProcessors.isEmpty }
    var changed: Bool { inputHash != outputHash }

    init(
        phase: String,
        enabledProcessors: [String],
        displayProcessorIDs: [String]? = nil,
        changedProcessorIDs: [String] = [],
        inputCharacterCount: Int,
        outputCharacterCount: Int,
        inputText: String? = nil,
        outputText: String? = nil,
        inputHash: String,
        outputHash: String
    ) {
        self.phase = phase
        self.enabledProcessors = enabledProcessors
        self.displayProcessorIDs = displayProcessorIDs
        self.changedProcessorIDs = changedProcessorIDs
        self.inputCharacterCount = inputCharacterCount
        self.outputCharacterCount = outputCharacterCount
        self.inputText = inputText
        self.outputText = outputText
        self.inputHash = inputHash
        self.outputHash = outputHash
    }
}

extension DeterministicProcessingPhaseTrace {
    var processorIDsForDisplay: [String] {
        displayProcessorIDs ?? enabledProcessors
    }

    var highlightedProcessorIDs: Set<String> {
        Set(enabledProcessors)
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
            hotwords: [],
            hotwordDetails: [],
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
    /// PromptKit trace metadata (prompt kind, version, rendered hash, styleID,
    /// routerVersion, agentPromptVersion). Safe to persist: contains no full
    /// prompt text or user content. `nil` for traces produced before PromptKit
    /// integration or by refiners that do not go through PromptKit.
    var promptMetadata: PromptTraceMetadata?

    init(
        providerID: String,
        providerName: String,
        endpoint: String,
        model: String,
        temperature: Double,
        timeoutSeconds: Double,
        requestBodyJSON: String,
        responseText: String? = nil,
        statusCode: Int? = nil,
        durationMS: Int? = nil,
        errorMessage: String? = nil,
        completedAt: Date? = nil,
        promptMetadata: PromptTraceMetadata? = nil
    ) {
        self.providerID = providerID
        self.providerName = providerName
        self.endpoint = endpoint
        self.model = model
        self.temperature = temperature
        self.timeoutSeconds = timeoutSeconds
        self.requestBodyJSON = requestBodyJSON
        self.responseText = responseText
        self.statusCode = statusCode
        self.durationMS = durationMS
        self.errorMessage = errorMessage
        self.completedAt = completedAt
        self.promptMetadata = promptMetadata
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.providerID = try c.decode(String.self, forKey: .providerID)
        self.providerName = try c.decode(String.self, forKey: .providerName)
        self.endpoint = try c.decode(String.self, forKey: .endpoint)
        self.model = try c.decode(String.self, forKey: .model)
        self.temperature = try c.decode(Double.self, forKey: .temperature)
        self.timeoutSeconds = try c.decode(Double.self, forKey: .timeoutSeconds)
        self.requestBodyJSON = try c.decode(String.self, forKey: .requestBodyJSON)
        self.responseText = try c.decodeIfPresent(String.self, forKey: .responseText)
        self.statusCode = try c.decodeIfPresent(Int.self, forKey: .statusCode)
        self.durationMS = try c.decodeIfPresent(Int.self, forKey: .durationMS)
        self.errorMessage = try c.decodeIfPresent(String.self, forKey: .errorMessage)
        self.completedAt = try c.decodeIfPresent(Date.self, forKey: .completedAt)
        // Backward-compatible: traces persisted before PromptKit integration
        // do not carry prompt metadata.
        self.promptMetadata = try c.decodeIfPresent(PromptTraceMetadata.self, forKey: .promptMetadata)
    }

    enum CodingKeys: String, CodingKey {
        case providerID
        case providerName
        case endpoint
        case model
        case temperature
        case timeoutSeconds
        case requestBodyJSON
        case responseText
        case statusCode
        case durationMS
        case errorMessage
        case completedAt
        case promptMetadata
    }

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
            completedAt: completedAt,
            // Metadata is safe (kind/version/hash/ids only — no full prompt or
            // user content), so it is preserved through redaction.
            promptMetadata: promptMetadata
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
    private let structuredPromptBuilder: StructuredCorrectionPromptBuilder?
    private let structuredLearningService: StructuredCorrectionLearningService?
    private let correctionTargetRepository: (any CorrectionTargetRepository)?
    private let correctionEvidenceRepository: (any CorrectionEvidenceRepository)?
    private let hotwordFileSyncService: HotwordFileSyncService?
    private let structuredLearningEnabled: () -> Bool
    private let voiceCorrectionProcessor: (any VoiceCorrectionTextProcessing)?
    private let contextBoostProvider: (any CurrentWindowOCRContextProviding)?
    /// Loads the current deterministic text processing settings. Returns
    /// `.defaults` (all-off no-op) when not configured, preserving current
    /// behavior for existing users and for pipelines without a settings store.
    private let deterministicSettingsProvider: @MainActor () -> DeterministicTextProcessingSettings
    private let contextBoostCoordinator: ContextBoostPrefetchCoordinator?
    private let contextBoostEnabled: @Sendable () -> Bool
    private let contextBoostSuppressed: @Sendable () -> Bool
    private let contextBoostTimeoutNanoseconds: UInt64

    init(
        refiner: any TextRefining,
        styleRepository: (any StyleRepository)? = nil,
        styleSelector: (any StyleSelecting)? = nil,
        promptBuilder: PromptBuilder = PromptBuilder(),
        structuredPromptBuilder: StructuredCorrectionPromptBuilder? = nil,
        structuredLearningService: StructuredCorrectionLearningService? = nil,
        correctionTargetRepository: (any CorrectionTargetRepository)? = nil,
        correctionEvidenceRepository: (any CorrectionEvidenceRepository)? = nil,
        hotwordFileSyncService: HotwordFileSyncService? = nil,
        structuredLearningEnabled: @escaping () -> Bool = { true },
        voiceCorrectionProcessor: (any VoiceCorrectionTextProcessing)? = nil,
        contextBoostProvider: (any CurrentWindowOCRContextProviding)? = nil,
        contextBoostCoordinator: ContextBoostPrefetchCoordinator? = nil,
        contextBoostEnabled: @escaping @Sendable () -> Bool = { ContextBoostSettings.isEnabled() },
        contextBoostSuppressed: @escaping @Sendable () -> Bool = { ContextBoostSuppression.isSuppressed() },
        contextBoostTimeoutNanoseconds: UInt64 = 1_000_000_000,
        deterministicSettingsProvider: @escaping @MainActor () -> DeterministicTextProcessingSettings = {
            // Default to disabled for tests and pipelines that don't explicitly
            // wire the provider. The real app (AppRuntime) passes a provider
            // that loads from storage with user-facing defaults (master on,
            // all processors on except longSentenceBreaking).
            DeterministicTextProcessingSettings(
                enabled: false,
                smartNumberRecognition: false,
                punctuationOptimization: false,
                longSentenceBreaking: false,
                fillerWordFiltering: false,
                cjkLatinSpacing: false,
                autoCapitalization: false
            )
        }
    ) {
        self.refiner = refiner
        self.styleRepository = styleRepository
        self.styleSelector = styleSelector
        self.promptBuilder = promptBuilder
        self.structuredPromptBuilder = structuredPromptBuilder
        self.structuredLearningService = structuredLearningService
        self.correctionTargetRepository = correctionTargetRepository
        self.correctionEvidenceRepository = correctionEvidenceRepository
        self.hotwordFileSyncService = hotwordFileSyncService
        self.structuredLearningEnabled = structuredLearningEnabled
        self.voiceCorrectionProcessor = voiceCorrectionProcessor
        self.contextBoostProvider = contextBoostProvider
        self.contextBoostCoordinator = contextBoostCoordinator
        self.contextBoostEnabled = contextBoostEnabled
        self.contextBoostSuppressed = contextBoostSuppressed
        self.contextBoostTimeoutNanoseconds = contextBoostTimeoutNanoseconds
        self.deterministicSettingsProvider = deterministicSettingsProvider
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

        // Deterministic pre-LLM processing: runs on the raw ASR text before
        // prompt rendering. Lightweight cleanup (filler filtering, smart
        // number recognition) that helps the LLM see a cleaner input. When
        // the deterministic settings are at defaults (all off), this is a
        // no-op, preserving current behavior.
        let deterministicSettings = deterministicSettingsProvider()
        let deterministicPipeline = DeterministicTextPipeline(settings: deterministicSettings)
        var isCodingContext = false
        var didRunDeterministicPreProcessing = false
        var didRunDeterministicPostProcessing = false
        var deterministicPreInput = text
        var deterministicPreOutput = text
        var deterministicPostInput = text
        var deterministicPostOutput = text

        if refiner.isEnabled, refiner.isConfigured {
            do {
                let contextBoostOutcome = correctionContext?.isSecureField == true
                    ? nil
                    : await captureContextBoostIfNeeded(target: target)
                let contextSnapshot = contextBoostOutcome?.snapshot
                contextBoostTrace = contextTrace(from: contextBoostOutcome, target: target)

                // Resolve style upfront so pre-LLM processing knows whether
                // this is a coding context (skip filler/capitalization) and
                // buildPrompt can reuse the same resolution without a second
                // router call.
                let resolvedStyle = try await resolveStyle(for: target)
                isCodingContext = resolvedStyle?.id == "builtin.coding"
                deterministicPreInput = text
                let preProcessedText = deterministicPipeline.preLLM(
                    text,
                    isCodingContext: isCodingContext
                )
                text = preProcessedText
                deterministicPreOutput = text
                didRunDeterministicPreProcessing = true

                let prompt = buildPrompt(
                    rawText: text,
                    style: resolvedStyle,
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
                        temperature: prompt.result.temperature,
                        promptMetadata: prompt.result.promptMetadata
                    )
                    if prompt.isStructured,
                       let traceableRefiner = refiner as? any TraceablePromptAwareTextRefining {
                        let traceResult = try await traceableRefiner.refineWithTrace(request)
                        refinedText = traceResult.text
                        localLLMProviderID = traceResult.providerID
                        localLLMTrace = traceResult.trace
                    } else if let traceableStreamingRefiner = refiner as? any TraceableStreamingPromptAwareTextRefining {
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
                let structuredParseResult = parseStructuredOutputIfNeeded(
                    refinedText,
                    isStructured: prompt.isStructured,
                    correctionContext: correctionContext
                )
                refinedText = structuredParseResult.text
                warnings.append(contentsOf: structuredParseResult.warnings)
                let trimmedRefinedText = refinedText.trimmingCharacters(in: .whitespacesAndNewlines)
                let refinementDecision = ConservativeRefinementGuard().validate(
                    raw: text,
                    refined: trimmedRefinedText,
                    temporaryHotwords: contextSnapshot?.hotwords.map(\.text) ?? []
                )
                switch refinementDecision {
                case .accept:
                    text = trimmedRefinedText
                case .reject:
                    warnings.append("llm_refinement_rejected")
                }
                // Deterministic post-LLM processing: runs on the accepted LLM
                // output before insertion. Handles punctuation normalization,
                // CJK-Latin spacing, long sentence breaking, and context-aware
                // capitalization. No-op when settings are at defaults.
                deterministicPostInput = text
                text = deterministicPipeline.postLLM(text, isCodingContext: isCodingContext)
                deterministicPostOutput = text
                didRunDeterministicPostProcessing = true
                llmProviderID = localLLMProviderID ?? (refiner as? any ActiveLLMProviderIdentifying)?.activeProviderID
                styleID = promptMetadata?.styleID
                trace = TextProcessingTrace(
                    llm: localLLMTrace ?? (refiner as? RefinementTraceProviding)?.lastTrace,
                    contextBoost: contextBoostTrace,
                    styleRoute: styleSelector?.lastRouteTrace
                )
            } catch {
                AppLogger.general.error("LLM refinement failed: \(error.localizedDescription)")
                warnings.append("llm_refinement_failed")
                trace = TextProcessingTrace(
                    llm: (refiner as? RefinementTraceProviding)?.lastTrace,
                    contextBoost: contextBoostTrace,
                    styleRoute: styleSelector?.lastRouteTrace
                )
            }
        }

        if !didRunDeterministicPostProcessing {
            if !didRunDeterministicPreProcessing {
                deterministicPreInput = text
                text = deterministicPipeline.preLLM(text, isCodingContext: isCodingContext)
                deterministicPreOutput = text
                didRunDeterministicPreProcessing = true
            }
            deterministicPostInput = text
            text = deterministicPipeline.postLLM(text, isCodingContext: isCodingContext)
            deterministicPostOutput = text
            didRunDeterministicPostProcessing = true
        }

        var deterministicUpdatedTrace = trace ?? TextProcessingTrace()
        deterministicUpdatedTrace.deterministic = deterministicTrace(
            settings: deterministicSettings,
            isCodingContext: isCodingContext,
            preInput: deterministicPreInput,
            preOutput: deterministicPreOutput,
            postInput: deterministicPostInput,
            postOutput: deterministicPostOutput
        )
        trace = deterministicUpdatedTrace

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

    private func deterministicTrace(
        settings: DeterministicTextProcessingSettings,
        isCodingContext: Bool,
        preInput: String,
        preOutput: String,
        postInput: String,
        postOutput: String
    ) -> DeterministicProcessingTrace {
        let effective = settings.effectiveSettings()
        let pipeline = DeterministicTextPipeline(settings: effective)
        let preSteps = pipeline.preLLMSteps(preInput, isCodingContext: isCodingContext)
        let postSteps = pipeline.postLLMSteps(postInput, isCodingContext: isCodingContext)
        return DeterministicProcessingTrace(
            enabled: effective.enabled,
            isCodingContext: isCodingContext,
            preLLM: DeterministicProcessingPhaseTrace(
                phase: "pre_llm",
                enabledProcessors: preSteps.map(\.id),
                displayProcessorIDs: effective.enabled ? Self.preLLMProcessorIDs : [],
                changedProcessorIDs: preSteps.filter(\.changed).map(\.id),
                inputCharacterCount: preInput.count,
                outputCharacterCount: preOutput.count,
                inputText: preInput,
                outputText: preOutput,
                inputHash: PromptRenderer.hash(renderedPrompt: preInput),
                outputHash: PromptRenderer.hash(renderedPrompt: preOutput)
            ),
            postLLM: DeterministicProcessingPhaseTrace(
                phase: "post_llm",
                enabledProcessors: postSteps.map(\.id),
                displayProcessorIDs: effective.enabled ? Self.postLLMProcessorIDs : [],
                changedProcessorIDs: postSteps.filter(\.changed).map(\.id),
                inputCharacterCount: postInput.count,
                outputCharacterCount: postOutput.count,
                inputText: postInput,
                outputText: postOutput,
                inputHash: PromptRenderer.hash(renderedPrompt: postInput),
                outputHash: PromptRenderer.hash(renderedPrompt: postOutput)
            )
        )
    }

    private static let preLLMProcessorIDs = [
        "filler_word_filtering",
        "smart_number_recognition",
    ]

    private static let postLLMProcessorIDs = [
        "punctuation_optimization",
        "cjk_latin_spacing",
        "long_sentence_breaking",
        "auto_capitalization",
    ]

    /// Resolves the style profile for the given target. Delegates to the
    /// style selector when present (which may consult manual rules, the AI
    /// router, or fall back to the default), otherwise queries the repository
    /// for the default profile. Returns nil when no profile is available.
    private func resolveStyle(for target: DictationTarget?) async throws -> StyleProfileRecord? {
        if let styleSelector {
            return try await styleSelector.style(for: target)
        }
        return try styleRepository?.defaultProfile()
    }

    private func buildPrompt(
        rawText: String,
        style: StyleProfileRecord?,
        target: DictationTarget?,
        temporaryHotwords: [TemporaryHotword] = []
    ) -> (result: PromptBuildResult, warnings: [String], isStructured: Bool) {
        if let structuredPromptBuilder {
            do {
                return (
                    try buildStructuredPrompt(
                        builder: structuredPromptBuilder,
                        style: style,
                        rawText: rawText,
                        target: target,
                        temporaryHotwords: temporaryHotwords
                    ),
                    [],
                    true
                )
            } catch {
                return (
                    buildStructuredFallbackPrompt(
                        builder: structuredPromptBuilder,
                        rawText: rawText,
                        target: target,
                        temporaryHotwords: temporaryHotwords
                    ),
                    ["prompt_context_failed"],
                    true
                )
            }
        }
        return (
            promptBuilder.build(
                style: style,
                temporaryHotwords: temporaryHotwords
            ),
            [],
            false
        )
    }

    private func buildStructuredPrompt(
        builder: StructuredCorrectionPromptBuilder,
        style: StyleProfileRecord?,
        rawText: String,
        target: DictationTarget?,
        temporaryHotwords: [TemporaryHotword]
    ) throws -> PromptBuildResult {
        let enabledStyle = style?.enabled == true ? style : nil
        let structuredStyle = structuredStyle(for: enabledStyle)
        let context = StructuredCorrectionPromptContext(
            rawText: rawText,
            userTerms: try structuredUserTerms(limit: 50),
            knownCorrections: try structuredKnownCorrections(rawText: rawText, limit: 12),
            ocrTemporaryTerms: temporaryHotwords.map(\.text),
            appContext: structuredAppContext(target: target)
        )
        let systemPrompt = builder.build(style: structuredStyle, context: context)
        let template = StructuredCorrectionPromptCatalog.styleTemplate(for: structuredStyle)
        let metadata = PromptTraceMetadata(
            promptKind: template.kind,
            promptVersion: template.version,
            // Hash the *actual* sent prompt (style template + critical/output
            // protocol + context section), not just the style template, so
            // the trace identifies the exact wording used for this request.
            renderedPromptHash: PromptRenderer.hash(renderedPrompt: systemPrompt),
            styleID: enabledStyle?.id,
            routerVersion: nil,
            agentPromptVersion: nil
        )
        return PromptBuildResult(
            systemPrompt: systemPrompt,
            llmProviderID: enabledStyle?.llmProviderID,
            styleID: enabledStyle?.id,
            model: enabledStyle?.model?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                ? enabledStyle?.model
                : nil,
            temperature: enabledStyle?.temperature,
            promptMetadata: metadata
        )
    }

    private func buildStructuredFallbackPrompt(
        builder: StructuredCorrectionPromptBuilder,
        rawText: String,
        target: DictationTarget?,
        temporaryHotwords: [TemporaryHotword]
    ) -> PromptBuildResult {
        let context = StructuredCorrectionPromptContext(
            rawText: rawText,
            userTerms: [],
            knownCorrections: [],
            ocrTemporaryTerms: temporaryHotwords.map(\.text),
            appContext: structuredAppContext(target: target)
        )
        let systemPrompt = builder.build(style: .default, context: context)
        let template = StructuredCorrectionPromptCatalog.styleTemplate(for: .default)
        let metadata = PromptTraceMetadata(
            promptKind: template.kind,
            promptVersion: template.version,
            renderedPromptHash: PromptRenderer.hash(renderedPrompt: systemPrompt),
            styleID: nil,
            routerVersion: nil,
            agentPromptVersion: nil
        )
        return PromptBuildResult(
            systemPrompt: systemPrompt,
            llmProviderID: nil,
            styleID: nil,
            model: nil,
            temperature: nil,
            promptMetadata: metadata
        )
    }

    private func structuredStyle(for style: StyleProfileRecord?) -> StructuredCorrectionStyle {
        switch style?.id {
        case "builtin.energetic":
            return .energetic
        case "builtin.email":
            return .email
        case "builtin.coding":
            return .coding
        case "builtin.formal":
            return .formal
        case "builtin.original":
            return .original
        case "builtin.casual":
            return .casual
        case "builtin.chat":
            return .chat
        default:
            return .default
        }
    }

    private func structuredUserTerms(limit: Int) throws -> [String] {
        guard let correctionTargetRepository else { return [] }
        return try correctionTargetRepository.listHotwords()
            .prefix(limit)
            .map(\.text)
    }

    private func structuredKnownCorrections(
        rawText: String,
        limit: Int
    ) throws -> [StructuredCorrectionPromptContext.KnownCorrection] {
        guard let correctionEvidenceRepository else { return [] }
        return try correctionEvidenceRepository.relevantKnownCorrections(
            for: rawText,
            limit: limit
        )
    }

    private func structuredAppContext(target: DictationTarget?) -> String? {
        let parts = [
            target?.appName.map { "应用：\($0)" },
            target?.bundleID.map { "Bundle ID：\($0)" },
        ].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: "\n")
    }

    private func parseStructuredOutputIfNeeded(
        _ refinedText: String,
        isStructured: Bool,
        correctionContext: CorrectionContext?
    ) -> (text: String, warnings: [String]) {
        guard isStructured else { return (refinedText, []) }
        switch StructuredCorrectionParser.parse(refinedText) {
        case .success(let output):
            learnFromStructuredOutputIfNeeded(output, correctionContext: correctionContext)
            return (output.polished, [])
        case .fallback(let rawText, let reason):
            return (rawText, [reason])
        }
    }

    private func learnFromStructuredOutputIfNeeded(
        _ output: StructuredCorrectionOutput,
        correctionContext: CorrectionContext?
    ) {
        guard structuredLearningEnabled(),
              correctionContext?.mode == .dictation,
              correctionContext?.isFinalTranscript == true,
              correctionContext?.isSecureField == false,
              let structuredLearningService else {
            return
        }
        let outcome = structuredLearningService.learn(from: output)
        if outcome.promotedHotwords.isEmpty == false {
            hotwordFileSyncService?.writeBackFromRepository()
        }
        if outcome.shouldNotifyVocabularyChange {
            NotificationCenter.default.post(name: .correctionVocabularyDidChange, object: outcome)
        }
        AppLogger.dictation.info(
            "structured_correction_learning keyTerms=\(output.keyTerms.count) " +
            "promoted=\(outcome.promotedHotwords.count) drawer=\(outcome.drawerCandidates.count)"
        )
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

private extension LearningOutcome {
    var shouldNotifyVocabularyChange: Bool {
        if promotedHotwords.isEmpty == false || drawerCandidates.isEmpty == false {
            return true
        }
        if keyTermResults.contains(where: { $0.action == .counting || $0.action == .enteredDrawer }) {
            return true
        }
        return correctionResults.contains { $0.action == .learned }
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
