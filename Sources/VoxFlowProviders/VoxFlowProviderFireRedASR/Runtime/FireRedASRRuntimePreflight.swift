import Foundation
import VoxFlowASRCore
import VoxFlowModelStore

/// FireRedASR2-AED 为什么不能在这台机器上跑。
///
/// 用类型而不是自由文本表达，让 App 层走既有 L10n 文案，而不是把 Provider 拼出来的句子塞进 HUD。
/// 门槛值与 `FireRedASRManifestCatalog` 同源，避免清单和预检各写一份常量。
public enum FireRedASRPreflightBlocker: Equatable, Sendable, CustomStringConvertible {
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

public enum FireRedASRRuntimePreflightOutcome: Equatable, Sendable {
    case usable
    case blocked(FireRedASRPreflightBlocker)

    public var isUsable: Bool {
        self == .usable
    }
}

public enum FireRedASRRuntimePreflight {
    /// 低于此值直接不提供该 Provider。AED 实测峰值 RSS 2814 MB。
    public static var requiredMemoryBytes: UInt64 {
        UInt64(FireRedASRManifestCatalog.minimumMemoryBytes)
    }

    public static var supportedArchitectures: [ModelArchitecture] {
        FireRedASRManifestCatalog.supportedArchitectures
    }

    public static var requiredMacOSMajorVersion: Int {
        Int(FireRedASRManifestCatalog.minimumOSVersion.split(separator: ".").first ?? "15") ?? 15
    }

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
    ) -> FireRedASRRuntimePreflightOutcome {
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
        return .usable
    }
}
