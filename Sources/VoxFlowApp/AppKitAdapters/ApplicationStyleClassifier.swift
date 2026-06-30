import Foundation
import VoxFlowPromptKit

/// Minimal trace for a single AI style-router call.
///
/// Records a style-router decision without retaining user transcript text.
struct StyleRouteTrace: Equatable, Codable, Sendable {
    let candidateStyleIDs: [String]
    let routerResponse: String?
    let selectedStyleID: String?
    let fallbackReason: String?
    let styleSelectionSource: String?
    let routerVersion: String
    let renderedPromptHash: String
    let durationMS: Int?

    init(
        candidateStyleIDs: [String],
        routerResponse: String?,
        selectedStyleID: String?,
        fallbackReason: String?,
        styleSelectionSource: String? = nil,
        routerVersion: String,
        renderedPromptHash: String,
        durationMS: Int?
    ) {
        self.candidateStyleIDs = candidateStyleIDs
        self.routerResponse = routerResponse
        self.selectedStyleID = selectedStyleID
        self.fallbackReason = fallbackReason
        self.styleSelectionSource = styleSelectionSource
        self.routerVersion = routerVersion
        self.renderedPromptHash = renderedPromptHash
        self.durationMS = durationMS
    }

    private enum CodingKeys: String, CodingKey {
        case candidateStyleIDs
        case routerResponse
        case selectedStyleID
        case fallbackReason
        case styleSelectionSource
        case routerVersion
        case renderedPromptHash
        case durationMS
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        candidateStyleIDs = try container.decode([String].self, forKey: .candidateStyleIDs)
        routerResponse = try container.decodeIfPresent(String.self, forKey: .routerResponse)
        selectedStyleID = try container.decodeIfPresent(String.self, forKey: .selectedStyleID)
        fallbackReason = try container.decodeIfPresent(String.self, forKey: .fallbackReason)
        styleSelectionSource = try container.decodeIfPresent(String.self, forKey: .styleSelectionSource)
        routerVersion = try container.decode(String.self, forKey: .routerVersion)
        renderedPromptHash = try container.decode(String.self, forKey: .renderedPromptHash)
        durationMS = try container.decodeIfPresent(Int.self, forKey: .durationMS)
    }

    /// Returns a persistence-safe copy. The raw `routerResponse` is dropped
    /// because invalid model output could echo user-derived text; the
    /// `selectedStyleID` and `fallbackReason` (a short code) are retained.
    func safeForPersistence() -> StyleRouteTrace {
        StyleRouteTrace(
            candidateStyleIDs: candidateStyleIDs,
            routerResponse: nil,
            selectedStyleID: selectedStyleID,
            fallbackReason: fallbackReason,
            styleSelectionSource: styleSelectionSource,
            routerVersion: routerVersion,
            renderedPromptHash: renderedPromptHash,
            durationMS: durationMS
        )
    }
}

protocol ApplicationStyleClassifying: AnyObject, Sendable {
    func classify(target: DictationTarget, styles: [StyleProfileRecord]) async throws -> String?
    func classify(target: DictationTarget, transcript: String?, styles: [StyleProfileRecord]) async throws -> String?
}

extension ApplicationStyleClassifying {
    func classify(target: DictationTarget, transcript: String?, styles: [StyleProfileRecord]) async throws -> String? {
        try await classify(target: target, styles: styles)
    }
}

final class LLMApplicationStyleClassifier: ApplicationStyleClassifying, @unchecked Sendable {
    private let refiner: any PromptAwareTextRefining
    private let logger = AppLogger.dictation
    private let renderer = PromptRenderer()
    private(set) var lastRouteTrace: StyleRouteTrace?

    init(refiner: any PromptAwareTextRefining) {
        self.refiner = refiner
    }

    func classify(target: DictationTarget, styles: [StyleProfileRecord]) async throws -> String? {
        try await classifyWithTrace(target: target, transcript: nil, styles: styles).styleID
    }

    func classify(target: DictationTarget, transcript: String?, styles: [StyleProfileRecord]) async throws -> String? {
        try await classifyWithTrace(target: target, transcript: transcript, styles: styles).styleID
    }

    /// Returns the selected style ID plus a route trace capturing candidates,
    /// router response, latency and fallback reason.
    func classifyWithTrace(
        target: DictationTarget,
        transcript: String? = nil,
        styles: [StyleProfileRecord]
    ) async throws -> (styleID: String?, trace: StyleRouteTrace) {
        let candidateStyles = styles.filter(\.isEligibleForAutoRouter)
        let candidateIDs = candidateStyles.map(\.id)
        guard refiner.isEnabled, refiner.isConfigured else {
            logger.debug("LLMApplicationStyleClassifier skip: refiner not ready")
            let trace = StyleRouteTrace(
                candidateStyleIDs: candidateIDs,
                routerResponse: nil,
                selectedStyleID: nil,
                fallbackReason: "refiner_not_ready",
                styleSelectionSource: "fallback",
                routerVersion: StyleRouterPromptCatalog.system.version.stringValue,
                renderedPromptHash: "",
                durationMS: nil
            )
            lastRouteTrace = trace
            return (nil, trace)
        }
        guard !candidateStyles.isEmpty else {
            let trace = StyleRouteTrace(
                candidateStyleIDs: [],
                routerResponse: nil,
                selectedStyleID: nil,
                fallbackReason: "no_candidates",
                styleSelectionSource: "fallback",
                routerVersion: StyleRouterPromptCatalog.system.version.stringValue,
                renderedPromptHash: "",
                durationMS: nil
            )
            lastRouteTrace = trace
            return (nil, trace)
        }

        let candidates = candidateStyles.enumerated()
            .map { index, style in "\(index + 1). \(style.autoMatchDescription ?? style.name)" }
            .joined(separator: "\n")
        logger.debug("LLMApplicationStyleClassifier request candidateCount=\(candidates.count)")
        let renderResult = renderer.render(
            StyleRouterPromptCatalog.system,
            context: PromptRenderContext(variables: ["candidates": candidates])
        )
        let systemPrompt = renderResult.renderedText
        let metadata = PromptTraceMetadata.from(
            result: renderResult,
            routerVersion: StyleRouterPromptCatalog.system.version.stringValue
        )
        let startedAt = Date()
        let response: String
        do {
            response = try await refiner.refine(
                TextRefinementRequest(
                    text: Self.userPrompt(target: target, transcript: transcript),
                    systemPrompt: systemPrompt,
                    model: nil,
                    temperature: nil,
                    purpose: .directTask,
                    promptMetadata: metadata
                )
            )
        } catch {
            let durationMS = Int(Date().timeIntervalSince(startedAt) * 1000)
            let trace = StyleRouteTrace(
                candidateStyleIDs: candidateIDs,
                routerResponse: nil,
                selectedStyleID: nil,
                fallbackReason: "request_failed",
                styleSelectionSource: "fallback",
                routerVersion: StyleRouterPromptCatalog.system.version.stringValue,
                renderedPromptHash: renderResult.renderedHash,
                durationMS: durationMS
            )
            lastRouteTrace = trace
            logger.warning("LLMApplicationStyleClassifier request failed: \(error.localizedDescription)")
            return (nil, trace)
        }
        let durationMS = Int(Date().timeIntervalSince(startedAt) * 1000)
        let selectedOutput = response.trimmingCharacters(in: .whitespacesAndNewlines)
        let selectedStyleID = Self.parseRouterOutput(selectedOutput, candidates: candidateStyles)
        let trace = StyleRouteTrace(
            candidateStyleIDs: candidateIDs,
            routerResponse: selectedOutput,
            selectedStyleID: selectedStyleID,
            fallbackReason: selectedStyleID == nil ? Self.fallbackReason(for: selectedOutput) : nil,
            styleSelectionSource: selectedStyleID == nil ? "fallback" : "aiRouter",
            routerVersion: StyleRouterPromptCatalog.system.version.stringValue,
            renderedPromptHash: renderResult.renderedHash,
            durationMS: durationMS
        )
        lastRouteTrace = trace
        if let selectedStyleID {
            logger.debug("LLMApplicationStyleClassifier hit selectedStyle=\(selectedStyleID) durationMS=\(durationMS)")
            return (selectedStyleID, trace)
        }
        logger.warning("LLMApplicationStyleClassifier fallback response=\(selectedOutput) durationMS=\(durationMS)")
        return (nil, trace)
    }

    private static func userPrompt(target: DictationTarget, transcript: String?) -> String {
        """
        Current app context:
        App name: \(target.appName ?? "unknown")
        Bundle ID: \(target.bundleID ?? "unknown")
        Window title: \(target.windowTitle ?? "unknown")

        Transcript:
        \(transcript?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? transcript! : "[not provided]")
        """
    }

    private static func parseRouterOutput(_ output: String, candidates: [StyleProfileRecord]) -> String? {
        guard output != "fallback" else { return nil }
        guard let index = Int(output), (1...candidates.count).contains(index) else {
            return nil
        }
        return candidates[index - 1].id
    }

    private static func fallbackReason(for output: String) -> String {
        output == "fallback" || output.isEmpty ? "fallback" : "invalid_response"
    }
}
