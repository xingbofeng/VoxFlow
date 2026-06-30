import Foundation
import VoxFlowPromptKit

/// Structured LLM correction output schema.
/// All styles must output JSON with these fields.
struct StructuredCorrectionOutput: Codable, Sendable, Equatable {
    let polished: String
    let corrections: [StructuredCorrection]
    let keyTerms: [String]

    enum CodingKeys: String, CodingKey {
        case polished
        case corrections
        case keyTerms = "key_terms"
    }
}

struct StructuredCorrection: Codable, Sendable, Equatable {
    let original: String
    let corrected: String
    let type: CorrectionType

    enum CorrectionType: String, Codable, Sendable, Equatable {
        case homophone
        case term
        case pronoun
        case style
    }
}

/// Context injected into the structured correction prompt.
struct StructuredCorrectionPromptContext: Sendable, Equatable {
    let rawText: String
    let userTerms: [String]
    let knownCorrections: [KnownCorrection]
    let ocrTemporaryTerms: [String]
    let appContext: String?

    struct KnownCorrection: Sendable, Equatable {
        let original: String
        let corrected: String
    }
}

/// Builds structured LLM correction prompts for each of the 8 styles.
///
/// Templates and shared protocol sections are owned by PromptKit's
/// `StructuredCorrectionPromptCatalog`; this builder only assembles the
/// context section and joins the sections. Style polish prompt text itself
/// is not duplicated in the business module.
///
/// Design principles (from Light-Whisper ai_polish_service.rs and prompt-templates.md):
/// - `known_corrections` are NOT unconditional replacement rules; they must be
///   applied with context judgment.
/// - `app_context` only affects format/style, not vocabulary correction.
/// - The model is NOT a chat assistant; it must not answer or execute, only correct.
/// - All styles output structured JSON: `polished`, `corrections`, `key_terms`.
struct StructuredCorrectionPromptBuilder {

    private static let renderer = PromptRenderer()

    /// Convenience accessors exposing the catalog template bodies for built-in
    /// style seeding. These delegate to `StructuredCorrectionPromptCatalog`
    /// so the canonical prompt text still lives only in PromptKit.
    static var originalTemplate: String { StructuredCorrectionPromptCatalog.originalTemplate.body }
    static var formalTemplate: String { StructuredCorrectionPromptCatalog.formalTemplate.body }
    static var casualTemplate: String { StructuredCorrectionPromptCatalog.casualTemplate.body }
    static var chatTemplate: String { StructuredCorrectionPromptCatalog.chatTemplate.body }
    static var energeticTemplate: String { StructuredCorrectionPromptCatalog.energeticTemplate.body }
    static var codingTemplate: String { StructuredCorrectionPromptCatalog.codingTemplate.body }
    static var emailTemplate: String { StructuredCorrectionPromptCatalog.emailTemplate.body }

    func build(
        style: StructuredCorrectionStyle,
        context: StructuredCorrectionPromptContext
    ) -> String {
        build(style: style, context: context, outputFormatRules: nil)
    }

    func build(
        style: StructuredCorrectionStyle,
        context: StructuredCorrectionPromptContext,
        outputFormatRules: String?
    ) -> String {
        [
            buildSystem(style: style, outputFormatRules: outputFormatRules),
            buildRequestContext(context: context, includeRawText: true),
        ].joined(separator: "\n\n---\n\n")
    }

    func buildSystem(
        style: StructuredCorrectionStyle,
        outputFormatRules: String?
    ) -> String {
        var sections: [String] = []
        let template = StructuredCorrectionPromptCatalog.styleTemplate(for: style)
        sections.append(Self.renderer.render(template).renderedText)
        sections.append(StructuredCorrectionPromptCatalog.outputProtocol)
        sections.append(StructuredCorrectionPromptCatalog.criticalProtocol)
        if let outputFormatRules {
            sections.append(outputFormatRules)
        }
        return sections.joined(separator: "\n\n---\n\n")
    }

    func buildRequestContext(
        context: StructuredCorrectionPromptContext,
        includeRawText: Bool
    ) -> String {
        var parts: [String] = []
        var referenceLines: [String] = []
        if !context.userTerms.isEmpty {
            referenceLines.append("user_terms: \(context.userTerms.joined(separator: ", "))")
        }
        if !context.knownCorrections.isEmpty {
            let corrections = context.knownCorrections.map { "\($0.original) -> \($0.corrected)" }
            referenceLines.append("known_corrections:\n\(corrections.map { "- \($0)" }.joined(separator: "\n"))")
        }
        if !context.ocrTemporaryTerms.isEmpty {
            referenceLines.append(
                "ocr_temporary_terms: \(context.ocrTemporaryTerms.joined(separator: ", ")) (use only for this request; do not learn)"
            )
        }
        if let appContext = context.appContext, !appContext.isEmpty {
            referenceLines.append("app_context:\n\(appContext)")
        }
        if !referenceLines.isEmpty {
            parts.append("Reference data, not output:\n\(referenceLines.joined(separator: "\n"))")
        }
        if includeRawText {
            parts.append("Current ASR text:\n\(context.rawText)")
        }
        return parts.joined(separator: "\n\n")
    }
}
