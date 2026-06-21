import Foundation

struct BenchmarkMetrics: Codable {
    let totalCases: Int
    let passedCases: Int
    let sentenceExactMatchRate: Double
    let correctionPrecision: Double
    let supportedCorrectionRecall: Double
    let falseReplacementRate: Double
    let regressionRate: Double
    let cerBefore: Double
    let cerAfter: Double
    let werBefore: Double
    let werAfter: Double
    let p50LatencyMilliseconds: Double
    let p95LatencyMilliseconds: Double
    let p99LatencyMilliseconds: Double
}

enum MetricsCalculator {
    static func calculate(_ results: [BenchmarkCaseResult]) -> BenchmarkMetrics {
        let total = results.count
        let passed = results.filter(\.passed).count
        let expectedEvents = results.flatMap(\.expectedAppliedEvents)
        let actualEvents = results.flatMap(\.actualEvents)
        let truePositive = actualEvents.filter { actual in
            expectedEvents.contains {
                $0.ruleID == actual.ruleID &&
                    $0.from == actual.from &&
                    $0.to == actual.to
            }
        }.count
        let falsePositive = max(0, actualEvents.count - truePositive)
        let negativeCases = results.filter { $0.case.expected == $0.case.raw }
        let regressions = negativeCases.filter { $0.actual != $0.case.raw }.count
        let latencies = results.map(\.latencyMilliseconds).sorted()

        let cerBefore = aggregateDistance(results) { text in
            normalizeForCharacterErrorRate(text).unicodeScalars.map { String($0) }
        }
        let cerAfter = aggregateDistance(results, useActual: true) { text in
            normalizeForCharacterErrorRate(text).unicodeScalars.map { String($0) }
        }
        let werBefore = aggregateDistance(results) { $0.split(whereSeparator: \.isWhitespace).map(String.init) }
        let werAfter = aggregateDistance(results, useActual: true) { $0.split(whereSeparator: \.isWhitespace).map(String.init) }

        return BenchmarkMetrics(
            totalCases: total,
            passedCases: passed,
            sentenceExactMatchRate: ratio(passed, total),
            correctionPrecision: actualEvents.isEmpty ? 1 : ratio(truePositive, actualEvents.count),
            supportedCorrectionRecall: expectedEvents.isEmpty ? 1 : ratio(truePositive, expectedEvents.count),
            falseReplacementRate: ratio(falsePositive, max(1, total)),
            regressionRate: ratio(regressions, max(1, negativeCases.count)),
            cerBefore: cerBefore,
            cerAfter: cerAfter,
            werBefore: werBefore,
            werAfter: werAfter,
            p50LatencyMilliseconds: percentile(latencies, 0.50),
            p95LatencyMilliseconds: percentile(latencies, 0.95),
            p99LatencyMilliseconds: percentile(latencies, 0.99)
        )
    }

    private static func ratio(_ numerator: Int, _ denominator: Int) -> Double {
        denominator == 0 ? 1 : Double(numerator) / Double(denominator)
    }

    private static func aggregateDistance<T: Equatable>(
        _ results: [BenchmarkCaseResult],
        useActual: Bool = false,
        split: (String) -> [T]
    ) -> Double {
        var distance = 0
        var referenceCount = 0
        for result in results {
            let reference = split(result.case.expected)
            let hypothesis = split(useActual ? result.actual : result.case.raw)
            distance += editDistance(reference, hypothesis)
            referenceCount += reference.count
        }
        return referenceCount == 0 ? 0 : Double(distance) / Double(referenceCount)
    }

    private static func editDistance<T: Equatable>(_ lhs: [T], _ rhs: [T]) -> Int {
        var previous = Array(0 ... rhs.count)
        var current = Array(repeating: 0, count: rhs.count + 1)
        for (i, left) in lhs.enumerated() {
            current[0] = i + 1
            for (j, right) in rhs.enumerated() {
                if left == right {
                    current[j + 1] = previous[j]
                } else {
                    current[j + 1] = min(previous[j], previous[j + 1], current[j]) + 1
                }
            }
            swap(&previous, &current)
        }
        return previous[rhs.count]
    }

    private static func normalizeForCharacterErrorRate(_ text: String) -> String {
        text
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private static func percentile(_ values: [Double], _ percentile: Double) -> Double {
        guard !values.isEmpty else {
            return 0
        }
        let index = Int((Double(values.count - 1) * percentile).rounded())
        return values[max(0, min(values.count - 1, index))]
    }
}
