import Foundation
import VoxFlowASRCore
import VoxFlowModelStore

/// R2T2 为什么不能在这台机器上跑。用类型而不是自由文本表达，让 App 层可以走既有 L10n 文案，
/// 而不是把 Provider 拼出来的句子直接塞进 HUD。
public enum R2T2PreflightBlocker: Equatable, Sendable, CustomStringConvertible {
    case architectureUnsupported(required: [ModelArchitecture], actual: ModelArchitecture)
    case operatingSystemTooOld(requiredMajorVersion: Int, actualMajorVersion: Int)
    case insufficientMemory(requiredBytes: UInt64, actualBytes: UInt64)

    public var asrErrorCategory: ASRErrorCategory {
        switch self {
        case .architectureUnsupported, .operatingSystemTooOld:
            return .runtimeUnsupported
        case .insufficientMemory:
            return .hardwareUnsupported
        }
    }

    /// 仅用于日志与诊断；面向用户的文案由 App 层按 case 生成。
    public var description: String {
        switch self {
        case .architectureUnsupported(let required, let actual):
            let requiredTags = required.map(\.rawValue).joined(separator: "|")
            return "architecture_unsupported(required=\(requiredTags), actual=\(actual.rawValue))"
        case .operatingSystemTooOld(let required, let actual):
            return "os_too_old(required=\(required), actual=\(actual))"
        case .insufficientMemory(let requiredBytes, let actualBytes):
            return "insufficient_memory(required=\(requiredBytes), actual=\(actualBytes))"
        }
    }
}

/// 能跑，但低于推荐内存——只作为提示，不阻止选择。
public enum R2T2PreflightCaution: Equatable, Sendable {
    case memoryBelowRecommended(actualBytes: UInt64)
}

public enum R2T2RuntimePreflightOutcome: Equatable, Sendable {
    case usable
    case usableWithCaution(R2T2PreflightCaution)
    case blocked(R2T2PreflightBlocker)

    public var isUsable: Bool {
        switch self {
        case .usable, .usableWithCaution:
            return true
        case .blocked:
            return false
        }
    }
}

public enum R2T2RuntimePreflight {
    /// 尝试门槛：低于此值直接不提供该 Provider。
    public static let requiredMemoryBytes: UInt64 = 16 * 1_024 * 1_024 * 1_024
    /// 推荐门槛：达到此值才认为 8bit 权重 + 16 s 滚动窗口有舒适余量。
    public static let recommendedMemoryBytes: UInt64 = 24 * 1_024 * 1_024 * 1_024
    public static let requiredMacOSMajorVersion = 15
    public static let supportedArchitectures: [ModelArchitecture] = [.arm64]

    public struct Environment: Sendable {
        public let architecture: ModelArchitecture
        public let physicalMemoryBytes: UInt64
        public let macOSMajorVersion: Int

        public init(
            architecture: ModelArchitecture,
            physicalMemoryBytes: UInt64,
            macOSMajorVersion: Int
        ) {
            self.architecture = architecture
            self.physicalMemoryBytes = physicalMemoryBytes
            self.macOSMajorVersion = macOSMajorVersion
        }

        public static func current(processInfo: ProcessInfo = .processInfo) -> Environment {
            Environment(
                architecture: currentArchitecture,
                physicalMemoryBytes: processInfo.physicalMemory,
                macOSMajorVersion: processInfo.operatingSystemVersion.majorVersion
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
        environment: Environment = .current()
    ) -> R2T2RuntimePreflightOutcome {
        guard supportedArchitectures.contains(environment.architecture) else {
            return .blocked(
                .architectureUnsupported(
                    required: supportedArchitectures,
                    actual: environment.architecture
                )
            )
        }
        guard environment.macOSMajorVersion >= requiredMacOSMajorVersion else {
            return .blocked(
                .operatingSystemTooOld(
                    requiredMajorVersion: requiredMacOSMajorVersion,
                    actualMajorVersion: environment.macOSMajorVersion
                )
            )
        }
        guard environment.physicalMemoryBytes >= requiredMemoryBytes else {
            return .blocked(
                .insufficientMemory(
                    requiredBytes: requiredMemoryBytes,
                    actualBytes: environment.physicalMemoryBytes
                )
            )
        }
        guard environment.physicalMemoryBytes >= recommendedMemoryBytes else {
            return .usableWithCaution(
                .memoryBelowRecommended(actualBytes: environment.physicalMemoryBytes)
            )
        }
        return .usable
    }
}
