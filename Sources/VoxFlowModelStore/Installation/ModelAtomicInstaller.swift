import Foundation

public enum ModelInstallError: Error, Equatable, Sendable {
    case emptyManifest
    case integrityFailed(ModelIntegrityReport)
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
