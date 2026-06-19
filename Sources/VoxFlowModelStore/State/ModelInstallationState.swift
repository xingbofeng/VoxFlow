import Foundation

public struct ModelComponentID: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public struct ModelDownloadProgress: Codable, Equatable, Sendable {
    public let bytesWritten: Int64
    public let totalBytes: Int64?
    public let componentID: ModelComponentID

    public init(
        bytesWritten: Int64,
        totalBytes: Int64?,
        componentID: ModelComponentID
    ) {
        self.bytesWritten = bytesWritten
        self.totalBytes = totalBytes
        self.componentID = componentID
    }

    public var fractionCompleted: Double? {
        guard let totalBytes, totalBytes > 0 else {
            return nil
        }
        return min(1, max(0, Double(bytesWritten) / Double(totalBytes)))
    }
}

public struct ModelInstallation: Codable, Equatable, Sendable {
    public let modelID: ModelID
    public let version: String
    public let installedRoot: URL

    public init(
        modelID: ModelID,
        version: String,
        installedRoot: URL
    ) {
        self.modelID = modelID
        self.version = version
        self.installedRoot = installedRoot
    }
}

public enum ModelInstallationState: Codable, Equatable, Sendable {
    case notInstalled
    case insufficientDisk(requiredBytes: Int64, availableBytes: Int64)
    case downloading(progress: ModelDownloadProgress)
    case paused(progress: ModelDownloadProgress)
    case verifying
    case extracting
    case compiling
    case warmingUp
    case canaryTesting
    case deleting(ModelInstallation)
    case ready(ModelInstallation)
    case corrupt(reason: String)
    case runtimeUnsupported(reason: String)
    case hardwareUnsupported(reason: String)
    case failed(message: String)

    public var isReady: Bool {
        switch self {
        case .ready:
            return true
        case .notInstalled,
             .insufficientDisk,
             .downloading,
             .paused,
             .verifying,
             .extracting,
             .compiling,
             .warmingUp,
             .canaryTesting,
             .deleting,
             .corrupt,
             .runtimeUnsupported,
             .hardwareUnsupported,
             .failed:
            return false
        }
    }

    public var isUnsupported: Bool {
        switch self {
        case .runtimeUnsupported, .hardwareUnsupported:
            return true
        case .notInstalled,
             .insufficientDisk,
             .downloading,
             .paused,
             .verifying,
             .extracting,
             .compiling,
             .warmingUp,
             .canaryTesting,
             .deleting,
             .ready,
             .corrupt,
             .failed:
            return false
        }
    }
}
