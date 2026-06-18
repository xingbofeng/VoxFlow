import CryptoKit
import Foundation

public enum ModelIntegrityIssue: Equatable, Sendable {
    case missingRequiredComponent(localPath: String)
    case sizeMismatch(localPath: String, expected: Int64, actual: Int64)
    case sha256Mismatch(localPath: String, expected: SHA256Digest, actual: SHA256Digest)
    case runtimeVersionMismatch(localPath: String, expected: String, actual: String)
    case invalidMetadata(localPath: String, field: String)
}

public struct ModelIntegrityReport: Equatable, Sendable {
    public let issues: [ModelIntegrityIssue]

    public init(issues: [ModelIntegrityIssue]) {
        self.issues = issues
    }

    public var isValid: Bool {
        issues.isEmpty
    }
}

public struct ModelIntegrityValidator {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func validate(
        manifest: ModelManifest,
        installedRoot: URL,
        runtimeVersion: String
    ) throws -> ModelIntegrityReport {
        var issues: [ModelIntegrityIssue] = []

        for component in manifest.components {
            issues.append(contentsOf: metadataIssues(for: component))

            let componentURL = installedRoot.appendingPathComponent(component.localPath)
            guard fileManager.fileExists(atPath: componentURL.path) else {
                if component.requirement == .required {
                    issues.append(.missingRequiredComponent(localPath: component.localPath))
                }
                continue
            }

            let actualSize = try fileSize(at: componentURL)
            if actualSize != component.expectedSizeBytes {
                issues.append(
                    .sizeMismatch(
                        localPath: component.localPath,
                        expected: component.expectedSizeBytes,
                        actual: actualSize
                    )
                )
            }

            let actualSHA256 = try sha256Digest(at: componentURL)
            if actualSHA256 != component.sha256 {
                issues.append(
                    .sha256Mismatch(
                        localPath: component.localPath,
                        expected: component.sha256,
                        actual: actualSHA256
                    )
                )
            }

            if component.runtimeVersion != runtimeVersion {
                issues.append(
                    .runtimeVersionMismatch(
                        localPath: component.localPath,
                        expected: component.runtimeVersion,
                        actual: runtimeVersion
                    )
                )
            }
        }

        return ModelIntegrityReport(issues: issues)
    }

    private func metadataIssues(for component: ModelComponentManifest) -> [ModelIntegrityIssue] {
        [
            (component.providerID.rawValue, "providerID"),
            (component.modelID.rawValue, "modelID"),
            (component.version, "version"),
            (component.runtimeVersion, "runtimeVersion"),
            (component.localPath, "localPath"),
            (component.license.name, "license"),
        ]
        .compactMap { value, field in
            value.isEmpty ? .invalidMetadata(localPath: component.localPath, field: field) : nil
        }
    }

    private func fileSize(at url: URL) throws -> Int64 {
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        let size = attributes[.size] as? NSNumber
        return size?.int64Value ?? 0
    }

    private func sha256Digest(at url: URL) throws -> SHA256Digest {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var hasher = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
            hasher.update(data: data)
        }

        let hex = hasher.finalize()
            .map { String(format: "%02x", $0) }
            .joined()
        return SHA256Digest(rawValue: hex)
    }
}
