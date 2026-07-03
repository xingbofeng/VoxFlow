import Foundation

protocol LocalAgentProviderChecking: AgentRuntimeAvailabilityDetecting, AgentRuntimeModelListing {}

struct LocalAgentCLIHelpCheck: Equatable, Sendable {
    let arguments: [String]
    let requiredFragments: [String]
}

struct LocalAgentCLIConfiguration: Equatable, Sendable {
    let cacheTTL: TimeInterval
    let candidateCLIPaths: [String]
    let versionArguments: [String]
    let helpChecks: [LocalAgentCLIHelpCheck]
    let modelListArguments: [String]?
    let fallbackModelIDs: [String]
    let claudeSettingsURL: URL?

    init(
        cacheTTL: TimeInterval = 60,
        candidateCLIPaths: [String],
        versionArguments: [String] = ["--version"],
        helpChecks: [LocalAgentCLIHelpCheck] = [],
        modelListArguments: [String]? = nil,
        fallbackModelIDs: [String] = [],
        claudeSettingsURL: URL? = nil
    ) {
        self.cacheTTL = cacheTTL
        self.candidateCLIPaths = candidateCLIPaths
        self.versionArguments = versionArguments
        self.helpChecks = helpChecks
        self.modelListArguments = modelListArguments
        self.fallbackModelIDs = fallbackModelIDs
        self.claudeSettingsURL = claudeSettingsURL
    }

    static func `default`(for descriptor: LocalAgentProviderDescriptor) -> LocalAgentCLIConfiguration {
        switch descriptor.providerID {
        case AgentProviderRegistry.voxflowAgent.providerID:
            return LocalAgentCLIConfiguration(
                candidateCLIPaths: builtinAgentHelperCandidates(),
                versionArguments: ["builtin-agent", "--version"],
                helpChecks: [
                    LocalAgentCLIHelpCheck(
                        arguments: ["builtin-agent", "--help"],
                        requiredFragments: ["builtin-agent", "stdio"]
                    )
                ],
                modelListArguments: nil,
                fallbackModelIDs: [
                    "current-default-llm"
                ]
            )
        case AgentProviderRegistry.codex.providerID:
            return LocalAgentCLIConfiguration(
                candidateCLIPaths: [
                    "/Applications/Codex.app/Contents/Resources/codex",
                    "/opt/homebrew/bin/codex",
                    "/usr/local/bin/codex"
                ],
                helpChecks: [
                    LocalAgentCLIHelpCheck(
                        arguments: ["app-server", "--help"],
                        requiredFragments: ["app-server"]
                    )
                ],
                modelListArguments: nil,
                fallbackModelIDs: [
                    "gpt-5.5",
                    "gpt-5.4",
                    "gpt-5.3-codex"
                ]
            )
        case AgentProviderRegistry.opencode.providerID:
            return LocalAgentCLIConfiguration(
                candidateCLIPaths: ["opencode"],
                helpChecks: [
                    LocalAgentCLIHelpCheck(
                        arguments: ["run", "--help"],
                        requiredFragments: ["run", "format", "json"]
                    )
                ],
                modelListArguments: ["models"]
            )
        case AgentProviderRegistry.claude.providerID:
            return LocalAgentCLIConfiguration(
                candidateCLIPaths: ["claude"],
                helpChecks: [
                    LocalAgentCLIHelpCheck(
                        arguments: ["--help"],
                        requiredFragments: ["print"]
                    )
                ],
                modelListArguments: nil,
                claudeSettingsURL: FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent(".claude/settings.json", isDirectory: false)
            )
        case AgentProviderRegistry.codebuddy.providerID:
            return LocalAgentCLIConfiguration(
                candidateCLIPaths: ["codebuddy"],
                helpChecks: [
                    LocalAgentCLIHelpCheck(
                        arguments: ["--help"],
                        requiredFragments: ["print"]
                    )
                ],
                modelListArguments: ["--help"]
            )
        case AgentProviderRegistry.pi.providerID:
            return LocalAgentCLIConfiguration(
                candidateCLIPaths: ["pi"],
                helpChecks: [
                    LocalAgentCLIHelpCheck(
                        arguments: ["--help"],
                        requiredFragments: ["print"]
                    )
                ],
                modelListArguments: ["--list-models"]
            )
        default:
            return LocalAgentCLIConfiguration(
                candidateCLIPaths: descriptor.executableNames
            )
        }
    }

    private static func builtinAgentHelperCandidates() -> [String] {
        var candidates: [String] = []
        if let executablePath = Bundle.main.executableURL?.path {
            candidates.append(
                URL(fileURLWithPath: executablePath)
                    .deletingLastPathComponent()
                    .appendingPathComponent("../Helpers/voxflow", isDirectory: false)
                    .standardizedFileURL
                    .path
            )
        }
        candidates.append("voxflow")
        return candidates
    }
}

actor LocalAgentCLIAdapter: LocalAgentProviderChecking {
    let descriptor: LocalAgentProviderDescriptor
    private let configuration: LocalAgentCLIConfiguration
    private let clock: any AppClock
    private var cached: AgentRuntimeAvailability?

    init(
        descriptor: LocalAgentProviderDescriptor,
        configuration: LocalAgentCLIConfiguration,
        clock: any AppClock = SystemClock()
    ) {
        self.descriptor = descriptor
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

    func listModels(cliPath: String) async -> [String] {
        if descriptor.providerID == AgentProviderRegistry.claude.providerID,
           let modelID = Self.claudeConfiguredModelID(settingsURL: configuration.claudeSettingsURL) {
            return [modelID]
        }
        guard let arguments = configuration.modelListArguments else {
            return configuration.fallbackModelIDs
        }
        let fallbackModelIDs = configuration.fallbackModelIDs
        return await Task.detached(priority: .utility) {
            let result = Self.run(cliPath, arguments: arguments)
            guard result.exitCode == 0 else { return fallbackModelIDs }
            let output = Self.readableOutput(from: result)
            let models = Self.parseModelIDs(from: output)
            return models.isEmpty ? fallbackModelIDs : models
        }.value
    }

    static func claudeConfiguredModelID(settingsURL: URL?) -> String? {
        guard let settingsURL,
              let data = try? Data(contentsOf: settingsURL),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        guard let rawModel = object["model"] as? String else {
            return nil
        }
        let model = rawModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else { return nil }

        let env = object["env"] as? [String: Any] ?? [:]
        let family = model.uppercased().replacingOccurrences(of: "-", with: "_")
        for key in [
            "ANTHROPIC_DEFAULT_\(family)_MODEL_NAME",
            "ANTHROPIC_DEFAULT_\(family)_MODEL"
        ] {
            if let value = env[key] as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            }
        }
        return model
    }

    private func detect(now: Date) -> AgentRuntimeAvailability {
        guard let cliPath = firstExistingCLIPath() else {
            return unavailable(
                "\(descriptor.displayName) CLI 不可用",
                now: now,
                cliPath: nil,
                cliVersion: nil
            )
        }

        let versionResult = Self.run(cliPath, arguments: configuration.versionArguments)
        let version = Self.readableOutput(from: versionResult)
        guard versionResult.exitCode == 0, !version.isEmpty else {
            return unavailable(
                "无法读取 \(descriptor.displayName) CLI 版本",
                now: now,
                cliPath: cliPath,
                cliVersion: nil
            )
        }

        for check in configuration.helpChecks {
            let result = Self.run(cliPath, arguments: check.arguments)
            let output = result.stdout + "\n" + result.stderr
            guard result.exitCode == 0,
                  check.requiredFragments.allSatisfy({ output.localizedCaseInsensitiveContains($0) }) else {
                return unavailable(
                    "\(descriptor.displayName) CLI 缺少必需能力",
                    now: now,
                    cliPath: cliPath,
                    cliVersion: version
                )
            }
        }

        return AgentRuntimeAvailability(
            providerID: descriptor.providerID,
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
            providerID: descriptor.providerID,
            status: .unavailable(reason: reason),
            detectedAt: now,
            expiresAt: now.addingTimeInterval(configuration.cacheTTL),
            cliPath: cliPath,
            cliVersion: cliVersion
        )
    }

    private func firstExistingCLIPath() -> String? {
        configuration.candidateCLIPaths.first {
            executablePath(for: $0) != nil
        }.flatMap(executablePath(for:))
    }

    private func executablePath(for candidate: String) -> String? {
        if candidate.contains("/") {
            return FileManager.default.isExecutableFile(atPath: candidate) ? candidate : nil
        }
        let pathDirectories = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
        let commonDirectories = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin"
        ]
        for directory in pathDirectories + commonDirectories {
            let path = URL(fileURLWithPath: directory)
                .appendingPathComponent(candidate)
                .path
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }

    private static func run(_ launchPath: String, arguments: [String]) -> LocalAgentProcessResult {
        do {
            return try LocalAgentProcessRunner.run(launchPath, arguments: arguments)
        } catch {
            return LocalAgentProcessResult(
                exitCode: -1,
                stdout: "",
                stderr: error.localizedDescription,
                timedOut: false
            )
        }
    }

    private static func readableOutput(from result: LocalAgentProcessResult) -> String {
        let stdout = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if !stdout.isEmpty { return stdout }
        return result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func parseModelIDs(from output: String) -> [String] {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        if let supported = supportedModelIDs(fromHelpText: trimmed), !supported.isEmpty {
            return supported
        }
        if let tableModels = tableModelIDs(from: trimmed), !tableModels.isEmpty {
            return tableModels
        }
        if let data = trimmed.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) {
            return unique(modelIDs(from: json))
        }
        return unique(
            trimmed
                .split(whereSeparator: \.isNewline)
                .map { line in
                    line
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "-*• "))
                }
                .filter { !$0.isEmpty }
        )
    }

    private static func supportedModelIDs(fromHelpText output: String) -> [String]? {
        guard let range = output.range(of: "Currently supported:") else { return nil }
        let remainder = output[range.upperBound...]
        guard let open = remainder.firstIndex(of: "("),
              let close = remainder[open...].firstIndex(of: ")") else {
            return nil
        }
        return unique(
            remainder[remainder.index(after: open)..<close]
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        )
    }

    private static func tableModelIDs(from output: String) -> [String]? {
        let lines = output
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard let headerIndex = lines.firstIndex(where: { line in
            let columns = line.split(whereSeparator: \.isWhitespace).map(String.init)
            return columns.count >= 2 &&
                columns[0].caseInsensitiveCompare("provider") == .orderedSame &&
                columns[1].caseInsensitiveCompare("model") == .orderedSame
        }) else {
            return nil
        }
        return unique(
            lines[(headerIndex + 1)...].compactMap { line in
                let columns = line.split(whereSeparator: \.isWhitespace).map(String.init)
                return columns.count >= 2 ? columns[1] : nil
            }
        )
    }

    private static func modelIDs(from json: Any) -> [String] {
        if let array = json as? [Any] {
            return array.flatMap(modelIDs(from:))
        }
        guard let object = json as? [String: Any] else { return [] }
        if object["hidden"] as? Bool == true {
            return []
        }
        if let models = object["data"] {
            return modelIDs(from: models)
        }
        if let models = object["models"] {
            return modelIDs(from: models)
        }
        if let result = object["result"] {
            return modelIDs(from: result)
        }
        if let id = object["id"] as? String {
            return [id]
        }
        if let model = object["model"] as? String {
            return [model]
        }
        if let name = object["name"] as? String {
            return [name]
        }
        return []
    }

    private static func unique(_ values: [String]) -> [String] {
        var result: [String] = []
        for value in values {
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty, !result.contains(normalized) else { continue }
            result.append(normalized)
        }
        return result
    }
}
