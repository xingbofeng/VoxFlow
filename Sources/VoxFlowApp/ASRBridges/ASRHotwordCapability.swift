import Foundation
import VoxFlowVoiceCorrection

/// Defines the hotword support mode, limits, and pruning strategy for each
/// ASR Provider, per the Provider 预研矩阵 in research-decisions.md.
///
/// This is the single source of truth for which providers get the `热词` tag
/// in the UI and how hotword payloads are constructed.
enum ASRHotwordSupportMode: String, Sendable, Equatable {
    /// Real hotword/boosting API (Apple contextualStrings, Nemotron WordBoostingConfig, Tencent hotword_list).
    case nativeHotword
    /// Prompt/context-style hotword injection (Groq Whisper, Qwen3 context).
    case promptContext
    /// External vocabulary ID (Aliyun DashScope vocabulary_id).
    case configuredVocabulary
    /// No user hotword API exposed; UI must not show `热词` tag. May still go through LLM context.
    case unsupported
}

/// Capability descriptor for a single ASR Provider's hotword support.
struct ASRHotwordCapability: Sendable, Equatable {
    let providerID: String
    let engineType: ASREngineType
    let supportMode: ASRHotwordSupportMode
    /// Maximum number of hotwords that can be delivered in a single request.
    let maxCount: Int
    /// Maximum character or token budget for the hotword payload (0 = no limit).
    let maxBudget: Int
    /// Whether the budget is measured in tokens (vs characters).
    let budgetUnit: BudgetUnit
    /// Whether additional configuration (e.g., vocabulary_id) is required.
    let requiresConfiguration: Bool
    /// The reason shown in trace/logs when hotwords are not delivered.
    var unsupportedReason: String?

    enum BudgetUnit: String, Sendable, Equatable {
        case characters
        case tokens
        case count
    }

    /// Whether this provider should show the `热词` tag in the UI.
    var showsHotwordTag: Bool {
        supportMode != .unsupported
    }

    /// Prunes hotword candidates to fit this provider's budget.
    /// Returns the delivered list and the pruned count.
    func prune(_ candidates: [String]) -> (delivered: [String], pruned: Int) {
        guard !candidates.isEmpty else {
            return ([], 0)
        }
        guard supportMode != .unsupported else {
            return ([], candidates.count)
        }
        if maxCount > 0 && candidates.count > maxCount {
            let delivered = Array(candidates.prefix(maxCount))
            return (delivered, candidates.count - maxCount)
        }
        if maxBudget > 0 {
            var selected: [String] = []
            var length = 0
            for term in candidates {
                let termLength = budgetUnit == .tokens
                    ? Self.estimateTokens(term)
                    : term.count
                let addedLength = termLength + (selected.isEmpty ? 0 : 2)
                guard length + addedLength <= maxBudget else { break }
                selected.append(term)
                length += addedLength
            }
            return (selected, candidates.count - selected.count)
        }
        return (candidates, 0)
    }

    /// Conservative token estimate for prompt-limited ASR APIs.
    /// CJK text is closer to one token per character, while Latin text is
    /// roughly four characters per token. This intentionally under-fills
    /// Groq's documented 224-token prompt budget.
    static func estimateTokens(_ text: String) -> Int {
        var cjkCount = 0
        var otherCount = 0
        for scalar in text.unicodeScalars {
            if Self.isCJK(scalar) {
                cjkCount += 1
            } else if !CharacterSet.whitespacesAndNewlines.contains(scalar) {
                otherCount += 1
            }
        }
        return max(1, cjkCount + Int(ceil(Double(otherCount) / 4.0)))
    }

    static func isCJK(_ scalar: UnicodeScalar) -> Bool {
        switch scalar.value {
        case 0x4E00...0x9FFF,
             0x3400...0x4DBF,
             0x20000...0x2A6DF,
             0x2A700...0x2B73F,
             0x2B740...0x2B81F,
             0x2B820...0x2CEAF,
             0xF900...0xFAFF:
            return true
        default:
            return false
        }
    }
}

/// The payload constructed for a specific ASR Provider's hotword delivery.
struct ASRHotwordPayload: Sendable, Equatable {
    let providerID: String
    let engineType: ASREngineType
    let supportMode: ASRHotwordSupportMode
    let candidates: [String]
    let delivered: [String]
    let prunedCount: Int
    let unsupportedReason: String?

    /// For prompt-based providers, the hotwords joined as a comma-separated prompt string.
    var promptString: String? {
        guard supportMode == .promptContext, !delivered.isEmpty else { return nil }
        return delivered.joined(separator: ", ")
    }

    /// For Apple Speech, the contextualStrings array.
    var contextualStrings: [String]? {
        guard supportMode == .nativeHotword, engineType == .apple else { return nil }
        return delivered
    }

    /// For Tencent Cloud, the hotword_list format: `词|权重`.
    var hotwordList: [String]? {
        guard supportMode == .nativeHotword, engineType == .tencentCloud else { return nil }
        return delivered.enumerated().map { index, term in
            "\(term)|\(ASRHotwordCapabilityMatrix.tencentWeight(forPriorityIndex: index))"
        }
    }

    /// For NVIDIA Nemotron, the phrases for WordBoostingConfig.
    var boostingPhrases: [String]? {
        guard supportMode == .nativeHotword, engineType == .nvidiaNemotron else { return nil }
        return delivered
    }

    /// For Qwen3 speech-swift, the context string.
    var contextString: String? {
        guard supportMode == .promptContext, engineType == .qwen3 else { return nil }
        return delivered.joined(separator: ", ")
    }

    /// Summary for trace/logging.
    var traceSummary: String {
        if supportMode == .unsupported {
            return "候选 \(candidates.count) · 未下发（\(unsupportedReason ?? "unsupported")）"
        }
        return "候选 \(candidates.count) · 下发 \(delivered.count) · 剪枝 \(prunedCount)"
    }
}

/// The central hotword capability matrix, mapping each ASREngineType to its
/// ASRHotwordCapability. This replaces the hardcoded `.whisper/.groqWhisper`
/// budgets in the old `ASRTermPromptProvider`.
enum ASRHotwordCapabilityMatrix {
    /// Tencent hotword weights are priority-sensitive. Earlier terms have
    /// higher weights, and lower-priority terms stay below the super-hotword
    /// level to avoid harming overall recognition accuracy.
    static let tencentMaximumWeight = 11
    static let tencentMinimumWeight = 5

    static func tencentWeight(forPriorityIndex index: Int) -> Int {
        max(tencentMinimumWeight, tencentMaximumWeight - index)
    }

    static let capabilities: [ASREngineType: ASRHotwordCapability] = [
        // Apple Speech: contextualStrings, no hard limit but keep reasonable
        .apple: ASRHotwordCapability(
            providerID: ASREngineType.apple.providerID,
            engineType: .apple,
            supportMode: .nativeHotword,
            maxCount: 50,
            maxBudget: 0,
            budgetUnit: .count,
            requiresConfiguration: false,
            unsupportedReason: nil
        ),
        // WhisperKit promptTokens currently produce empty finals in live smoke;
        // do not advertise or deliver ASR hotwords until that path is fixed.
        .whisper: ASRHotwordCapability(
            providerID: ASREngineType.whisper.providerID,
            engineType: .whisper,
            supportMode: .unsupported,
            maxCount: 0,
            maxBudget: 0,
            budgetUnit: .count,
            requiresConfiguration: false,
            unsupportedReason: "whisper_prompt_empty_final"
        ),
        // Groq Whisper: prompt-based, 224 token limit per official docs
        .groqWhisper: ASRHotwordCapability(
            providerID: ASREngineType.groqWhisper.providerID,
            engineType: .groqWhisper,
            supportMode: .promptContext,
            maxCount: 0,
            maxBudget: 224,
            budgetUnit: .tokens,
            requiresConfiguration: false,
            unsupportedReason: nil
        ),
        // Qwen3 speech-swift: context parameter
        .qwen3: ASRHotwordCapability(
            providerID: ASREngineType.qwen3.providerID,
            engineType: .qwen3,
            supportMode: .promptContext,
            maxCount: 0,
            maxBudget: 500,
            budgetUnit: .characters,
            requiresConfiguration: false,
            unsupportedReason: nil
        ),
        // NVIDIA Nemotron: WordBoostingConfig
        .nvidiaNemotron: ASRHotwordCapability(
            providerID: ASREngineType.nvidiaNemotron.providerID,
            engineType: .nvidiaNemotron,
            supportMode: .nativeHotword,
            maxCount: 100,
            maxBudget: 0,
            budgetUnit: .count,
            requiresConfiguration: false,
            unsupportedReason: nil
        ),
        // Tencent Cloud: hotword_list, max 128
        .tencentCloud: ASRHotwordCapability(
            providerID: ASREngineType.tencentCloud.providerID,
            engineType: .tencentCloud,
            supportMode: .nativeHotword,
            maxCount: 128,
            maxBudget: 0,
            budgetUnit: .count,
            requiresConfiguration: false,
            unsupportedReason: nil
        ),
        // Aliyun DashScope: vocabulary_id, no direct word list
        .aliyunDashScope: ASRHotwordCapability(
            providerID: ASREngineType.aliyunDashScope.providerID,
            engineType: .aliyunDashScope,
            supportMode: .configuredVocabulary,
            maxCount: 0,
            maxBudget: 0,
            budgetUnit: .count,
            requiresConfiguration: true,
            unsupportedReason: nil
        ),
        .volcengineDoubao: ASRHotwordCapability(
            providerID: ASREngineType.volcengineDoubao.providerID,
            engineType: .volcengineDoubao,
            supportMode: .unsupported,
            maxCount: 0,
            maxBudget: 0,
            budgetUnit: .count,
            requiresConfiguration: false,
            unsupportedReason: "provider_no_hotword_api"
        ),
        // Unsupported providers
        .parakeetStreaming: ASRHotwordCapability(
            providerID: ASREngineType.parakeetStreaming.providerID,
            engineType: .parakeetStreaming,
            supportMode: .unsupported,
            maxCount: 0,
            maxBudget: 0,
            budgetUnit: .count,
            requiresConfiguration: false,
            unsupportedReason: "provider_no_hotword_api"
        ),
        .omnilingualASR: ASRHotwordCapability(
            providerID: ASREngineType.omnilingualASR.providerID,
            engineType: .omnilingualASR,
            supportMode: .unsupported,
            maxCount: 0,
            maxBudget: 0,
            budgetUnit: .count,
            requiresConfiguration: false,
            unsupportedReason: "provider_no_hotword_api"
        ),
        .paraformer: ASRHotwordCapability(
            providerID: ASREngineType.paraformer.providerID,
            engineType: .paraformer,
            supportMode: .unsupported,
            maxCount: 0,
            maxBudget: 0,
            budgetUnit: .count,
            requiresConfiguration: false,
            unsupportedReason: "provider_no_hotword_api"
        ),
        .funASR: ASRHotwordCapability(
            providerID: ASREngineType.funASR.providerID,
            engineType: .funASR,
            supportMode: .unsupported,
            maxCount: 0,
            maxBudget: 0,
            budgetUnit: .count,
            requiresConfiguration: false,
            unsupportedReason: "provider_no_hotword_api"
        ),
        .senseVoice: ASRHotwordCapability(
            providerID: ASREngineType.senseVoice.providerID,
            engineType: .senseVoice,
            supportMode: .unsupported,
            maxCount: 0,
            maxBudget: 0,
            budgetUnit: .count,
            requiresConfiguration: false,
            unsupportedReason: "provider_no_hotword_api"
        ),
    ]

    /// Returns the capability for a given engine type, or a default unsupported.
    static func capability(for engineType: ASREngineType) -> ASRHotwordCapability {
        capabilities[engineType] ?? ASRHotwordCapability(
            providerID: engineType.providerID,
            engineType: engineType,
            supportMode: .unsupported,
            maxCount: 0,
            maxBudget: 0,
            budgetUnit: .count,
            requiresConfiguration: false,
            unsupportedReason: "unknown_provider"
        )
    }

    /// Builds a hotword payload for a given engine type from candidate hotwords.
    static func buildPayload(
        for engineType: ASREngineType,
        candidates: [String],
        hasVocabularyID: Bool = false
    ) -> ASRHotwordPayload {
        let cap = capability(for: engineType)

        if cap.supportMode == .unsupported {
            return ASRHotwordPayload(
                providerID: cap.providerID,
                engineType: engineType,
                supportMode: .unsupported,
                candidates: candidates,
                delivered: [],
                prunedCount: candidates.count,
                unsupportedReason: cap.unsupportedReason
            )
        }

        if cap.supportMode == .configuredVocabulary {
            let reason = hasVocabularyID ? nil : "missing_vocabulary_id"
            return ASRHotwordPayload(
                providerID: cap.providerID,
                engineType: engineType,
                supportMode: .configuredVocabulary,
                candidates: candidates,
                delivered: hasVocabularyID ? candidates : [],
                prunedCount: hasVocabularyID ? 0 : candidates.count,
                unsupportedReason: reason
            )
        }

        let filteredCandidates: [String]
        let invalidCount: Int
        if engineType == .tencentCloud {
            filteredCandidates = candidates.filter(isValidTencentHotword)
            invalidCount = candidates.count - filteredCandidates.count
        } else {
            filteredCandidates = candidates
            invalidCount = 0
        }
        let (delivered, pruned) = cap.prune(filteredCandidates)
        return ASRHotwordPayload(
            providerID: cap.providerID,
            engineType: engineType,
            supportMode: cap.supportMode,
            candidates: candidates,
            delivered: delivered,
            prunedCount: pruned + invalidCount,
            unsupportedReason: nil
        )
    }

    static func isValidTencentHotword(_ term: String) -> Bool {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 30 else { return false }
        let cjkCount = trimmed.unicodeScalars.filter(ASRHotwordCapability.isCJK).count
        return cjkCount <= 10
    }
}
