import Foundation

public struct ModelProviderID: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public struct ModelID: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public struct SHA256Digest: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public enum ModelComponentRequirement: String, Codable, Equatable, Sendable {
    case required
    case optional
}

public enum ModelArchitecture: String, Codable, Equatable, Sendable {
    case arm64
    case x86_64
}

public struct ModelLicense: Codable, Equatable, Sendable {
    public let name: String
    public let url: URL?

    public init(name: String, url: URL?) {
        self.name = name
        self.url = url
    }
}

public struct ModelComponentManifest: Codable, Equatable, Sendable {
    public let providerID: ModelProviderID
    public let modelID: ModelID
    public let version: String
    public let runtimeVersion: String
    public let downloadURL: URL
    public let expectedSizeBytes: Int64
    public let sha256: SHA256Digest
    public let localPath: String
    public let requirement: ModelComponentRequirement
    public let supportedArchitectures: [ModelArchitecture]
    public let minimumOSVersion: String
    public let minimumMemoryBytes: Int64
    public let license: ModelLicense

    public init(
        providerID: ModelProviderID,
        modelID: ModelID,
        version: String,
        runtimeVersion: String,
        downloadURL: URL,
        expectedSizeBytes: Int64,
        sha256: SHA256Digest,
        localPath: String,
        requirement: ModelComponentRequirement,
        supportedArchitectures: [ModelArchitecture],
        minimumOSVersion: String,
        minimumMemoryBytes: Int64,
        license: ModelLicense
    ) {
        self.providerID = providerID
        self.modelID = modelID
        self.version = version
        self.runtimeVersion = runtimeVersion
        self.downloadURL = downloadURL
        self.expectedSizeBytes = expectedSizeBytes
        self.sha256 = sha256
        self.localPath = localPath
        self.requirement = requirement
        self.supportedArchitectures = supportedArchitectures
        self.minimumOSVersion = minimumOSVersion
        self.minimumMemoryBytes = minimumMemoryBytes
        self.license = license
    }
}

public struct ModelManifest: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let components: [ModelComponentManifest]

    public init(
        schemaVersion: Int,
        components: [ModelComponentManifest]
    ) {
        self.schemaVersion = schemaVersion
        self.components = components
    }
}
