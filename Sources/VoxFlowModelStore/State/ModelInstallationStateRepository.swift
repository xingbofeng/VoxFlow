import Foundation

public protocol ModelInstallationStateStoring: Sendable {
    func state(for key: ModelInstallKey) throws -> ModelInstallationState
    func save(_ state: ModelInstallationState, for key: ModelInstallKey) throws
    func removeState(for key: ModelInstallKey) throws
}

public final class FileModelInstallationStateRepository: ModelInstallationStateStoring, @unchecked Sendable {
    private let fileURL: URL
    private let fileManager: FileManager
    private let lock = NSLock()

    public init(
        fileURL: URL,
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    public func state(for key: ModelInstallKey) throws -> ModelInstallationState {
        try lock.withLock {
            try recordsByKey()[key] ?? .notInstalled
        }
    }

    public func save(_ state: ModelInstallationState, for key: ModelInstallKey) throws {
        try lock.withLock {
            var records = try recordsByKey()
            records[key] = state
            try write(records)
        }
    }

    public func removeState(for key: ModelInstallKey) throws {
        try lock.withLock {
            var records = try recordsByKey()
            records.removeValue(forKey: key)
            try write(records)
        }
    }

    private func recordsByKey() throws -> [ModelInstallKey: ModelInstallationState] {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return [:]
        }

        let data = try Data(contentsOf: fileURL)
        let records = try JSONDecoder().decode([ModelInstallationStateRecord].self, from: data)
        return Dictionary(uniqueKeysWithValues: records.map { ($0.key, $0.state) })
    }

    private func write(_ records: [ModelInstallKey: ModelInstallationState]) throws {
        let parent = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)

        let payload = records
            .map { ModelInstallationStateRecord(key: $0.key, state: $0.value) }
            .sorted { lhs, rhs in
                if lhs.key.modelID.rawValue == rhs.key.modelID.rawValue {
                    return lhs.key.version < rhs.key.version
                }
                return lhs.key.modelID.rawValue < rhs.key.modelID.rawValue
            }
        let data = try JSONEncoder().encode(payload)
        try data.write(to: fileURL, options: [.atomic])
    }
}

private struct ModelInstallationStateRecord: Codable {
    let key: ModelInstallKey
    let state: ModelInstallationState
}
