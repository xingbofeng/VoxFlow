import Foundation

/// Identifies the kind of built-in protocol prompt managed by PromptKit.
///
/// PromptKit owns the protocol prompts (correction base, style router, agent
/// compose system prompt, tool descriptions, batch classification, context
/// wrappers). Style polish prompts remain user-editable and are not cataloged
/// here as protocol kinds.
public enum PromptKind: String, Sendable, Equatable, Codable {
    case voiceCorrection
    case structuredCorrection
    case styleRouter
    case agentCompose
    case toolDescription
    case batchStyleClassification
    case contextRounds
    case imageContext
}

/// Semantic version of a built-in prompt template.
///
/// Bumping the version is a deliberate, reviewable action that should be
/// accompanied by snapshot / regression test updates. The version is recorded
/// in `PromptTraceMetadata` so historical traces can explain which wording was
/// in effect at request time.
public struct PromptVersion: Sendable, Equatable, Codable, Hashable {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    public var stringValue: String {
        "\(major).\(minor).\(patch)"
    }
}

extension PromptVersion {
    /// Initial version for all migrated built-in prompts. The first PromptKit
    /// migration is required to preserve existing rendered behavior, so every
    /// catalog starts at `1.0.0` and only bumps once prompt content is
    /// intentionally upgraded in later tasks.
    public static let v1_0_0 = PromptVersion(major: 1, minor: 0, patch: 0)
}
