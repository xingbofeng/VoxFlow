// Adapted from DictusCore (commit 7264b1d8). MIT License — Copyright (c) 2026 PIVI Solutions.
// App Group identifier is provided by AppGroup.identifier.

import Foundation

public struct DiagnosticResult {
    public let canWrite: Bool
    public let canRead: Bool
    public let appGroupID: String
    public let containerExists: Bool
    public let canWriteFile: Bool
    public let canReadFile: Bool
    public let fileName: String
    public let fileValue: String?
    public let timestamp: Date

    public var isHealthy: Bool {
        canWrite && canRead && containerExists && canWriteFile && canReadFile
    }
}

public enum AppGroupDiagnostic {
    public static let probeDefaultsKey = "mashangxie.appGroupProbe.defaults"
    public static let probeFileName = "mashangxie-app-group-probe.txt"

    public static func run() -> DiagnosticResult {
        run(defaults: AppGroup.defaults, containerURL: AppGroup.containerURL, now: Date())
    }

    /// Soft variant: returns an "unavailable" result instead of crashing when
    /// App Group is not configurable. Used by the Keyboard Extension startup
    /// path so free-signed builds don't crash on diagnostic probes.
    public static func runSafe() -> DiagnosticResult {
        guard let defaults = AppGroup.defaultsIfAvailable else {
            return DiagnosticResult(
                canWrite: false,
                canRead: false,
                appGroupID: AppGroup.identifier,
                containerExists: false,
                canWriteFile: false,
                canReadFile: false,
                fileName: probeFileName,
                fileValue: nil,
                timestamp: Date()
            )
        }
        return run(defaults: defaults, containerURL: AppGroup.containerURL, now: Date())
    }

    public static func run(defaults: UserDefaults, containerURL: URL?, now: Date) -> DiagnosticResult {
        let testValue = "ok-\(now.timeIntervalSince1970)"

        defaults.set(testValue, forKey: probeDefaultsKey)
        defaults.synchronize()

        let readBack = defaults.string(forKey: probeDefaultsKey)
        let canWrite = readBack == testValue
        let canRead = readBack != nil
        let fileResult = writeAndReadProbeFile(value: testValue, containerURL: containerURL)

        let result = DiagnosticResult(
            canWrite: canWrite,
            canRead: canRead,
            appGroupID: AppGroup.identifier,
            containerExists: containerURL != nil,
            canWriteFile: fileResult.canWrite,
            canReadFile: fileResult.canRead,
            fileName: probeFileName,
            fileValue: fileResult.value,
            timestamp: now
        )

        return result
    }

    private static func writeAndReadProbeFile(value: String, containerURL: URL?) -> (
        canWrite: Bool,
        canRead: Bool,
        value: String?
    ) {
        guard let containerURL else {
            return (false, false, nil)
        }

        let fileURL = containerURL.appendingPathComponent(probeFileName, isDirectory: false)
        let canWrite = (try? value.write(to: fileURL, atomically: true, encoding: .utf8)) != nil
        let readValue = try? String(contentsOf: fileURL, encoding: .utf8)
        return (canWrite, readValue == value, readValue)
    }
}
