import Foundation

extension ApplicationSupportPaths {
    var agentRouterDirectory: URL {
        rootDirectory.appendingPathComponent("AgentRouter", isDirectory: true)
    }

    var agentRouterSocketURL: URL {
        agentRouterDirectory.appendingPathComponent("router.sock", isDirectory: false)
    }

    var cliBinDirectory: URL {
        rootDirectory.appendingPathComponent("bin", isDirectory: true)
    }
}

enum AgentRouterHealthDecision: Equatable {
    case start
    case keep
    case restart
}

struct AgentCLIRegistrationPlan: Equatable {
    let helperURL: URL
    let voxflowDestination: URL
    let voxDestination: URL
    let examples: [String]
}

struct AgentCLIRegistrationPreview: Equatable {
    let profileURL: URL
    let shellBlock: String
}

@MainActor
final class AgentHelperManager {
    private let paths: ApplicationSupportPaths
    private let helperURL: URL
    private let shimURL: URL
    private let homeDirectory: URL
    private let shellURL: URL
    private var routerProcess: Process?
    private var healthTimer: Timer?
    private var routerStartedAt: Date?
    private var shouldMaintainRouter = false

    init(
        paths: ApplicationSupportPaths,
        bundleURL: URL = Bundle.main.bundleURL,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        shellURL: URL = URL(
            fileURLWithPath: ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        )
    ) {
        self.paths = paths
        self.homeDirectory = homeDirectory
        self.shellURL = shellURL
        let helpers = bundleURL.appendingPathComponent("Contents/Helpers", isDirectory: true)
        helperURL = helpers.appendingPathComponent("voxflow", isDirectory: false)
        shimURL = helpers.appendingPathComponent("vox", isDirectory: false)
        AppLogger.general.debug("AgentHelperManager initialized helperPath=\(helpers.path)")
    }

    static func healthDecision(
        processRunning: Bool,
        socketReachable: Bool
    ) -> AgentRouterHealthDecision {
        switch (processRunning, socketReachable) {
        case (false, false): return .start
        case (false, true): return .keep
        case (true, true): return .keep
        case (true, false): return .restart
        }
    }

    static func registrationPlan(
        helperURL: URL,
        binDirectory: URL
    ) -> AgentCLIRegistrationPlan {
        AgentCLIRegistrationPlan(
            helperURL: helperURL,
            voxflowDestination: binDirectory.appendingPathComponent("voxflow"),
            voxDestination: binDirectory.appendingPathComponent("vox"),
            examples: [
                "vox flow codex",
                "vox flow --claude",
                "vox flow --codebuddy",
            ]
        )
    }

    static func registrationPreview(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        shellURL: URL = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh")
    ) -> AgentCLIRegistrationPreview {
        let commandDirectory = homeDirectory.appendingPathComponent(".local/bin", isDirectory: true)
        return AgentCLIRegistrationPreview(
            profileURL: shellProfileURL(homeDirectory: homeDirectory, shellURL: shellURL),
            shellBlock: shellPathBlock(commandDirectory: commandDirectory, homeDirectory: homeDirectory)
        )
    }

    var socketURL: URL { paths.agentRouterSocketURL }

    func startRouter() async throws {
        AppLogger.general.debug("AgentHelperManager startRouter invoked")
        shouldMaintainRouter = true
        try paths.ensureDirectories()
        try secureExistingRouterPaths()
        guard FileManager.default.isExecutableFile(atPath: helperURL.path) else {
            AppLogger.general.warning("AgentHelperManager helper missing helperPath=\(helperURL.path)")
            throw AgentHelperManagerError.helperMissing(helperURL.path)
        }
        if routerProcess?.isRunning == true { return }
        if await socketIsReachable() {
            AppLogger.general.debug("AgentHelperManager socket reachable; keep existing router")
            startHealthMonitoring()
            return
        }

        try? FileManager.default.removeItem(at: paths.agentRouterSocketURL)
        let process = Process()
        process.executableURL = helperURL
        process.arguments = ["serve"]
        process.environment = ProcessInfo.processInfo.environment.merging([
            "VOXFLOW_AGENT_ROUTER_HOME": paths.agentRouterDirectory.path,
        ]) { _, value in value }
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { [weak self] process in
            Task { @MainActor in
                guard self?.routerProcess === process else { return }
                self?.routerProcess = nil
            }
        }
        try process.run()
        routerProcess = process
        routerStartedAt = Date()
        AppLogger.general.info("AgentHelperManager router started pid=\(process.processIdentifier)")
        startHealthMonitoring()
    }

    func secureExistingRouterPaths(fileManager: FileManager = .default) throws {
        if fileManager.fileExists(atPath: paths.agentRouterDirectory.path) {
            try fileManager.setAttributes(
                [.posixPermissions: NSNumber(value: Int16(0o700))],
                ofItemAtPath: paths.agentRouterDirectory.path
            )
        }
        if fileManager.fileExists(atPath: paths.agentRouterSocketURL.path) {
            try fileManager.setAttributes(
                [.posixPermissions: NSNumber(value: Int16(0o600))],
                ofItemAtPath: paths.agentRouterSocketURL.path
            )
        }
    }

    func stopRouter() {
        AppLogger.general.debug("AgentHelperManager stopRouter invoked")
        shouldMaintainRouter = false
        healthTimer?.invalidate()
        healthTimer = nil
        guard let process = routerProcess else { return }
        if process.isRunning { process.terminate() }
        routerProcess = nil
    }

    private func startHealthMonitoring() {
        AppLogger.general.debug("AgentHelperManager startHealthMonitoring")
        guard healthTimer == nil else { return }
        healthTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.repairRouterIfNeeded()
            }
        }
    }

    private func repairRouterIfNeeded() async {
        guard shouldMaintainRouter else { return }
        let running = routerProcess?.isRunning == true
        let socketReachable = await socketIsReachable()
        AppLogger.general.debug("AgentHelperManager health state running=\(running) socketReachable=\(socketReachable)")
        if running,
           !socketReachable,
           Date().timeIntervalSince(routerStartedAt ?? .distantPast) < 2 {
            return
        }
        switch Self.healthDecision(processRunning: running, socketReachable: socketReachable) {
        case .keep:
            return
        case .restart:
            AppLogger.general.debug("AgentHelperManager health decision: restart")
            routerProcess?.terminate()
            routerProcess = nil
            try? await startRouter()
        case .start:
            AppLogger.general.debug("AgentHelperManager health decision: start")
            try? await startRouter()
        }
    }

    private func socketIsReachable() async -> Bool {
        let request: [String: Any] = [
            "id": 0,
            "method": "list_agents",
            "params": [:],
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: request) else {
            return false
        }
        return (try? await UnixAgentRouterTransport(socketURL: paths.agentRouterSocketURL).send(data)) != nil
    }

    @discardableResult
    func registerCLI() throws -> AgentCLIRegistrationStatus {
        try paths.ensureDirectories()
        guard FileManager.default.isExecutableFile(atPath: helperURL.path) else {
            throw AgentHelperManagerError.helperMissing(helperURL.path)
        }
        guard FileManager.default.fileExists(atPath: shimURL.path) else {
            throw AgentHelperManagerError.shimMissing(shimURL.path)
        }

        let plan = Self.registrationPlan(helperURL: helperURL, binDirectory: paths.cliBinDirectory)
        try install(source: helperURL, destination: plan.voxflowDestination)
        try install(source: shimURL, destination: plan.voxDestination)
        let commandDirectory = homeDirectory.appendingPathComponent(".local/bin", isDirectory: true)
        try FileManager.default.createDirectory(at: commandDirectory, withIntermediateDirectories: true)
        try expose(
            managedCommand: plan.voxflowDestination,
            at: commandDirectory.appendingPathComponent("voxflow")
        )
        try expose(
            managedCommand: plan.voxDestination,
            at: commandDirectory.appendingPathComponent("vox")
        )
        try configureShellPath(commandDirectory: commandDirectory)
        let pathEntries = ProcessInfo.processInfo.environment["PATH"]?
            .split(separator: ":")
            .map(String.init) ?? []
        return AgentCLIRegistrationStatus(
            binDirectory: commandDirectory,
            isOnCurrentPath: pathEntries.contains(commandDirectory.path),
            examples: plan.examples
        )
    }

    func unregisterCLI() throws {
        let commandDirectory = homeDirectory.appendingPathComponent(".local/bin", isDirectory: true)
        try removeManagedCommandLink(
            at: commandDirectory.appendingPathComponent("voxflow"),
            managedCommand: paths.cliBinDirectory.appendingPathComponent("voxflow")
        )
        try removeManagedCommandLink(
            at: commandDirectory.appendingPathComponent("vox"),
            managedCommand: paths.cliBinDirectory.appendingPathComponent("vox")
        )
        try removeShellPathBlock()
    }

    private func expose(managedCommand: URL, at destination: URL) throws {
        let fileManager = FileManager.default
        if let existingTarget = try? fileManager.destinationOfSymbolicLink(atPath: destination.path) {
            let existingTargetURL = existingTarget.hasPrefix("/")
                ? URL(fileURLWithPath: existingTarget)
                : destination.deletingLastPathComponent().appendingPathComponent(existingTarget)
            if existingTargetURL.standardizedFileURL == managedCommand.standardizedFileURL {
                return
            }
            if fileManager.fileExists(atPath: existingTargetURL.path) {
                throw AgentHelperManagerError.commandConflict(destination.path)
            }
            try fileManager.removeItem(at: destination)
        }
        if fileManager.fileExists(atPath: destination.path) {
            throw AgentHelperManagerError.commandConflict(destination.path)
        }
        try fileManager.createSymbolicLink(
            atPath: destination.path,
            withDestinationPath: managedCommand.path
        )
    }

    private func configureShellPath(commandDirectory: URL) throws {
        let profileURL = Self.shellProfileURL(homeDirectory: homeDirectory, shellURL: shellURL)
        let marker = "# VoxFlow CLI"
        var profile = (try? String(contentsOf: profileURL, encoding: .utf8)) ?? ""
        guard !profile.contains(marker) else { return }
        try backupProfileIfNeeded(profileURL: profileURL, contents: profile)
        if !profile.isEmpty, !profile.hasSuffix("\n") {
            profile.append("\n")
        }
        profile.append("\n\(Self.shellPathBlock(commandDirectory: commandDirectory, homeDirectory: homeDirectory))\n")
        try FileManager.default.createDirectory(at: homeDirectory, withIntermediateDirectories: true)
        try profile.write(to: profileURL, atomically: true, encoding: .utf8)
    }

    private func removeShellPathBlock() throws {
        let profileURL = Self.shellProfileURL(homeDirectory: homeDirectory, shellURL: shellURL)
        guard var profile = try? String(contentsOf: profileURL, encoding: .utf8) else { return }
        let block = Self.shellPathBlock(
            commandDirectory: homeDirectory.appendingPathComponent(".local/bin", isDirectory: true),
            homeDirectory: homeDirectory
        )
        profile = profile.replacingOccurrences(of: "\n\(block)\n", with: "\n")
        profile = profile.replacingOccurrences(of: "\(block)\n", with: "")
        profile = profile.replacingOccurrences(of: "\n\(block)", with: "")
        profile = profile.replacingOccurrences(of: block, with: "")
        try profile.write(to: profileURL, atomically: true, encoding: .utf8)
    }

    private func backupProfileIfNeeded(profileURL: URL, contents: String) throws {
        let backupURL = profileURL.deletingLastPathComponent()
            .appendingPathComponent("\(profileURL.lastPathComponent).voxflow.bak")
        guard !FileManager.default.fileExists(atPath: backupURL.path) else { return }
        try FileManager.default.createDirectory(
            at: profileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try contents.write(to: backupURL, atomically: true, encoding: .utf8)
    }

    private func removeManagedCommandLink(at destination: URL, managedCommand: URL) throws {
        let fileManager = FileManager.default
        guard let existingTarget = try? fileManager.destinationOfSymbolicLink(atPath: destination.path) else {
            return
        }
        let existingTargetURL = existingTarget.hasPrefix("/")
            ? URL(fileURLWithPath: existingTarget)
            : destination.deletingLastPathComponent().appendingPathComponent(existingTarget)
        guard existingTargetURL.standardizedFileURL == managedCommand.standardizedFileURL else {
            return
        }
        try fileManager.removeItem(at: destination)
    }

    private static func shellProfileURL(homeDirectory: URL, shellURL: URL) -> URL {
        switch shellURL.lastPathComponent {
        case "zsh":
            return homeDirectory.appendingPathComponent(".zprofile")
        case "bash":
            return homeDirectory.appendingPathComponent(".bash_profile")
        default:
            return homeDirectory.appendingPathComponent(".profile")
        }
    }

    private static func shellPathBlock(commandDirectory: URL, homeDirectory: URL) -> String {
        let relativePath = commandDirectory.path.replacingOccurrences(
            of: homeDirectory.path,
            with: "$HOME"
        )
        return "# VoxFlow CLI\nexport PATH=\"\(relativePath):$PATH\""
    }

    private func install(source: URL, destination: URL) throws {
        let fileManager = FileManager.default
        try? fileManager.removeItem(at: destination)
        try fileManager.copyItem(at: source, to: destination)
        try fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o755))],
            ofItemAtPath: destination.path
        )
    }
}

struct AgentCLIRegistrationStatus: Equatable {
    let binDirectory: URL
    let isOnCurrentPath: Bool
    let examples: [String]
}

enum AgentHelperManagerError: LocalizedError, Equatable {
    case helperMissing(String)
    case shimMissing(String)
    case commandConflict(String)

    var errorDescription: String? {
        switch self {
        case let .helperMissing(path): return L10n.format("agent.helper.error_component_missing_format", comment: "AI helper component missing error", path)
        case let .shimMissing(path): return L10n.format("agent.helper.error_shim_missing_format", comment: "Agent shim missing error", path)
        case let .commandConflict(path): return L10n.format("agent.helper.error_command_conflict_format", comment: "Command conflict error", path)
        }
    }
}

enum AgentRouterClientError: LocalizedError, Equatable {
    case router(String)
    case invalidResponse
    case requestTooLarge
    case timeout

    var errorDescription: String? {
        switch self {
        case let .router(message): return message
        case .invalidResponse: return L10n.localize("agent.helper.error_invalid_response", comment: "Invalid AI response error")
        case .requestTooLarge: return L10n.localize("agent.helper.error_request_too_large", comment: "Request too long error")
        case .timeout: return L10n.localize("agent.helper.error_timeout", comment: "AI timeout error")
        }
    }
}
