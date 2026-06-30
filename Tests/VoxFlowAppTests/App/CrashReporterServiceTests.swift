import XCTest
@testable import VoxFlowApp

final class CrashReporterServiceTests: XCTestCase {
    func testDisabledOrMissingDSNDoesNotActivateAutomaticReporting() {
        let client = CapturingCrashReportClient()
        let service = CrashReporterService(client: client)

        service.configure(
            enabled: true,
            configuration: CrashReporterConfiguration(
                dsn: nil,
                release: "com.voxflow.app@1.0+1",
                environment: "development",
                bundleIdentifier: "com.voxflow.app",
                appVersion: "1.0",
                buildNumber: "1"
            )
        )

        XCTAssertFalse(service.isAutomaticReportingActive)
        XCTAssertEqual(client.configurations.count, 0)

        service.configure(
            enabled: false,
            configuration: CrashReporterConfiguration(
                dsn: "https://example@sentry.io/1",
                release: "com.voxflow.app@1.0+1",
                environment: "development",
                bundleIdentifier: "com.voxflow.app",
                appVersion: "1.0",
                buildNumber: "1"
            )
        )

        XCTAssertFalse(service.isAutomaticReportingActive)
        XCTAssertEqual(client.configurations.count, 0)
        XCTAssertEqual(client.stopCount, 1)
        XCTAssertTrue(client.didClearPendingReports)
    }

    func testEnabledWithDSNActivatesAutomaticReporting() {
        let client = CapturingCrashReportClient()
        let service = CrashReporterService(client: client)
        let configuration = CrashReporterConfiguration(
            dsn: "https://example@sentry.io/1",
            release: "com.voxflow.app@1.0+1",
            environment: "development",
            bundleIdentifier: "com.voxflow.app",
            appVersion: "1.0",
            buildNumber: "1"
        )

        service.configure(enabled: true, configuration: configuration)

        XCTAssertTrue(service.isAutomaticReportingActive)
        XCTAssertEqual(client.configurations, [configuration])
    }

    func testManualReportRequiresDSNAndSendsWithTemporaryClient() {
        let client = CapturingCrashReportClient()
        let service = CrashReporterService(client: client)
        let payload = ManualCrashReportPayload(
            summary: SystemCrashReportSummary(
                processName: "VoxFlow",
                exceptionType: "EXC_BAD_ACCESS (SIGSEGV)",
                crashedThreadTopFrames: ["0 VoxFlow SmartConfigurationView.progressView"]
            ),
            sanitizedBody: "Thread 0 Crashed"
        )

        let missingDSNResult = service.sendManualCrashReport(
            payload,
            configuration: CrashReporterConfiguration(
                dsn: nil,
                release: "com.voxflow.app@1.0+1",
                environment: "development",
                bundleIdentifier: "com.voxflow.app",
                appVersion: "1.0",
                buildNumber: "1"
            )
        )

        XCTAssertEqual(missingDSNResult, .missingDSN)
        XCTAssertTrue(client.manualReports.isEmpty)

        let sentResult = service.sendManualCrashReport(
            payload,
            configuration: CrashReporterConfiguration(
                dsn: "https://example@sentry.io/1",
                release: "com.voxflow.app@1.0+1",
                environment: "development",
                bundleIdentifier: "com.voxflow.app",
                appVersion: "1.0",
                buildNumber: "1"
            )
        )

        XCTAssertEqual(sentResult, .sent)
        XCTAssertEqual(client.configurations.count, 1)
        XCTAssertEqual(client.manualReports, [payload])
        XCTAssertEqual(client.flushTimeouts, [2])
        XCTAssertEqual(client.stopCount, 1)
    }
}

private final class CapturingCrashReportClient: CrashReportClient {
    private(set) var configurations: [CrashReporterConfiguration] = []
    private(set) var manualReports: [ManualCrashReportPayload] = []
    private(set) var flushTimeouts: [TimeInterval] = []
    private(set) var stopCount = 0
    private(set) var didClearPendingReports = false

    func start(configuration: CrashReporterConfiguration) {
        configurations.append(configuration)
    }

    func captureManualReport(_ payload: ManualCrashReportPayload) {
        manualReports.append(payload)
    }

    func flush(timeout: TimeInterval) {
        flushTimeouts.append(timeout)
    }

    func stopAndClearPendingReports() {
        stopCount += 1
        didClearPendingReports = true
    }
}
