import Foundation

public enum ModelInstallError: LocalizedError, Equatable, Sendable {
    case emptyManifest
    case integrityFailed(ModelIntegrityReport)

    public var errorDescription: String? {
        switch self {
        case .emptyManifest:
            return "模型清单是空的，无法安装。请更新模型清单后重试。"
        case .integrityFailed(let report):
            let details = report.issues
                .prefix(3)
                .map(\.localizedSummary)
                .joined(separator: "；")
            if details.isEmpty {
                return "模型文件可能已损坏，校验没有通过。请点“清理模型”后重新下载。"
            }
            return "模型文件可能已损坏，校验没有通过。请点“清理模型”后重新下载。问题：\(details)"
        }
    }
}

public struct ModelInstallKey: Codable, Hashable, Sendable {
    public let modelID: ModelID
    public let version: String

    public init(modelID: ModelID, version: String) {
        self.modelID = modelID
        self.version = version
    }
}

public struct ModelAtomicInstaller {
    private let fileManager: FileManager
    private let validator: ModelIntegrityValidator

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.validator = ModelIntegrityValidator(fileManager: fileManager)
    }

    public func install(
        manifest: ModelManifest,
        stagingRoot: URL,
        storeRoot: URL,
        runtimeVersion: String
    ) throws -> ModelInstallation {
        guard let firstComponent = manifest.components.first else {
            throw ModelInstallError.emptyManifest
        }

        let report = try validator.validate(
            manifest: manifest,
            installedRoot: stagingRoot,
            runtimeVersion: runtimeVersion
        )
        guard report.isValid else {
            throw ModelInstallError.integrityFailed(report)
        }

        let destinationRoot = storeRoot
            .appendingPathComponent(firstComponent.modelID.rawValue, isDirectory: true)
            .appendingPathComponent(firstComponent.version, isDirectory: true)
        try moveValidatedStaging(stagingRoot, to: destinationRoot)

        return ModelInstallation(
            modelID: firstComponent.modelID,
            version: firstComponent.version,
            installedRoot: destinationRoot
        )
    }

    @discardableResult
    public func cleanupExpiredStagingDirectories(
        in root: URL,
        olderThan maxAge: TimeInterval,
        referenceDate: Date = Date()
    ) throws -> [URL] {
        let contents = try fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        var removed: [URL] = []
        for url in contents where url.lastPathComponent.hasSuffix(".partial") {
            let values = try url.resourceValues(forKeys: [.contentModificationDateKey, .isDirectoryKey])
            guard values.isDirectory == true,
                  let modified = values.contentModificationDate,
                  referenceDate.timeIntervalSince(modified) > maxAge else {
                continue
            }
            try fileManager.removeItem(at: url)
            removed.append(url)
        }

        return removed.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func moveValidatedStaging(_ stagingRoot: URL, to destinationRoot: URL) throws {
        let parent = destinationRoot.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)

        guard fileManager.fileExists(atPath: destinationRoot.path) else {
            try fileManager.moveItem(at: stagingRoot, to: destinationRoot)
            return
        }

        let backupRoot = parent.appendingPathComponent(
            ".\(destinationRoot.lastPathComponent).backup.\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.moveItem(at: destinationRoot, to: backupRoot)
        do {
            try fileManager.moveItem(at: stagingRoot, to: destinationRoot)
            try? fileManager.removeItem(at: backupRoot)
        } catch {
            try? fileManager.removeItem(at: destinationRoot)
            try? fileManager.moveItem(at: backupRoot, to: destinationRoot)
            throw error
        }
    }
}

private extension ModelIntegrityIssue {
    var localizedSummary: String {
        switch self {
        case .missingRequiredComponent(let localPath):
            return "\(localPath) 缺失"
        case .sizeMismatch(let localPath, let expected, let actual):
            return "\(localPath) 大小不一致（需要 \(Self.formatBytes(expected))，实际 \(Self.formatBytes(actual))）"
        case .sha256Mismatch(let localPath, _, _):
            return "\(localPath) SHA256 校验不一致"
        case .runtimeVersionMismatch(let localPath, let expected, let actual):
            return "\(localPath) 运行时版本不匹配（需要 \(expected)，当前 \(actual)）"
        case .invalidMetadata(let localPath, let field):
            return "\(localPath) 元数据字段 \(field) 无效"
        }
    }

    private static func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

public actor ModelInstallCoordinator {
    private var inFlight: [ModelInstallKey: Task<ModelInstallation, Error>] = [:]

    public init() {}

    public func install(
        for key: ModelInstallKey,
        operation: @Sendable @escaping () async throws -> ModelInstallation
    ) async throws -> ModelInstallation {
        if let existing = inFlight[key] {
            return try await existing.value
        }

        let task = Task {
            try await operation()
        }
        inFlight[key] = task
        defer {
            inFlight[key] = nil
        }
        return try await task.value
    }
}
