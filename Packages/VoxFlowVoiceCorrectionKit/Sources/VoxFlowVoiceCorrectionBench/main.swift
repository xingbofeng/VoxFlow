import Foundation

struct Arguments {
    let fixtures: URL
    let baseline: URL
    let output: URL
}

func parseArguments() throws -> Arguments {
    var values: [String: String] = [:]
    var iterator = CommandLine.arguments.dropFirst().makeIterator()
    while let key = iterator.next() {
        guard key.hasPrefix("--"), let value = iterator.next() else {
            continue
        }
        values[String(key.dropFirst(2))] = value
    }
    guard let fixtures = values["fixtures"],
          let baseline = values["baseline"],
          let output = values["output"]
    else {
        throw BenchmarkError.invalidArguments
    }
    return Arguments(
        fixtures: URL(fileURLWithPath: fixtures),
        baseline: URL(fileURLWithPath: baseline),
        output: URL(fileURLWithPath: output)
    )
}

enum BenchmarkError: Error {
    case invalidArguments
    case failedThresholds
}

do {
    let arguments = try parseArguments()
    let baselineData = try Data(contentsOf: arguments.baseline)
    let baseline = try JSONDecoder().decode(BenchmarkBaseline.self, from: baselineData)
    let report = try BenchmarkRunner(fixturesDirectory: arguments.fixtures).run()
    try ReportWriter.write(report: report, to: arguments.output)

    let metrics = report.summary
    guard metrics.totalCases >= baseline.minimumCases,
          report.failedCases.isEmpty,
          report.failedLearningCases.isEmpty,
          metrics.correctionPrecision >= baseline.correctionPrecision,
          metrics.supportedCorrectionRecall >= baseline.supportedCorrectionRecall,
          metrics.falseReplacementRate <= baseline.falseReplacementRate,
          metrics.regressionRate <= baseline.regressionRate,
          metrics.cerAfter <= metrics.cerBefore,
          metrics.werAfter <= metrics.werBefore
    else {
        throw BenchmarkError.failedThresholds
    }
    print("VoiceCorrection benchmark passed: \(metrics.passedCases)/\(metrics.totalCases), learning \(report.learningResults.count - report.failedLearningCases.count)/\(report.learningResults.count)")
} catch {
    fputs("VoiceCorrection benchmark failed: \(error)\n", stderr)
    exit(1)
}
