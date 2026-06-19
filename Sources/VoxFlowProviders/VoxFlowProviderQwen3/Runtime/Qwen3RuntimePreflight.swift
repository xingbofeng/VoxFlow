import Darwin
import Foundation
import VoxFlowModelStore

public enum Qwen3RuntimeRoute: Equatable, Sendable {
    case speechSwiftQwen3ASR(modelID: String)
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
        case .qwen06SpeechSwift4Bit:
            return Qwen3RuntimePlan(
                route: .speechSwiftQwen3ASR(
                    modelID: SpeechSwiftQwen3StreamingSessionFactory.smallModelID
                ),
                minimumMemoryBytes: 8 * 1_024 * 1_024 * 1_024,
                supportedArchitectures: [.arm64]
            )
        case .qwen17SpeechSwift8Bit:
            return Qwen3RuntimePlan(
                route: .speechSwiftQwen3ASR(
                    modelID: SpeechSwiftQwen3StreamingSessionFactory.largeModelID
                ),
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

public enum Qwen3RuntimePreflight {
    public struct Environment: Sendable {
        public let architecture: ModelArchitecture
        public let physicalMemoryBytes: UInt64

        public init(
            architecture: ModelArchitecture,
            physicalMemoryBytes: UInt64
        ) {
            self.architecture = architecture
            self.physicalMemoryBytes = physicalMemoryBytes
        }

        public static func current(processInfo: ProcessInfo = .processInfo) -> Environment {
            Environment(
                architecture: Self.currentArchitecture,
                physicalMemoryBytes: processInfo.physicalMemory
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
        return .supported
    }
}

public extension Qwen3ModelVariant {
    var displayModelSize: String {
        switch self {
        case .qwen06SpeechSwift4Bit:
            return "0.6B"
        case .qwen17SpeechSwift8Bit:
            return "1.7B"
        }
    }
}
