import Foundation
import VoxFlowVoiceCorrection

struct ActualBenchmarkEvent: Codable {
    let ruleID: String
    let from: String
    let to: String
}

struct BenchmarkCaseResult: Codable {
    let id: String
    let `case`: CorrectionBenchmarkCase
    let actual: String
    let actualEvents: [ActualBenchmarkEvent]
    let expectedAppliedEvents: [ExpectedBenchmarkEvent]
    let passed: Bool
    let failureReason: String?
    let nextStep: String?
    let latencyMilliseconds: Double
}

struct BenchmarkReport: Codable {
    let summary: BenchmarkMetrics
    let failedCases: [BenchmarkCaseResult]
    let notIncludedCases: [String]
    let results: [BenchmarkCaseResult]
}

struct BenchmarkRunner {
    let fixturesDirectory: URL

    func run() throws -> BenchmarkReport {
        let rules = try loadRules()
        let cases = try loadCases()
        let snapshot = RuleSnapshot(version: 1, rules: rules)
        let engine = VoiceCorrectionEngine()
        let results = cases.map { benchmarkCase in
            let start = DispatchTime.now().uptimeNanoseconds
            let result = engine.correct(
                rawText: benchmarkCase.raw,
                context: benchmarkCase.context.correctionContext(),
                snapshot: snapshot
            )
            let end = DispatchTime.now().uptimeNanoseconds
            let actualEvents = result.events.map {
                ActualBenchmarkEvent(
                    ruleID: $0.ruleID.uuidString,
                    from: $0.original,
                    to: $0.replacement
                )
            }
            let expectedApplied = benchmarkCase.expectedEvents.filter(\.shouldApply)
            let passed = result.correctedText == benchmarkCase.expected &&
                Set(actualEvents.map(eventKey)) == Set(expectedApplied.map(eventKey))
            return BenchmarkCaseResult(
                id: benchmarkCase.id,
                case: benchmarkCase,
                actual: result.correctedText,
                actualEvents: actualEvents,
                expectedAppliedEvents: expectedApplied,
                passed: passed,
                failureReason: passed ? nil : failureReason(
                    expectedText: benchmarkCase.expected,
                    actualText: result.correctedText,
                    expectedEvents: expectedApplied,
                    actualEvents: actualEvents
                ),
                nextStep: passed ? nil : "Classify as matcher, gate, conflict resolution, or fixture expectation drift before changing thresholds.",
                latencyMilliseconds: Double(end - start) / 1_000_000
            )
        }
        return BenchmarkReport(
            summary: MetricsCalculator.calculate(results),
            failedCases: results.filter { !$0.passed },
            notIncludedCases: [
                "500 correction + 100 learning extended benchmark: not included in the Phase 1 first gate; next step is expanding fixtures after the 100-case correction gate is stable.",
                "Real Accessibility permission observation benchmark: not included because CI uses fake observer/fake clock; next step is manual smoke coverage outside CI.",
                "Provider bias and OCR/TTL context benchmark: not included because Phase 1 correction engine intentionally does not consume OCR or provider bias."
            ],
            results: results
        )
    }

    private func loadRules() throws -> [CorrectionRule] {
        let data = try Data(contentsOf: fixturesDirectory.appendingPathComponent("rules_v1.json"))
        let dtos = try JSONDecoder().decode([BenchmarkRule].self, from: data)
        return dtos.map {
            CorrectionRule(
                id: UUID(uuidString: $0.id)!,
                original: $0.original,
                replacement: $0.replacement,
                matchPolicy: $0.matchPolicy,
                scope: $0.scope?.ruleScope ?? .global,
                lifecycle: .active,
                source: .manual,
                caseSensitive: $0.caseSensitive ?? false,
                confidence: 1
            )
        }
    }

    private func loadCases() throws -> [CorrectionBenchmarkCase] {
        let url = fixturesDirectory.appendingPathComponent("correction_cases_v1.jsonl")
        let content = try String(contentsOf: url, encoding: .utf8)
        let decoder = JSONDecoder()
        return try content.split(separator: "\n").map {
            try decoder.decode(CorrectionBenchmarkCase.self, from: Data($0.utf8))
        }
    }

    private func eventKey(_ event: ActualBenchmarkEvent) -> String {
        "\(event.ruleID)|\(event.from)|\(event.to)"
    }

    private func eventKey(_ event: ExpectedBenchmarkEvent) -> String {
        "\(event.ruleID)|\(event.from)|\(event.to)"
    }

    private func failureReason(
        expectedText: String,
        actualText: String,
        expectedEvents: [ExpectedBenchmarkEvent],
        actualEvents: [ActualBenchmarkEvent]
    ) -> String {
        var reasons: [String] = []
        if expectedText != actualText {
            reasons.append("text mismatch")
        }
        if Set(actualEvents.map(eventKey)) != Set(expectedEvents.map(eventKey)) {
            reasons.append("event mismatch")
        }
        return reasons.isEmpty ? "unknown mismatch" : reasons.joined(separator: ", ")
    }
}
