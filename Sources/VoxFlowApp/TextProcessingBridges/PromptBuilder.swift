import Foundation
import VoxFlowContextBoost
import VoxFlowPromptKit

enum TextRefinementPurpose: Equatable {
    case dictationCorrection
    case agentCompose
    case directTask
}

struct TextRefinementRequest: Equatable {
    let text: String
    let systemPrompt: String
    let model: String?
    let temperature: Double?
    let promptMetadata: PromptTraceMetadata?

    init(
        text: String,
        systemPrompt: String,
        model: String?,
        temperature: Double?,
        purpose: TextRefinementPurpose = .dictationCorrection,
        promptMetadata: PromptTraceMetadata? = nil
    ) {
        self.text = text
        self.systemPrompt = systemPrompt
        self.model = model
        self.temperature = temperature
        self.purpose = purpose
        self.promptMetadata = promptMetadata
    }

    let purpose: TextRefinementPurpose
}

struct PromptBuildResult: Equatable {
    let systemPrompt: String
    let requestContext: String?
    let llmProviderID: String?
    let styleID: String?
    let model: String?
    let temperature: Double?
    let promptMetadata: PromptTraceMetadata?

    init(
        systemPrompt: String,
        requestContext: String? = nil,
        llmProviderID: String?,
        styleID: String?,
        model: String?,
        temperature: Double?,
        promptMetadata: PromptTraceMetadata? = nil
    ) {
        self.systemPrompt = systemPrompt
        self.requestContext = requestContext
        self.llmProviderID = llmProviderID
        self.styleID = styleID
        self.model = model
        self.temperature = temperature
        self.promptMetadata = promptMetadata
    }
}

struct PromptBuilder {
    private static let logger = AppLogger.dictation
    private static let renderer = PromptRenderer()
    private let systemLanguage: String

    init(systemLanguage: String = Self.defaultSystemLanguage()) {
        self.systemLanguage = systemLanguage
    }

    /// The base conservative dictation prompt, rendered through PromptKit.
    /// Preserved verbatim from the previous inlined string during migration;
    /// see `VoiceCorrectionPromptCatalog.base`.
    static var conservativeSystemPrompt: String {
        renderer.render(
            VoiceCorrectionPromptCatalog.base,
            context: PromptRenderContext.make(("systemLanguage", defaultSystemLanguage()))
        ).renderedText
    }

    func build(
        style: StyleProfileRecord?,
        temporaryHotwords: [TemporaryHotword] = []
    ) -> PromptBuildResult {
        Self.logger.debug(
            "PromptBuilder build start: styleProvided=\(style != nil), enabled=\(style?.enabled == true), hotwordCount=\(temporaryHotwords.count)"
        )
        let baseRender = Self.renderer.render(
            VoiceCorrectionPromptCatalog.base,
            context: PromptRenderContext.make(("systemLanguage", systemLanguage))
        )
        var sections = [baseRender.renderedText]
        let enabledStyle = style?.enabled == true ? style : nil

        if let enabledStyle {
            sections.append(
                """
                Selected style:
                \(enabledStyle.prompt)
                """
            )
        }

        if let contextSection = ContextBoostPromptSectionBuilder().build(hotwords: temporaryHotwords) {
            sections.append(contextSection)
        }

        let systemPrompt = sections.joined(separator: "\n\n")
        let metadata = PromptTraceMetadata(
            promptKind: VoiceCorrectionPromptCatalog.base.kind,
            promptVersion: VoiceCorrectionPromptCatalog.base.version,
            // Hash the *actual* sent prompt (base + style polish + hotword
            // context), not just the base template, so the trace identifies
            // the exact wording used for this request.
            renderedPromptHash: PromptRenderer.hash(renderedPrompt: systemPrompt),
            styleID: enabledStyle?.id,
            routerVersion: nil,
            agentPromptVersion: nil
        )
        let result = PromptBuildResult(
            systemPrompt: systemPrompt,
            llmProviderID: enabledStyle?.llmProviderID,
            styleID: enabledStyle?.id,
            model: enabledStyle?.model?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                ? enabledStyle?.model
                : nil,
            temperature: enabledStyle?.temperature,
            promptMetadata: metadata
        )
        Self.logger.debug(
            "PromptBuilder build completed: promptLength=\(result.systemPrompt.count), " +
            "styleID=\(result.styleID ?? "-"), model=\(result.model ?? "-"), temperature=\(String(describing: result.temperature))"
        )
        return result
    }

    private static func defaultSystemLanguage() -> String {
        Locale.preferredLanguages.first ?? Locale.current.identifier
    }
}

protocol PromptAwareTextRefining: TextRefining {
    func refine(_ request: TextRefinementRequest) async throws -> String
}

protocol StructuredLineTranslationSupporting {
    var supportsStructuredLineTranslation: Bool { get }
}

protocol StreamingPromptAwareTextRefining: PromptAwareTextRefining {
    func refineStream(_ request: TextRefinementRequest) -> AsyncThrowingStream<String, Error>
}
