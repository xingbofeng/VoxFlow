import Foundation

/// Settings for deterministic (non-LLM) text processing in ordinary dictation.
///
/// These settings control a pre-LLM and post-LLM text processing pipeline
/// that runs independently of the LLM correction. By default the master
/// switch is on and all processors are enabled except `longSentenceBreaking`,
/// which is more intrusive and is opt-in. This gives new users a better
/// out-of-box experience while keeping the breaking-into-lines behavior
/// conservative.
///
/// Migration: an earlier version of these settings defaulted every toggle to
/// off. Users who saved settings under that version have an on-disk payload
/// with all toggles off. To migrate them to the new "sensible defaults"
/// behavior without overwriting their explicit choices, the store checks for
/// the legacy all-off payload (see `DeterministicTextProcessingSettingsStore`)
/// and replaces it with `.defaults` on first load. Subsequent saves write a
/// `schemaVersion` so future migrations can be keyed off it.
public struct DeterministicTextProcessingSettings: Sendable, Equatable, Codable {
    /// Schema version for forward migrations. Defaults to 0 for payloads
    /// saved before the version field existed (legacy all-off defaults).
    public var schemaVersion: Int
    /// Master switch. When false, all deterministic processors are skipped
    /// and the pipeline returns the input unchanged.
    public var enabled: Bool
    /// Convert Chinese numerals to Arabic digits in quantity/date/time/percent
    /// contexts. Conservative: idioms and fixed phrases are preserved.
    public var smartNumberRecognition: Bool
    /// Punctuation optimization: sentence-ending punctuation completion,
    /// half-width → full-width CJK punctuation, consecutive punctuation
    /// normalization.
    public var punctuationOptimization: Bool
    /// Break long sentences into multiple lines at semantic boundaries.
    /// Only triggers above the configured word/CJK thresholds. Defaults to
    /// off because it is the most intrusive processor (introduces newlines).
    public var longSentenceBreaking: Bool
    /// Remove pure filler words ("嗯", "呃", "um", "uh") while preserving
    /// discourse markers with semantic value ("其实", "反正", "毕竟", "大概").
    public var fillerWordFiltering: Bool
    /// Insert a space between CJK and Latin/digit characters, while protecting
    /// URLs, paths, code identifiers, emails, version strings and backtick
    /// content.
    public var cjkLatinSpacing: Bool
    /// Capitalize the first letter of natural English sentences. Disabled in
    /// coding/identifier contexts to avoid breaking variable names/commands.
    public var autoCapitalization: Bool
    /// Maximum English words per line before long-sentence breaking triggers.
    public var longSentenceWordThreshold: Int
    /// Maximum CJK characters per line before long-sentence breaking triggers.
    public var longSentenceCJKThreshold: Int
    /// Minimum CJK characters in a segment before punctuation optimization
    /// treats it as a CJK context for half→full-width conversion.
    public var punctuationCJKThreshold: Int
    /// Minimum English words in a segment before punctuation optimization
    /// treats it as English context.
    public var punctuationWordThreshold: Int

    public init(
        enabled: Bool = true,
        smartNumberRecognition: Bool = true,
        punctuationOptimization: Bool = true,
        longSentenceBreaking: Bool = false,
        fillerWordFiltering: Bool = true,
        cjkLatinSpacing: Bool = true,
        autoCapitalization: Bool = true,
        longSentenceWordThreshold: Int = 8,
        longSentenceCJKThreshold: Int = 12,
        punctuationCJKThreshold: Int = 3,
        punctuationWordThreshold: Int = 4,
        schemaVersion: Int = Self.currentSchemaVersion
    ) {
        self.enabled = enabled
        self.smartNumberRecognition = smartNumberRecognition
        self.punctuationOptimization = punctuationOptimization
        self.longSentenceBreaking = longSentenceBreaking
        self.fillerWordFiltering = fillerWordFiltering
        self.cjkLatinSpacing = cjkLatinSpacing
        self.autoCapitalization = autoCapitalization
        self.longSentenceWordThreshold = longSentenceWordThreshold
        self.longSentenceCJKThreshold = longSentenceCJKThreshold
        self.punctuationCJKThreshold = punctuationCJKThreshold
        self.punctuationWordThreshold = punctuationWordThreshold
        self.schemaVersion = schemaVersion
    }

    /// Current schema version. Bump when the default values or shape changes
    /// in a way that requires migrating existing on-disk payloads.
    public static let currentSchemaVersion = 1

    /// Default settings. Master switch is on; all processors are enabled
    /// except `longSentenceBreaking` (the most intrusive one). Thresholds
    /// are tuned for typical CJK + English mixed dictation.
    public static let defaults = DeterministicTextProcessingSettings()
}

public extension DeterministicTextProcessingSettings {
    /// Returns a copy with only the processors enabled that are both turned on
    /// in the settings and permitted by the master switch. When the master
    /// switch is off, all sub-toggles are forced off (regardless of their
    /// stored values) so the pipeline is a guaranteed no-op.
    func effectiveSettings() -> DeterministicTextProcessingSettings {
        guard enabled else {
            return DeterministicTextProcessingSettings(
                enabled: false,
                smartNumberRecognition: false,
                punctuationOptimization: false,
                longSentenceBreaking: false,
                fillerWordFiltering: false,
                cjkLatinSpacing: false,
                autoCapitalization: false,
                longSentenceWordThreshold: longSentenceWordThreshold,
                longSentenceCJKThreshold: longSentenceCJKThreshold,
                punctuationCJKThreshold: punctuationCJKThreshold,
                punctuationWordThreshold: punctuationWordThreshold,
                schemaVersion: schemaVersion
            )
        }
        return self
    }
}
