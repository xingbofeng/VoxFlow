import Foundation

public struct Qwen3MLXRuntimeLayout: Equatable, Sendable {
    public static let mlxAudioVersion = "0.4.4"

    public let rootURL: URL

    public init(applicationSupportURL: URL) {
        self.rootURL = applicationSupportURL
            .appendingPathComponent("VoxFlow", isDirectory: true)
            .appendingPathComponent("Runtimes", isDirectory: true)
            .appendingPathComponent("Qwen3MLX", isDirectory: true)
            .appendingPathComponent(Self.mlxAudioVersion, isDirectory: true)
    }

    public var pythonExecutableURL: URL {
        rootURL
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("python3")
    }

    public var metadataURL: URL {
        rootURL.appendingPathComponent("runtime.json")
    }

    public var packageRequirement: String {
        "mlx-audio==\(Self.mlxAudioVersion)"
    }

    public static func current(fileManager: FileManager = .default) -> Qwen3MLXRuntimeLayout {
        let applicationSupportURL = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        return Qwen3MLXRuntimeLayout(applicationSupportURL: applicationSupportURL)
    }
}

public struct Qwen3MLXRuntimeMetadata: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let mlxAudioVersion: String
    public let installedAt: Date

    public init(
        schemaVersion: Int = 1,
        mlxAudioVersion: String,
        installedAt: Date
    ) {
        self.schemaVersion = schemaVersion
        self.mlxAudioVersion = mlxAudioVersion
        self.installedAt = installedAt
    }
}

public struct Qwen3MLXRuntimeCommand: Equatable, Sendable {
    public let executableURL: URL
    public let arguments: [String]

    public init(executableURL: URL, arguments: [String]) {
        self.executableURL = executableURL
        self.arguments = arguments
    }
}

public struct Qwen3MLXRuntimeCommandResult: Equatable, Sendable {
    public let status: Int32
    public let output: String

    public init(status: Int32, output: String) {
        self.status = status
        self.output = output
    }
}

public protocol Qwen3MLXRuntimeCommandRunning: Sendable {
    func run(_ command: Qwen3MLXRuntimeCommand) async throws -> Qwen3MLXRuntimeCommandResult
}

public struct Qwen3MLXRuntimeProcessRunner: Qwen3MLXRuntimeCommandRunning {
    public init() {}

    public func run(_ command: Qwen3MLXRuntimeCommand) async throws -> Qwen3MLXRuntimeCommandResult {
        let process = Process()
        let output = Pipe()
        process.executableURL = command.executableURL
        process.arguments = command.arguments
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return Qwen3MLXRuntimeCommandResult(
            status: process.terminationStatus,
            output: String(data: data, encoding: .utf8) ?? ""
        )
    }
}

public protocol Qwen3MLXRuntimeProvisioning: Sendable {
    func prepare() async throws -> URL
}

public enum Qwen3MLXRuntimeProvisioningError: LocalizedError, Equatable, Sendable {
    case bootstrapPythonMissing
    case commandFailed(stage: String, status: Int32, output: String)
    case managedPythonMissing(String)
    case healthCheckFailed(String)

    public var errorDescription: String? {
        switch self {
        case .bootstrapPythonMissing:
            return "Qwen3-ASR 1.7B 需要 Python 3.11 或 3.12 来安装 MLX runtime。"
        case .commandFailed(let stage, let status, let output):
            let detail = output.trimmingCharacters(in: .whitespacesAndNewlines)
            return detail.isEmpty
                ? "Qwen3 MLX runtime \(stage)失败，退出码 \(status)。"
                : "Qwen3 MLX runtime \(stage)失败：\(detail)"
        case .managedPythonMissing(let path):
            return "Qwen3 MLX runtime 安装后缺少 Python：\(path)"
        case .healthCheckFailed(let reason):
            return "Qwen3 MLX runtime 健康检查失败：\(reason)"
        }
    }
}

public actor Qwen3MLXRuntimeProvisioner: Qwen3MLXRuntimeProvisioning {
    private let layout: Qwen3MLXRuntimeLayout
    private let fileManager: FileManager
    private let commandRunner: any Qwen3MLXRuntimeCommandRunning
    private let bootstrapPythonProvider: @Sendable () -> URL?
    private let workerURLProvider: @Sendable () throws -> URL
    private let healthChecker:
        @Sendable (Qwen3MLXWorkerExecutableResolver.LaunchCommand) -> Qwen3MLXWorkerHealthStatus
    private let now: @Sendable () -> Date

    public init(
        layout: Qwen3MLXRuntimeLayout = .current(),
        fileManager: FileManager = .default,
        commandRunner: any Qwen3MLXRuntimeCommandRunning = Qwen3MLXRuntimeProcessRunner(),
        bootstrapPythonProvider: @escaping @Sendable () -> URL? = {
            Qwen3MLXRuntimeProvisioner.resolveBootstrapPython()
        },
        workerURLProvider: @escaping @Sendable () throws -> URL = {
            try Qwen3MLXWorkerExecutableResolver.resolve()
        },
        healthChecker: @escaping @Sendable (
            Qwen3MLXWorkerExecutableResolver.LaunchCommand
        ) -> Qwen3MLXWorkerHealthStatus = {
            Qwen3MLXWorkerHealthChecker.check(launchCommand: $0)
        },
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.layout = layout
        self.fileManager = fileManager
        self.commandRunner = commandRunner
        self.bootstrapPythonProvider = bootstrapPythonProvider
        self.workerURLProvider = workerURLProvider
        self.healthChecker = healthChecker
        self.now = now
    }

    public func prepare() async throws -> URL {
        let workerURL = try workerURLProvider()
        if fileManager.isExecutableFile(atPath: layout.pythonExecutableURL.path),
           healthStatus(workerURL: workerURL) == .healthy {
            return layout.pythonExecutableURL
        }

        guard let bootstrapPythonURL = bootstrapPythonProvider() else {
            throw Qwen3MLXRuntimeProvisioningError.bootstrapPythonMissing
        }
        try fileManager.createDirectory(
            at: layout.rootURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try await runRequired(
            Qwen3MLXRuntimeCommand(
                executableURL: bootstrapPythonURL,
                arguments: ["-m", "venv", layout.rootURL.path]
            ),
            stage: "创建环境"
        )
        guard fileManager.isExecutableFile(atPath: layout.pythonExecutableURL.path) else {
            throw Qwen3MLXRuntimeProvisioningError.managedPythonMissing(
                layout.pythonExecutableURL.path
            )
        }
        try await runRequired(
            Qwen3MLXRuntimeCommand(
                executableURL: layout.pythonExecutableURL,
                arguments: [
                    "-m", "pip", "install",
                    "--disable-pip-version-check",
                    "--no-input",
                    "--upgrade",
                    layout.packageRequirement,
                ]
            ),
            stage: "安装依赖"
        )

        switch healthStatus(workerURL: workerURL) {
        case .healthy:
            break
        case .missing:
            throw Qwen3MLXRuntimeProvisioningError.healthCheckFailed("worker missing")
        case .unhealthy(let reason):
            throw Qwen3MLXRuntimeProvisioningError.healthCheckFailed(reason)
        }

        let metadata = Qwen3MLXRuntimeMetadata(
            mlxAudioVersion: Qwen3MLXRuntimeLayout.mlxAudioVersion,
            installedAt: now()
        )
        let metadataData = try JSONEncoder().encode(metadata)
        try metadataData.write(to: layout.metadataURL, options: .atomic)
        return layout.pythonExecutableURL
    }

    public nonisolated static func resolveBootstrapPython(
        fileManager: FileManager = .default
    ) -> URL? {
        bootstrapPythonCandidates
            .first(where: { fileManager.isExecutableFile(atPath: $0) })
            .map(URL.init(fileURLWithPath:))
    }

    private func runRequired(
        _ command: Qwen3MLXRuntimeCommand,
        stage: String
    ) async throws {
        let result = try await commandRunner.run(command)
        guard result.status == 0 else {
            throw Qwen3MLXRuntimeProvisioningError.commandFailed(
                stage: stage,
                status: result.status,
                output: result.output
            )
        }
    }

    private func healthStatus(workerURL: URL) -> Qwen3MLXWorkerHealthStatus {
        healthChecker(
            Qwen3MLXWorkerExecutableResolver.LaunchCommand(
                executableURL: layout.pythonExecutableURL,
                arguments: [workerURL.path]
            )
        )
    }

    private static let bootstrapPythonCandidates = [
        "/opt/homebrew/bin/python3.12",
        "/opt/homebrew/bin/python3.11",
        "/usr/local/bin/python3.12",
        "/usr/local/bin/python3.11",
    ]
}
