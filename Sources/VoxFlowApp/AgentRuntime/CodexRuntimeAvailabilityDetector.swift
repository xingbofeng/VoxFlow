import Foundation

protocol AgentRuntimeAvailabilityDetecting: Sendable {
    func cachedOrDetect(forceRefresh: Bool) async -> AgentRuntimeAvailability
}

struct CodexRuntimeDetectorConfiguration: Equatable, Sendable {
    let providerID: String
    let cacheTTL: TimeInterval
    let candidateCLIPaths: [String]

    static let `default` = CodexRuntimeDetectorConfiguration(
        providerID: AgentProviderRegistry.codex.providerID,
        cacheTTL: 60,
        candidateCLIPaths: [
            "/Applications/Codex.app/Contents/Resources/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex"
        ]
    )
}

actor CodexRuntimeAvailabilityDetector: AgentRuntimeAvailabilityDetecting {
    private let configuration: CodexRuntimeDetectorConfiguration
    private let clock: any AppClock
    private var cached: AgentRuntimeAvailability?

    init(
        configuration: CodexRuntimeDetectorConfiguration = .default,
        clock: any AppClock = SystemClock()
    ) {
        self.configuration = configuration
        self.clock = clock
    }

    func cachedOrDetect(forceRefresh: Bool = false) async -> AgentRuntimeAvailability {
        let now = clock.now
        if !forceRefresh,
           let cached,
           cached.expiresAt > now {
            return cached
        }
        let detected = detect(now: now)
        cached = detected
        return detected
    }

    private func detect(now: Date) -> AgentRuntimeAvailability {
        guard let cliPath = firstExistingCLIPath() else {
            return unavailable(
                "Codex.app 内置 CLI 不可用",
                now: now,
                cliPath: nil,
                cliVersion: nil
            )
        }
        let versionResult = run(cliPath, arguments: ["--version"])
        let version = versionResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard versionResult.exitCode == 0, !version.isEmpty else {
            return unavailable(
                "无法读取 Codex CLI 版本",
                now: now,
                cliPath: cliPath,
                cliVersion: nil
            )
        }
        let helpResult = run(cliPath, arguments: ["app-server", "--help"])
        guard helpResult.exitCode == 0,
              helpResult.stdout.contains("app-server") || helpResult.stderr.contains("app-server") else {
            return unavailable(
                "Codex runtime app-server 不可用",
                now: now,
                cliPath: cliPath,
                cliVersion: version
            )
        }
        return AgentRuntimeAvailability(
            providerID: configuration.providerID,
            status: .available,
            detectedAt: now,
            expiresAt: now.addingTimeInterval(configuration.cacheTTL),
            cliPath: cliPath,
            cliVersion: version
        )
    }

    private func unavailable(
        _ reason: String,
        now: Date,
        cliPath: String?,
        cliVersion: String?
    ) -> AgentRuntimeAvailability {
        AgentRuntimeAvailability(
            providerID: configuration.providerID,
            status: .unavailable(reason: reason),
            detectedAt: now,
            expiresAt: now.addingTimeInterval(configuration.cacheTTL),
            cliPath: cliPath,
            cliVersion: cliVersion
        )
    }

    private func firstExistingCLIPath() -> String? {
        configuration.candidateCLIPaths.first {
            FileManager.default.isExecutableFile(atPath: $0)
        }
    }

    private func run(_ launchPath: String, arguments: [String]) -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return ProcessResult(exitCode: -1, stdout: "", stderr: error.localizedDescription)
        }

        let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return ProcessResult(exitCode: process.terminationStatus, stdout: stdout, stderr: stderr)
    }
}

private struct ProcessResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String
}
