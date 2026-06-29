import Foundation

/// Trace metadata recorded for every PromptKit-rendered LLM request.
///
/// Default persistence stores this struct (or its Codable projection) but
/// MUST NOT store the full rendered prompt, full user content, or full image
/// base64. `renderedPromptHash` lets historical traces explain which exact
/// wording was used without retaining sensitive content.
public struct PromptTraceMetadata: Codable, Equatable, Sendable {
    public let promptKind: String
    public let promptVersion: String
    public let renderedPromptHash: String
    public let styleID: String?
    public let routerVersion: String?
    public let agentPromptVersion: String?

    public init(
        promptKind: PromptKind,
        promptVersion: PromptVersion,
        renderedPromptHash: String,
        styleID: String? = nil,
        routerVersion: String? = nil,
        agentPromptVersion: String? = nil
    ) {
        self.promptKind = promptKind.rawValue
        self.promptVersion = promptVersion.stringValue
        self.renderedPromptHash = renderedPromptHash
        self.styleID = styleID
        self.routerVersion = routerVersion
        self.agentPromptVersion = agentPromptVersion
    }

    /// Codable-friendly initializer that accepts already-serialized field
    /// values. Used by persistence layers and tests that decode stored traces.
    public init(
        promptKind: String,
        promptVersion: String,
        renderedPromptHash: String,
        styleID: String?,
        routerVersion: String?,
        agentPromptVersion: String?
    ) {
        self.promptKind = promptKind
        self.promptVersion = promptVersion
        self.renderedPromptHash = renderedPromptHash
        self.styleID = styleID
        self.routerVersion = routerVersion
        self.agentPromptVersion = agentPromptVersion
    }
}

public extension PromptTraceMetadata {
    /// Build trace metadata directly from a `PromptRenderResult`.
    static func from(
        result: PromptRenderResult,
        styleID: String? = nil,
        routerVersion: String? = nil,
        agentPromptVersion: String? = nil
    ) -> PromptTraceMetadata {
        PromptTraceMetadata(
            promptKind: result.kind,
            promptVersion: result.version,
            renderedPromptHash: result.renderedHash,
            styleID: styleID,
            routerVersion: routerVersion,
            agentPromptVersion: agentPromptVersion
        )
    }
}
