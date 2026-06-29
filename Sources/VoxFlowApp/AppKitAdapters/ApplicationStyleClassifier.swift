import Foundation
import VoxFlowPromptKit

/// Minimal trace for a single AI style-router call.
///
/// Section 2 requires the router trace to record candidates, response,
/// router version and latency. Full `styleSelectionSource` (manualRule /
/// aiRouteCache / aiRouter / default / fallback) and route cache are
/// section 5 work; this struct only captures what the classifier itself
/// observes so `TextProcessingTrace` can explain router decisions.
struct StyleRouteTrace: Equatable, Codable, Sendable {
    let candidateStyleIDs: [String]
    let routerResponse: String?
    let selectedStyleID: String?
    let fallbackReason: String?
    let routerVersion: String
    let renderedPromptHash: String
    let durationMS: Int?

    /// Returns a persistence-safe copy. The raw `routerResponse` is dropped
    /// because invalid model output could echo user-derived text; the
    /// `selectedStyleID` and `fallbackReason` (a short code) are retained.
    func safeForPersistence() -> StyleRouteTrace {
        StyleRouteTrace(
            candidateStyleIDs: candidateStyleIDs,
            routerResponse: nil,
            selectedStyleID: selectedStyleID,
            fallbackReason: fallbackReason,
            routerVersion: routerVersion,
            renderedPromptHash: renderedPromptHash,
            durationMS: durationMS
        )
    }
}

protocol ApplicationStyleClassifying: AnyObject, Sendable {
    func classify(target: DictationTarget, styles: [StyleProfileRecord]) async throws -> String?
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
        try await classifyWithTrace(target: target, styles: styles).styleID
    }

    /// Returns the selected style ID plus a route trace capturing candidates,
    /// router response, latency and fallback reason.
    func classifyWithTrace(
        target: DictationTarget,
        styles: [StyleProfileRecord]
    ) async throws -> (styleID: String?, trace: StyleRouteTrace) {
        guard refiner.isEnabled, refiner.isConfigured else {
            logger.debug("LLMApplicationStyleClassifier skip: refiner not ready")
            let trace = StyleRouteTrace(
                candidateStyleIDs: styles.filter(\.enabled).map(\.id),
                routerResponse: nil,
                selectedStyleID: nil,
                fallbackReason: "refiner_not_ready",
                routerVersion: StyleRouterPromptCatalog.system.version.stringValue,
                renderedPromptHash: "",
                durationMS: nil
            )
            lastRouteTrace = trace
            return (nil, trace)
        }
        let enabledStyles = styles.filter(\.enabled)
        let candidateIDs = enabledStyles.map(\.id)
        let candidates = enabledStyles
            .map { "\($0.id): \($0.name) - \($0.subtitle ?? $0.category)" }
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
                    text: "应用名：\(target.appName ?? "未知")\nBundle ID：\(target.bundleID ?? "未知")",
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
                routerVersion: StyleRouterPromptCatalog.system.version.stringValue,
                renderedPromptHash: renderResult.renderedHash,
                durationMS: durationMS
            )
            lastRouteTrace = trace
            logger.warning("LLMApplicationStyleClassifier request failed: \(error.localizedDescription)")
            return (nil, trace)
        }
        let durationMS = Int(Date().timeIntervalSince(startedAt) * 1000)
        let selectedID = response.trimmingCharacters(in: .whitespacesAndNewlines)
        let isValid = enabledStyles.contains { $0.id == selectedID }
        let trace = StyleRouteTrace(
            candidateStyleIDs: candidateIDs,
            routerResponse: selectedID,
            selectedStyleID: isValid ? selectedID : nil,
            fallbackReason: isValid ? nil : "invalid_response",
            routerVersion: StyleRouterPromptCatalog.system.version.stringValue,
            renderedPromptHash: renderResult.renderedHash,
            durationMS: durationMS
        )
        lastRouteTrace = trace
        if isValid {
            logger.debug("LLMApplicationStyleClassifier hit selectedStyle=\(selectedID) durationMS=\(durationMS)")
            return (selectedID, trace)
        }
        logger.warning("LLMApplicationStyleClassifier invalid selectedStyle=\(selectedID) durationMS=\(durationMS)")
        return (nil, trace)
    }
}
