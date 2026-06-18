import Foundation
import Darwin
import VoxFlowModelStore

public enum Qwen3RuntimeRoute: Equatable, Sendable {
    case fluidAudioCoreML
    case mlxWorker(executableName: String)
}

public struct Qwen3RuntimePlan: Equatable, Sendable {
    public let route: Qwen3RuntimeRoute
    public let minimumMemoryBytes: UInt64
    public let supportedArchitectures: [ModelArchitecture]

    public init(
        route: Qwen3RuntimeRoute,
        minimumMemoryBytes: UInt64,
        supportedArchitectures: [ModelArchitecture]
    ) {
        self.route = route
        self.minimumMemoryBytes = minimumMemoryBytes
        self.supportedArchitectures = supportedArchitectures
    }

    public static func plan(for variant: Qwen3ModelVariant) -> Qwen3RuntimePlan {
        switch variant {
        case .qwen06CoreMLInt8:
            return Qwen3RuntimePlan(
                route: .fluidAudioCoreML,
                minimumMemoryBytes: 8 * 1_024 * 1_024 * 1_024,
                supportedArchitectures: [.arm64]
            )
        case .qwen17MLX4Bit:
            return Qwen3RuntimePlan(
                route: .mlxWorker(executableName: "voxflow-qwen3-mlx-worker"),
                minimumMemoryBytes: 16 * 1_024 * 1_024 * 1_024,
                supportedArchitectures: [.arm64]
            )
        }
    }
}

public enum Qwen3RuntimePreflightResult: Equatable, Sendable {
    case supported
    case runtimeUnsupported(reason: String)
    case hardwareUnsupported(reason: String)

    public var isSupported: Bool {
        self == .supported
    }

    public var reason: String? {
        switch self {
        case .supported:
            return nil
        case .runtimeUnsupported(let reason),
             .hardwareUnsupported(let reason):
            return reason
        }
    }
}

public enum Qwen3MLXWorkerHealthStatus: Equatable, Sendable {
    case healthy
    case missing
    case unhealthy(reason: String)
}

public enum Qwen3RuntimePreflight {
    public struct Environment: Sendable {
        public let architecture: ModelArchitecture
        public let physicalMemoryBytes: UInt64
        public let workerHealth: @Sendable (String) -> Qwen3MLXWorkerHealthStatus

        public init(
            architecture: ModelArchitecture,
            physicalMemoryBytes: UInt64,
            workerHealth: @escaping @Sendable (String) -> Qwen3MLXWorkerHealthStatus
        ) {
            self.architecture = architecture
            self.physicalMemoryBytes = physicalMemoryBytes
            self.workerHealth = workerHealth
        }

        public static func current(
            processInfo: ProcessInfo = .processInfo,
            bundle: Bundle = .main
        ) -> Environment {
            Environment(
                architecture: Self.currentArchitecture,
                physicalMemoryBytes: processInfo.physicalMemory,
                workerHealth: { executableName in
                    Qwen3MLXWorkerHealthChecker.check(executableName: executableName, bundle: bundle)
                }
            )
        }

        private static var currentArchitecture: ModelArchitecture {
            #if arch(arm64)
            return .arm64
            #else
            return .x86_64
            #endif
        }
    }

    public static func evaluate(
        variant: Qwen3ModelVariant,
        environment: Environment = .current()
    ) -> Qwen3RuntimePreflightResult {
        let plan = Qwen3RuntimePlan.plan(for: variant)
        guard plan.supportedArchitectures.contains(environment.architecture) else {
            return .hardwareUnsupported(
                reason: "Qwen3-ASR \(variant.displayModelSize) 不支持当前架构。"
            )
        }
        guard environment.physicalMemoryBytes >= plan.minimumMemoryBytes else {
            return .hardwareUnsupported(
                reason: "Qwen3-ASR \(variant.displayModelSize) 至少需要 \(plan.minimumMemoryBytes / 1_024 / 1_024 / 1_024)GB 内存。"
            )
        }
        switch plan.route {
        case .fluidAudioCoreML:
            return .supported
        case .mlxWorker(let executableName):
            switch environment.workerHealth(executableName) {
            case .healthy:
                return .supported
            case .missing:
                return .runtimeUnsupported(
                    reason: "Qwen3-ASR \(variant.displayModelSize) 需要 MLX 本地 worker：\(executableName)。"
                )
            case .unhealthy(let reason):
                return .runtimeUnsupported(
                    reason: "Qwen3-ASR \(variant.displayModelSize) MLX worker 不可用：\(reason)"
                )
            }
        }
    }
}

public enum Qwen3MLXWorkerHealthChecker {
    public static func check(
        executableName: String = "voxflow-qwen3-mlx-worker",
        bundle: Bundle = .main
    ) -> Qwen3MLXWorkerHealthStatus {
        guard let launchCommand = try? Qwen3MLXWorkerExecutableResolver.launchCommand(
            executableName: executableName,
            bundle: bundle
        ) else {
            return .missing
        }
        return check(launchCommand: launchCommand)
    }

    public static func check(executableURL: URL) -> Qwen3MLXWorkerHealthStatus {
        check(
            launchCommand: Qwen3MLXWorkerExecutableResolver.LaunchCommand(
                executableURL: executableURL,
                arguments: []
            )
        )
    }

    public static func check(
        launchCommand: Qwen3MLXWorkerExecutableResolver.LaunchCommand
    ) -> Qwen3MLXWorkerHealthStatus {
        let process = Process()
        let output = Pipe()
        process.executableURL = launchCommand.executableURL
        process.arguments = launchCommand.arguments + ["--health"]
        process.standardOutput = output
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return .unhealthy(reason: error.localizedDescription)
        }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            return .unhealthy(reason: "health probe exited with status \(process.terminationStatus)")
        }
        do {
            let payload = try JSONDecoder().decode(HealthPayload.self, from: data)
            switch payload.status {
            case "healthy":
                return .healthy
            case "missing":
                return .missing
            default:
                return .unhealthy(reason: payload.reason ?? "health probe returned \(payload.status)")
            }
        } catch {
            return .unhealthy(reason: "health probe returned invalid JSON")
        }
    }

    private struct HealthPayload: Decodable {
        let type: String
        let status: String
        let reason: String?
    }
}

public extension Qwen3ModelVariant {
    var displayModelSize: String {
        switch self {
        case .qwen06CoreMLInt8:
            return "0.6B"
        case .qwen17MLX4Bit:
            return "1.7B"
        }
    }
}
