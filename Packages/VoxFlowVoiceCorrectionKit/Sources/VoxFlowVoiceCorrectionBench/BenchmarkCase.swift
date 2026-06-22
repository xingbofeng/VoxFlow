import Foundation
import VoxFlowVoiceCorrection

struct BenchmarkContext: Codable {
    let mode: CorrectionInputMode
    let providerID: String
    let modelID: String?
    let language: String?
    let bundleIdentifier: String?
    let isFinalTranscript: Bool?
    let isSecureField: Bool?

    func correctionContext() -> CorrectionContext {
        CorrectionContext(
            mode: mode,
            providerID: providerID,
            modelID: modelID,
            language: language,
            bundleIdentifier: bundleIdentifier,
            isFinalTranscript: isFinalTranscript ?? true,
            isSecureField: isSecureField ?? false
        )
    }
}

struct ExpectedBenchmarkEvent: Codable, Equatable {
    let ruleID: String
    let from: String
    let to: String
    let shouldApply: Bool
}

struct CorrectionBenchmarkCase: Codable {
    let id: String
    let raw: String
    let expected: String
    let context: BenchmarkContext
    let expectedEvents: [ExpectedBenchmarkEvent]
    let tags: [String]
}

struct ExpectedLearningCandidate: Codable, Equatable, Hashable {
    let original: String
    let replacement: String
}

struct LearningBenchmarkCase: Codable {
    let id: String
    let rawText: String
    let insertedText: String
    let observedFinalText: String
    let expectedCandidates: [ExpectedLearningCandidate]
    let expectedRevertedRuleIDs: [String]
    let shouldLearn: Bool
    let tags: [String]
}

struct BenchmarkRule: Codable {
    let id: String
    let original: String
    let replacement: String
    let matchPolicy: MatchPolicy
    let scope: RuleScopeDTO?
    let caseSensitive: Bool?
}

enum RuleScopeDTO: Codable {
    case global
    case application(String)

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "global":
            self = .global
        case "application":
            self = .application(try container.decode(String.self, forKey: .bundleIdentifier))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown scope type \(type)."
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .global:
            try container.encode("global", forKey: .type)
        case .application(let bundleIdentifier):
            try container.encode("application", forKey: .type)
            try container.encode(bundleIdentifier, forKey: .bundleIdentifier)
        }
    }

    var ruleScope: RuleScope {
        switch self {
        case .global:
            return .global
        case .application(let bundleIdentifier):
            return .application(bundleIdentifier: bundleIdentifier)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case bundleIdentifier
    }
}

struct BenchmarkBaseline: Codable {
    let minimumCases: Int
    let correctionPrecision: Double
    let supportedCorrectionRecall: Double
    let falseReplacementRate: Double
    let regressionRate: Double
}
