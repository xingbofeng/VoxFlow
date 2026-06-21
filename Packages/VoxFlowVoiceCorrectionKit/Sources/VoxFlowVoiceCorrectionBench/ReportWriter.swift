import Foundation

enum ReportWriter {
    static func write(
        report: BenchmarkReport,
        to outputDirectory: URL
    ) throws {
        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(report).write(to: outputDirectory.appendingPathComponent("report.json"))
        try markdown(report).write(
            to: outputDirectory.appendingPathComponent("report.md"),
            atomically: true,
            encoding: .utf8
        )
    }

    private static func markdown(_ report: BenchmarkReport) -> String {
        var lines: [String] = [
            "# Voice Correction Benchmark",
            "",
            "- Total cases: \(report.summary.totalCases)",
            "- Passed cases: \(report.summary.passedCases)",
            "- Sentence exact match: \(report.summary.sentenceExactMatchRate)",
            "- Correction precision: \(report.summary.correctionPrecision)",
            "- Supported correction recall: \(report.summary.supportedCorrectionRecall)",
            "- False replacement rate: \(report.summary.falseReplacementRate)",
            "- Regression rate: \(report.summary.regressionRate)",
            "- CER before/after: \(report.summary.cerBefore) / \(report.summary.cerAfter)",
            "- WER before/after: \(report.summary.werBefore) / \(report.summary.werAfter)",
            "- Latency P50/P95/P99 ms: \(report.summary.p50LatencyMilliseconds) / \(report.summary.p95LatencyMilliseconds) / \(report.summary.p99LatencyMilliseconds)",
            "",
            "## Failed Cases",
            "",
        ]

        if report.failedCases.isEmpty {
            lines.append("None.")
        } else {
            for failure in report.failedCases {
                lines.append("- \(failure.id): raw=`\(failure.case.raw)`, expected=`\(failure.case.expected)`, actual=`\(failure.actual)`, reason=`\(failure.failureReason ?? "unknown")`, next=`\(failure.nextStep ?? "triage")`")
            }
        }

        lines += [
            "",
            "## Not Included Cases",
            "",
            report.notIncludedCases.isEmpty ? "None." : report.notIncludedCases.map { "- \($0)" }.joined(separator: "\n"),
        ]
        return lines.joined(separator: "\n") + "\n"
    }
}
