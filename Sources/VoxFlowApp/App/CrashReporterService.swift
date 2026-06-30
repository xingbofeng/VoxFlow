import Foundation
@preconcurrency import Sentry

struct CrashReporterConfiguration: Equatable {
    let dsn: String?
    let release: String
    let environment: String
    let bundleIdentifier: String
    let appVersion: String
    let buildNumber: String

    var hasConfiguredDSN: Bool {
        guard let dsn else { return false }
        return !dsn.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func live(bundle: Bundle = .main) -> CrashReporterConfiguration {
        let bundleIdentifier = bundle.bundleIdentifier ?? "com.voxflow.app"
        let appVersion = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        let buildNumber = bundle.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        let bundledDSN = bundle.infoDictionary?["VoxFlowSentryDSN"] as? String
        let environmentDSN = ProcessInfo.processInfo.environment["VOXFLOW_SENTRY_DSN"]
        #if DEBUG
        let environment = "development"
        #else
        let environment = "production"
        #endif

        return CrashReporterConfiguration(
            dsn: environmentDSN ?? bundledDSN,
            release: "\(bundleIdentifier)@\(appVersion)+\(buildNumber)",
            environment: environment,
            bundleIdentifier: bundleIdentifier,
            appVersion: appVersion,
            buildNumber: buildNumber
        )
    }
}

struct ManualCrashReportPayload: Equatable {
    let summary: SystemCrashReportSummary
    let sanitizedBody: String
}

enum CrashReportSendResult: Equatable {
    case sent
    case missingDSN
}

protocol CrashReportClient: AnyObject {
    func start(configuration: CrashReporterConfiguration)
    func captureManualReport(_ payload: ManualCrashReportPayload)
    func flush(timeout: TimeInterval)
    func stopAndClearPendingReports()
}

extension CrashReportClient {
    func captureManualReport(_ payload: ManualCrashReportPayload) {}
    func flush(timeout: TimeInterval) {}
}

final class CrashReporterService: @unchecked Sendable {
    static let shared = CrashReporterService(client: SentryCrashReportClient())
    private static let eventSendingLock = NSLock()
    nonisolated(unsafe) private static var eventSendingEnabled = false

    private let client: any CrashReportClient
    private(set) var isAutomaticReportingActive = false

    init(client: any CrashReportClient) {
        self.client = client
    }

    func configure(enabled: Bool, configuration: CrashReporterConfiguration) {
        guard enabled else {
            isAutomaticReportingActive = false
            Self.setEventSendingAllowed(false)
            client.stopAndClearPendingReports()
            return
        }

        guard configuration.hasConfiguredDSN else {
            isAutomaticReportingActive = false
            Self.setEventSendingAllowed(false)
            return
        }

        Self.setEventSendingAllowed(true)
        client.start(configuration: configuration)
        isAutomaticReportingActive = true
    }

    @discardableResult
    func sendManualCrashReport(
        _ payload: ManualCrashReportPayload,
        configuration: CrashReporterConfiguration
    ) -> CrashReportSendResult {
        guard configuration.hasConfiguredDSN else {
            return .missingDSN
        }

        let wasAutomaticReportingActive = isAutomaticReportingActive
        if !wasAutomaticReportingActive {
            Self.setEventSendingAllowed(true)
            client.start(configuration: configuration)
        }
        client.captureManualReport(payload)
        client.flush(timeout: 2)
        if !wasAutomaticReportingActive {
            Self.setEventSendingAllowed(false)
            client.stopAndClearPendingReports()
        }
        return .sent
    }

    fileprivate static func isEventSendingAllowed() -> Bool {
        eventSendingLock.lock()
        defer { eventSendingLock.unlock() }
        return eventSendingEnabled
    }

    private static func setEventSendingAllowed(_ allowed: Bool) {
        eventSendingLock.lock()
        eventSendingEnabled = allowed
        eventSendingLock.unlock()
    }
}

final class SentryCrashReportClient: CrashReportClient {
    func start(configuration: CrashReporterConfiguration) {
        SentrySDK.start { options in
            options.dsn = configuration.dsn
            options.releaseName = configuration.release
            options.environment = configuration.environment
            options.enableAutoSessionTracking = false
            options.enableAutoPerformanceTracing = false
            options.enableNetworkTracking = false
            options.enableFileIOTracing = false
            options.enableCoreDataTracing = false
            options.enableAppHangTracking = false
            options.enableAutoBreadcrumbTracking = false
            options.enableWatchdogTerminationTracking = false
            options.sendDefaultPii = false
            options.tracesSampleRate = 0
            options.beforeSend = { event in
                guard CrashReporterService.isEventSendingAllowed() else {
                    return nil
                }
                event.user = nil
                event.breadcrumbs = []
                return event
            }
        }
    }

    func captureManualReport(_ payload: ManualCrashReportPayload) {
        let event = Event(level: .info)
        event.message = SentryMessage(formatted: "Manual VoxFlow system crash report")
        event.logger = "voxflow.crash_report.manual"
        event.tags = [
            "source": "manual_system_crash_report",
            "process": payload.summary.processName,
            "exception_type": payload.summary.exceptionType,
        ]
        event.extra = [
            "identifier": payload.summary.identifier ?? "",
            "version": payload.summary.version ?? "",
            "date_time": payload.summary.dateTime ?? "",
            "crashed_thread_top_frames": payload.summary.crashedThreadTopFrames,
            "sanitized_report": payload.sanitizedBody,
        ]
        SentrySDK.capture(event: event)
    }

    func flush(timeout: TimeInterval) {
        SentrySDK.flush(timeout: timeout)
    }

    func stopAndClearPendingReports() {
        SentrySDK.close()
    }
}
