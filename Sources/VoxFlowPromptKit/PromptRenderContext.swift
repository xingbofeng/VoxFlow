import Foundation

/// Variables made available to a `PromptTemplate` during rendering.
///
/// PromptKit catalogs declare the variables they consume via
/// `PromptRenderContext.variables`. Renderers substitute placeholders of the
/// form `{{variableName}}` with the provided values. Unknown placeholders are
/// left untouched so missing data is visible during testing rather than
/// silently dropped.
public struct PromptRenderContext: Sendable, Equatable {
    public let variables: [String: String]

    public init(variables: [String: String] = [:]) {
        self.variables = variables
    }

    public func value(for key: String) -> String? {
        variables[key]
    }

    public func merging(_ other: PromptRenderContext) -> PromptRenderContext {
        PromptRenderContext(variables: variables.merging(other.variables) { _, new in new })
    }
}

public extension PromptRenderContext {
    /// Convenience builder for Swift variadic-style usage.
    static func make(_ pairs: (String, String)...) -> PromptRenderContext {
        PromptRenderContext(variables: Dictionary(uniqueKeysWithValues: pairs))
    }
}
