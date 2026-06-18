import CryptoKit
import Foundation

public enum ModelContentAddressedStoreError: Error, Equatable, Sendable {
    case sha256Mismatch(expected: SHA256Digest, actual: SHA256Digest)
    case missingBlob(SHA256Digest)
}

public struct ModelContentAddressedStore {
    private let root: URL
    private let fileManager: FileManager

    public init(
        root: URL,
        fileManager: FileManager = .default
    ) {
        self.root = root
        self.fileManager = fileManager
    }

    public func storeBlob(
        from sourceURL: URL,
        expectedSHA256: SHA256Digest
    ) throws -> URL {
        let actualSHA256 = try sha256Digest(at: sourceURL)
        guard actualSHA256 == expectedSHA256 else {
            throw ModelContentAddressedStoreError.sha256Mismatch(
                expected: expectedSHA256,
                actual: actualSHA256
            )
        }

        let destinationURL = blobURL(for: expectedSHA256)
        try fileManager.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if !fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
        }
        return destinationURL
    }

    public func linkBlob(
        _ digest: SHA256Digest,
        to destinationURL: URL
    ) throws {
        let sourceURL = blobURL(for: digest)
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            throw ModelContentAddressedStoreError.missingBlob(digest)
        }

        try fileManager.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.linkItem(at: sourceURL, to: destinationURL)
    }

    public func deleteReference(at referenceURL: URL) throws {
        let digest = try sha256Digest(at: referenceURL)
        let sourceURL = blobURL(for: digest)

        try fileManager.removeItem(at: referenceURL)
        if fileManager.fileExists(atPath: sourceURL.path),
           try referenceCount(for: digest) <= 1 {
            try fileManager.removeItem(at: sourceURL)
        }
    }

    public func referenceCount(for digest: SHA256Digest) throws -> Int {
        let sourceURL = blobURL(for: digest)
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            throw ModelContentAddressedStoreError.missingBlob(digest)
        }

        let attributes = try fileManager.attributesOfItem(atPath: sourceURL.path)
        let count = attributes[.referenceCount] as? NSNumber
        return count?.intValue ?? 1
    }

    public func blobURL(for digest: SHA256Digest) -> URL {
        root
            .appendingPathComponent("blobs", isDirectory: true)
            .appendingPathComponent(digest.rawValue)
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
