import Foundation

/// A versioned, immutable prompt template owned by PromptKit.
///
/// `PromptTemplate` holds the static template body and the version metadata
/// required for traceability. It does not perform variable substitution by
/// itself — `PromptRenderer` is responsible for rendering a template against a
/// `PromptRenderContext`. Keeping the template as a plain value type makes
/// snapshot tests and accidental drift detection straightforward.
public struct PromptTemplate: Sendable, Equatable {
    public let kind: PromptKind
    public let version: PromptVersion
    public let body: String

    public init(kind: PromptKind, version: PromptVersion, body: String) {
        self.kind = kind
        self.version = version
        self.body = body
    }
}
