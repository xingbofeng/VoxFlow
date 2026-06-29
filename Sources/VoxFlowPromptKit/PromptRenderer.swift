import Foundation
import CryptoKit

/// Renders `PromptTemplate` instances against `PromptRenderContext` values and
/// produces a `PromptRenderResult` carrying the rendered text plus the
/// metadata required for tracing.
///
/// The renderer is the single place where placeholder substitution and
/// rendered-prompt hashing happen, so every business module that goes through
/// PromptKit gets consistent behavior and a consistent hash format. Business
/// modules MUST NOT inline prompt strings or compute their own hashes.
public struct PromptRenderer: Sendable {
    public init() {}

    /// Renders `template` against `context`.
    ///
    /// Placeholders use the `{{name}}` form. Whitespace inside the braces is
    /// tolerated (`{{ name }}`). Unknown placeholders are left as-is so
    /// snapshot tests catch missing variables instead of hiding them.
    public func render(
        _ template: PromptTemplate,
        context: PromptRenderContext = PromptRenderContext()
    ) -> PromptRenderResult {
        let rendered = Self.substitute(template.body, with: context)
        return PromptRenderResult(
            template: template,
            renderedText: rendered,
            renderedHash: Self.sha256Hex(rendered)
        )
    }

    static func substitute(_ body: String, with context: PromptRenderContext) -> String {
        let pattern = #"\{\{\s*([A-Za-z0-9_]+)\s*\}\}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return body
        }
        let range = NSRange(body.startIndex..<body.endIndex, in: body)
        let nsBody = body as NSString
        var output = ""
        var cursor = 0
        for match in regex.matches(in: body, range: range) {
            if let matchRange = Range(match.range, in: body) {
                let prefixRange = NSRange(location: cursor, length: match.range.location - cursor)
                output += nsBody.substring(with: prefixRange)
                let fullMatch = String(body[matchRange])
                let key = fullMatch
                    .dropFirst(2)
                    .dropLast(2)
                    .trimmingCharacters(in: .whitespaces)
                if let value = context.value(for: key) {
                    output += value
                } else {
                    output += fullMatch
                }
                cursor = match.range.location + match.range.length
            }
        }
        if cursor < nsBody.length {
            let suffixRange = NSRange(location: cursor, length: nsBody.length - cursor)
            output += nsBody.substring(with: suffixRange)
        }
        return output
    }

    static func sha256Hex(_ text: String) -> String {
        let data = Data(text.utf8)
        let hash = SHA256.hash(data: data)
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    /// Hash an already-assembled rendered prompt string. Use this when the
    /// final system prompt is composed of multiple sections (base template +
    /// style polish + hotword/context sections) and the trace needs to
    /// identify the *exact* wording sent to the LLM, not just the base
    /// template. The kind/version still come from the template that anchors
    /// the request (e.g. `.voiceCorrection` / `.v1_0_0`).
    public static func hash(renderedPrompt: String) -> String {
        sha256Hex(renderedPrompt)
    }
}

/// The outcome of rendering a `PromptTemplate`.
///
/// `renderedText` is the final prompt sent to the LLM. `renderedHash` is a
/// SHA-256 hex digest of the rendered text, used by `PromptTraceMetadata` to
/// identify which exact wording was used without persisting the full prompt.
public struct PromptRenderResult: Sendable, Equatable {
    public let template: PromptTemplate
    public let renderedText: String
    public let renderedHash: String

    public var kind: PromptKind { template.kind }
    public var version: PromptVersion { template.version }
}
