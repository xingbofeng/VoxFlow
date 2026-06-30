import Foundation

struct SystemCrashReport: Equatable {
    let url: URL
    let summary: SystemCrashReportSummary
}

struct SystemCrashReportSummary: Equatable {
    let processName: String
    let identifier: String?
    let version: String?
    let dateTime: String?
    let exceptionType: String
    let crashedThreadTopFrames: [String]

    init(
        processName: String,
        identifier: String? = nil,
        version: String? = nil,
        dateTime: String? = nil,
        exceptionType: String,
        crashedThreadTopFrames: [String]
    ) {
        self.processName = processName
        self.identifier = identifier
        self.version = version
        self.dateTime = dateTime
        self.exceptionType = exceptionType
        self.crashedThreadTopFrames = crashedThreadTopFrames
    }
}

struct SystemCrashReportScanner {
    private let directory: URL
    private let fileManager: FileManager

    init(
        directory: URL = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Logs/DiagnosticReports", isDirectory: true),
        fileManager: FileManager = .default
    ) {
        self.directory = directory
        self.fileManager = fileManager
    }

    func latestReport() -> SystemCrashReport? {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        let candidates = urls
            .filter { url in
                let name = url.lastPathComponent
                return name.hasPrefix("VoxFlow-") && name.hasSuffix(".ips")
            }
            .sorted { lhs, rhs in
                modificationDate(for: lhs) > modificationDate(for: rhs)
            }

        guard let latest = candidates.first,
              let raw = try? String(contentsOf: latest, encoding: .utf8) else {
            return nil
        }

        let reportURL = directory.appendingPathComponent(latest.lastPathComponent)
        return SystemCrashReport(url: reportURL, summary: Self.summary(from: raw))
    }

    private func modificationDate(for url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

    private static func summary(from raw: String) -> SystemCrashReportSummary {
        if let summary = modernIPSSummary(from: raw) {
            return summary
        }

        let lines = raw.components(separatedBy: .newlines)
        let processName = value(after: "Process:", in: lines)
            .map { value in value.components(separatedBy: "[").first?.trimmingCharacters(in: .whitespaces) ?? value }
            ?? "VoxFlow"
        let exceptionType = value(after: "Exception Type:", in: lines) ?? L10n.localize(
            "settings.crash_report.summary.unknown_exception",
            comment: ""
        )
        let frames = crashedThreadFrames(in: lines)

        return SystemCrashReportSummary(
            processName: processName,
            identifier: value(after: "Identifier:", in: lines),
            version: value(after: "Version:", in: lines),
            dateTime: value(after: "Date/Time:", in: lines),
            exceptionType: exceptionType,
            crashedThreadTopFrames: frames
        )
    }

    private static func modernIPSSummary(from raw: String) -> SystemCrashReportSummary? {
        let lines = raw.components(separatedBy: .newlines)
        guard let firstLine = lines.first?.trimmingCharacters(in: .whitespacesAndNewlines),
              firstLine.hasPrefix("{"),
              let metadataData = firstLine.data(using: .utf8),
              let metadata = try? JSONDecoder().decode(IPSMetadata.self, from: metadataData) else {
            return nil
        }

        let body = lines.dropFirst().joined(separator: "\n")
        let bodyReport = body.data(using: .utf8)
            .flatMap { try? JSONDecoder().decode(IPSReportBody.self, from: $0) }
        let bundleInfo = bodyReport?.bundleInfo
        let appVersion = bundleInfo?.shortVersion ?? metadata.appVersion
        let buildVersion = bundleInfo?.buildVersion ?? metadata.buildVersion
        let version = [appVersion, buildVersion.map { "(\($0))" }]
            .compactMap { $0 }
            .joined(separator: " ")
        let exceptionType = [
            bodyReport?.exception?.type,
            bodyReport?.exception?.signal.map { "(\($0))" },
        ]
            .compactMap { $0 }
            .joined(separator: " ")

        return SystemCrashReportSummary(
            processName: bodyReport?.processName ?? metadata.processName ?? metadata.appName ?? "VoxFlow",
            identifier: bundleInfo?.identifier ?? metadata.bundleID,
            version: version.isEmpty ? nil : version,
            dateTime: bodyReport?.captureTime ?? metadata.timestamp,
            exceptionType: exceptionType.isEmpty ? L10n.localize(
                "settings.crash_report.summary.unknown_exception",
                comment: ""
            ) : exceptionType,
            crashedThreadTopFrames: bodyReport?.triggeredThreadFrames ?? []
        )
    }

    private static func value(after prefix: String, in lines: [String]) -> String? {
        lines.first { $0.trimmingCharacters(in: .whitespaces).hasPrefix(prefix) }
            .map { line in
                String(line.dropFirst(prefix.count))
                    .trimmingCharacters(in: .whitespaces)
            }
            .flatMap { $0.isEmpty ? nil : $0 }
    }

    private static func crashedThreadFrames(in lines: [String]) -> [String] {
        guard let headerIndex = lines.firstIndex(where: {
            $0.trimmingCharacters(in: .whitespaces).hasPrefix("Thread 0 Crashed:")
        }) else {
            return []
        }

        var frames: [String] = []
        for line in lines[(headerIndex + 1)...] {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { break }
            frames.append(trimmed)
            if frames.count == 8 { break }
        }
        return frames
    }
}

private struct IPSMetadata: Decodable {
    let appName: String?
    let timestamp: String?
    let appVersion: String?
    let buildVersion: String?
    let bundleID: String?
    let processName: String?

    enum CodingKeys: String, CodingKey {
        case appName = "app_name"
        case timestamp
        case appVersion = "app_version"
        case buildVersion = "build_version"
        case bundleID
        case processName = "name"
    }
}

private struct IPSReportBody: Decodable {
    let captureTime: String?
    let processName: String?
    let bundleInfo: IPSBundleInfo?
    let exception: IPSException?
    let threads: [IPSThread]

    var triggeredThreadFrames: [String] {
        guard let frames = threads.first(where: { $0.triggered == true })?.frames else {
            return []
        }
        return frames.prefix(8).enumerated().compactMap { index, frame in
            guard let symbol = frame.symbol, !symbol.isEmpty else { return nil }
            return "\(index) \(symbol)"
        }
    }

    enum CodingKeys: String, CodingKey {
        case captureTime
        case processName = "procName"
        case bundleInfo
        case exception
        case threads
    }
}

private struct IPSBundleInfo: Decodable {
    let shortVersion: String?
    let buildVersion: String?
    let identifier: String?

    enum CodingKeys: String, CodingKey {
        case shortVersion = "CFBundleShortVersionString"
        case buildVersion = "CFBundleVersion"
        case identifier = "CFBundleIdentifier"
    }
}

private struct IPSException: Decodable {
    let type: String?
    let signal: String?
}

private struct IPSThread: Decodable {
    let triggered: Bool?
    let frames: [IPSFrame]
}

private struct IPSFrame: Decodable {
    let symbol: String?
}

struct SystemCrashReportSanitizer {
    let homeDirectory: URL

    func sanitize(_ raw: String) -> String {
        raw.components(separatedBy: .newlines)
            .filter { !containsSensitiveMarker($0) }
            .joined(separator: "\n")
            .replacingOccurrences(of: homeDirectory.path, with: "~")
    }

    private func containsSensitiveMarker(_ line: String) -> Bool {
        let lowercased = line.trimmingCharacters(in: .whitespaces).lowercased()
        return lowercased.hasPrefix("prompt:")
            || lowercased.hasPrefix("clipboard:")
            || lowercased.hasPrefix("transcription:")
            || lowercased.hasPrefix("transcript:")
    }
}
