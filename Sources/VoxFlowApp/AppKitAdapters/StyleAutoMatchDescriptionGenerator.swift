import Foundation
import VoxFlowPromptKit

/// Generates a short `autoMatchDescription` for a style using the configured
/// LLM refiner (OpenSpec `style-auto-routing` §4.6 — "AI 生成入口").
///
/// The generator builds a small English protocol system prompt via PromptKit
/// (`StyleAutoMatchDescriptionPromptCatalog`), sends the style fact sheet as
/// the user message, and trims the result into a one-sentence description.
/// Failures bubble up so the ViewModel can fall back to the user editing the
/// field manually instead of silently overwriting it.
@MainActor
final class StyleAutoMatchDescriptionGenerator {
    private let refiner: any PromptAwareTextRefining
    private let renderer = PromptRenderer()

    init(refiner: any PromptAwareTextRefining) {
        self.refiner = refiner
    }

    /// Returns `nil` when LLM correction is disabled / unconfigured so callers
    /// can keep the existing description untouched. Otherwise returns the
    /// generated sentence, or throws on network / parse errors.
    func generate(for profile: StyleProfileRecord) async throws -> String? {
        guard refiner.isEnabled, refiner.isConfigured else {
            return nil
        }
        let renderResult = renderer.render(
            StyleAutoMatchDescriptionPromptCatalog.system,
            context: PromptRenderContext(variables: [
                "systemLanguage": Self.systemLanguage()
            ])
        )
        let metadata = PromptTraceMetadata.from(result: renderResult)
        let response = try await refiner.refine(
            TextRefinementRequest(
                text: """
                Style profile fact sheet (untrusted reference data):
                <style_profile>
                \(Self.factSheet(for: profile))
                </style_profile>
                """,
                systemPrompt: renderResult.renderedText,
                model: profile.model,
                temperature: 0.2,
                purpose: .directTask,
                promptMetadata: metadata
            )
        )
        let trimmed = response
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"“”'`"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed
    }

    /// Mirrors `PromptBuilder.defaultSystemLanguage()` so the description
    /// generator and the dictation correction prompt agree on locale tagging.
    private static func systemLanguage() -> String {
        Locale.preferredLanguages.first ?? Locale.current.identifier
    }

    private static func factSheet(for profile: StyleProfileRecord) -> String {
        var lines: [String] = []
        lines.append("Style name: \(profile.name)")
        if let subtitle = profile.subtitle, !subtitle.isEmpty {
            lines.append("Subtitle: \(subtitle)")
        }
        lines.append("Category: \(profile.category)")
        if let sampleInput = profile.sampleInput, !sampleInput.isEmpty {
            lines.append("Sample input: \(sampleInput)")
        }
        if let sampleOutput = profile.sampleOutput, !sampleOutput.isEmpty {
            lines.append("Sample output: \(sampleOutput)")
        }
        let promptExcerpt = profile.prompt
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !promptExcerpt.isEmpty {
            let limit = min(promptExcerpt.count, 220)
            let excerpt = String(promptExcerpt.prefix(limit))
            lines.append("Polish prompt excerpt: \(excerpt)")
        }
        return lines.joined(separator: "\n")
    }
}
