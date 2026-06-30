import XCTest
@testable import VoxFlowApp

final class SystemCrashReportScannerTests: XCTestCase {
    func testFindsLatestVoxFlowCrashReportAndBuildsSummary() throws {
        let directory = try makeTemporaryDirectory()
        let older = directory.appendingPathComponent("VoxFlow-2026-06-30-100000.ips")
        let latest = directory.appendingPathComponent("VoxFlow-2026-06-30-122341.ips")
        try sampleReport(process: "VoxFlow", date: "2026-06-30 10:00:00.0000 +0800")
            .write(to: older, atomically: true, encoding: .utf8)
        try sampleReport(process: "VoxFlow", date: "2026-06-30 12:23:41.0000 +0800")
            .write(to: latest, atomically: true, encoding: .utf8)

        let report = try XCTUnwrap(SystemCrashReportScanner(directory: directory).latestReport())

        XCTAssertEqual(report.url, latest)
        XCTAssertEqual(report.summary.processName, "VoxFlow")
        XCTAssertEqual(report.summary.identifier, "com.voxflow.app.dev")
        XCTAssertEqual(report.summary.version, "1.10.1 (19)")
        XCTAssertEqual(report.summary.dateTime, "2026-06-30 12:23:41.0000 +0800")
        XCTAssertEqual(report.summary.exceptionType, "EXC_BAD_ACCESS (SIGSEGV)")
        XCTAssertTrue(report.summary.crashedThreadTopFrames.first?.contains("SmartConfigurationView.progressView") == true)
    }

    func testBuildsSummaryFromModernMacOSIPSJSONReport() throws {
        let directory = try makeTemporaryDirectory()
        let latest = directory.appendingPathComponent("VoxFlow-2026-06-30-122341.ips")
        try modernIPSReport().write(to: latest, atomically: true, encoding: .utf8)

        let report = try XCTUnwrap(SystemCrashReportScanner(directory: directory).latestReport())

        XCTAssertEqual(report.summary.processName, "VoxFlow")
        XCTAssertEqual(report.summary.identifier, "com.voxflow.app.dev")
        XCTAssertEqual(report.summary.version, "1.10.1 (19)")
        XCTAssertEqual(report.summary.dateTime, "2026-06-30 12:23:33.7360 +0800")
        XCTAssertEqual(report.summary.exceptionType, "EXC_BAD_ACCESS (SIGSEGV)")
        XCTAssertEqual(report.summary.crashedThreadTopFrames.first, "0 objc_opt_respondsToSelector")
    }

    func testSanitizesHomePathAndSensitiveMarkers() throws {
        let raw = """
        Path: /Users/counter/Applications/VoxFlow.app
        Prompt: secret prompt
        Clipboard: secret clipboard
        Transcription: secret transcript
        Thread 0 Crashed:
        0 VoxFlow SmartConfigurationView.progressView
        """

        let sanitized = SystemCrashReportSanitizer(homeDirectory: URL(fileURLWithPath: "/Users/counter"))
            .sanitize(raw)

        XCTAssertFalse(sanitized.contains("/Users/counter"))
        XCTAssertFalse(sanitized.contains("secret prompt"))
        XCTAssertFalse(sanitized.contains("secret clipboard"))
        XCTAssertFalse(sanitized.contains("secret transcript"))
        XCTAssertTrue(sanitized.contains("~/Applications/VoxFlow.app"))
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SystemCrashReportScannerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }

    private func sampleReport(process: String, date: String) -> String {
        """
        Process:             \(process) [76368]
        Identifier:          com.voxflow.app.dev
        Version:             1.10.1 (19)
        Date/Time:           \(date)
        Exception Type:      EXC_BAD_ACCESS (SIGSEGV)
        Thread 0 Crashed:
        0   VoxFlow          SmartConfigurationView.progressView(title:progress:)
        1   SwiftUICore      closure #1 in VStack.init(alignment:spacing:content:)
        """
    }

    private func modernIPSReport() -> String {
        """
        {"app_name":"VoxFlow","timestamp":"2026-06-30 12:23:41.00 +0800","app_version":"1.10.1","build_version":"19","bundleID":"com.voxflow.app.dev","name":"VoxFlow"}
        {
          "captureTime" : "2026-06-30 12:23:33.7360 +0800",
          "procName" : "VoxFlow",
          "bundleInfo" : {"CFBundleShortVersionString":"1.10.1","CFBundleVersion":"19","CFBundleIdentifier":"com.voxflow.app.dev"},
          "exception" : {"type":"EXC_BAD_ACCESS","signal":"SIGSEGV"},
          "threads" : [
            {
              "triggered": true,
              "frames": [
                {"symbol":"objc_opt_respondsToSelector","imageIndex":5},
                {"symbol":"String.init(format:_:)","imageIndex":6},
                {"symbol":"SmartConfigurationView.progressView(title:progress:)","imageIndex":0}
              ]
            }
          ]
        }
        """
    }
}
