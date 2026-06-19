import Foundation
import VoxFlowModelStore

public enum Qwen3ModelVariant: String, Sendable {
    case qwen06SpeechSwift4Bit
    case qwen17SpeechSwift8Bit
}

public struct Qwen3ModelStoreComponentMetadata: Equatable, Sendable {
    public let expectedSizeBytes: Int64
    public let sha256: SHA256Digest

    public init(expectedSizeBytes: Int64, sha256: SHA256Digest) {
        self.expectedSizeBytes = expectedSizeBytes
        self.sha256 = sha256
    }
}

public struct Qwen3ModelStoreMetadata: Equatable, Sendable {
    public let modelID: ModelID
    public let version: String
    public let runtimeVersion: String
    public let supportedArchitectures: [ModelArchitecture]
    public let minimumOSVersion: String
    public let minimumMemoryBytes: Int64
    public let license: ModelLicense
    public let components: [String: Qwen3ModelStoreComponentMetadata]

    public init(
        modelID: ModelID,
        version: String,
        runtimeVersion: String,
        supportedArchitectures: [ModelArchitecture],
        minimumOSVersion: String,
        minimumMemoryBytes: Int64,
        license: ModelLicense,
        components: [String: Qwen3ModelStoreComponentMetadata]
    ) {
        self.modelID = modelID
        self.version = version
        self.runtimeVersion = runtimeVersion
        self.supportedArchitectures = supportedArchitectures
        self.minimumOSVersion = minimumOSVersion
        self.minimumMemoryBytes = minimumMemoryBytes
        self.license = license
        self.components = components
    }
}

public enum Qwen3ModelStoreManifestError: Error, Equatable, Sendable {
    case runtimeUnsupported
    case missingIntegrityMetadata(localPath: String)
}

public struct Qwen3ModelManifest: Equatable, Sendable {
    public struct File: Equatable, Sendable {
        public let repository: String?
        public let remotePath: String
        public let localPath: String

        public init(repository: String? = nil, remotePath: String, localPath: String) {
            self.repository = repository
            self.remotePath = remotePath
            self.localPath = localPath
        }
    }

    public let repository: String
    public let localDirectoryName: String
    public let files: [File]
    public let requiredLocalPaths: [String]

    public init(
        repository: String,
        localDirectoryName: String,
        files: [File],
        requiredLocalPaths: [String]
    ) {
        self.repository = repository
        self.localDirectoryName = localDirectoryName
        self.files = files
        self.requiredLocalPaths = requiredLocalPaths
    }

    public var fileCount: Int { files.count }

    public func remoteURL(for file: File) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "huggingface.co"
        components.path = "/\(file.repository ?? repository)/resolve/main/\(file.remotePath)"
        return components.url!
    }

    public func modelStoreManifest(metadata: Qwen3ModelStoreMetadata) throws -> ModelManifest {
        guard !files.isEmpty else {
            throw Qwen3ModelStoreManifestError.runtimeUnsupported
        }

        let components = try files.map { file -> ModelComponentManifest in
            guard let componentMetadata = metadata.components[file.localPath] else {
                throw Qwen3ModelStoreManifestError.missingIntegrityMetadata(localPath: file.localPath)
            }

            return ModelComponentManifest(
                providerID: ModelProviderID(rawValue: "qwen3_asr"),
                modelID: metadata.modelID,
                version: metadata.version,
                runtimeVersion: metadata.runtimeVersion,
                downloadURL: remoteURL(for: file),
                expectedSizeBytes: componentMetadata.expectedSizeBytes,
                sha256: componentMetadata.sha256,
                localPath: file.localPath,
                requirement: .required,
                supportedArchitectures: metadata.supportedArchitectures,
                minimumOSVersion: metadata.minimumOSVersion,
                minimumMemoryBytes: metadata.minimumMemoryBytes,
                license: metadata.license
            )
        }

        return ModelManifest(schemaVersion: 1, components: components)
    }

    public func modelsExist(at directory: URL, fileManager: FileManager = .default) -> Bool {
        missingRequiredLocalPaths(at: directory, fileManager: fileManager).isEmpty
    }

    public func missingRequiredLocalPaths(
        at directory: URL,
        fileManager: FileManager = .default
    ) -> [String] {
        requiredLocalPaths.filter { path in
            !fileManager.fileExists(atPath: directory.appendingPathComponent(path).path)
        }
    }

    public static func missingRequiredLocalPaths(
        at directory: URL,
        fileManager: FileManager = .default
    ) -> [String] {
        supportedLoadablePathSets
            .map { paths in
                paths.filter { path in
                    !fileManager.fileExists(atPath: directory.appendingPathComponent(path).path)
                }
            }
            .min { lhs, rhs in lhs.count < rhs.count } ?? []
    }

    public static func supportedModelExists(
        at directory: URL,
        fileManager: FileManager = .default
    ) -> Bool {
        supportedLoadablePathSets.contains { paths in
            paths.allSatisfy { path in
                fileManager.fileExists(atPath: directory.appendingPathComponent(path).path)
            }
        }
    }

    public static let requiredLoadablePaths = [
        "config.json",
        "merges.txt",
        "model.safetensors",
        "model.safetensors.index.json",
        "tokenizer_config.json",
        "vocab.json",
    ]

    public static let supportedLoadablePathSets = [
        requiredLoadablePaths,
    ]
}

public enum Qwen3ManifestCatalog {
    public static func manifest(for variant: Qwen3ModelVariant) -> Qwen3ModelManifest {
        switch variant {
        case .qwen06SpeechSwift4Bit:
            return Qwen3ModelManifest(
                repository: "aufklarer/Qwen3-ASR-0.6B-MLX-4bit",
                localDirectoryName: "qwen3-asr-0.6b-mlx-4bit",
                files: [
                    .init(remotePath: "config.json", localPath: "config.json"),
                    .init(remotePath: "merges.txt", localPath: "merges.txt"),
                    .init(remotePath: "model.safetensors", localPath: "model.safetensors"),
                    .init(remotePath: "model.safetensors.index.json", localPath: "model.safetensors.index.json"),
                    .init(remotePath: "tokenizer_config.json", localPath: "tokenizer_config.json"),
                    .init(remotePath: "vocab.json", localPath: "vocab.json"),
                ],
                requiredLocalPaths: Qwen3ModelManifest.requiredLoadablePaths
            )
        case .qwen17SpeechSwift8Bit:
            return Qwen3ModelManifest(
                repository: "aufklarer/Qwen3-ASR-1.7B-MLX-8bit",
                localDirectoryName: "qwen3-asr-1.7b-mlx-8bit",
                files: [
                    .init(remotePath: "config.json", localPath: "config.json"),
                    .init(remotePath: "merges.txt", localPath: "merges.txt"),
                    .init(remotePath: "model.safetensors", localPath: "model.safetensors"),
                    .init(remotePath: "model.safetensors.index.json", localPath: "model.safetensors.index.json"),
                    .init(remotePath: "tokenizer_config.json", localPath: "tokenizer_config.json"),
                    .init(remotePath: "vocab.json", localPath: "vocab.json"),
                ],
                requiredLocalPaths: [
                    "config.json",
                    "merges.txt",
                    "model.safetensors",
                    "model.safetensors.index.json",
                    "tokenizer_config.json",
                    "vocab.json",
                ]
            )
        }
    }

    public static func metadata(for manifest: Qwen3ModelManifest) throws -> Qwen3ModelStoreMetadata {
        switch manifest.localDirectoryName {
        case "qwen3-asr-0.6b-mlx-4bit":
            return qwen06SpeechSwift4BitMetadata
        case "qwen3-asr-1.7b-mlx-8bit":
            return qwen17SpeechSwift8BitMetadata
        default:
            throw Qwen3ModelStoreManifestError.runtimeUnsupported
        }
    }

    public static let qwen06SpeechSwift4BitMetadata = Qwen3ModelStoreMetadata(
        modelID: ModelID(rawValue: "qwen3-asr-0.6b-mlx-4bit"),
        version: "bc441bd1e4295c1f42d9879f056049a925b6e013",
        runtimeVersion: "mlx-4bit",
        supportedArchitectures: [.arm64],
        minimumOSVersion: "15.0",
        minimumMemoryBytes: 8 * 1_024 * 1_024 * 1_024,
        license: ModelLicense(
            name: "Apache-2.0",
            url: URL(string: "https://huggingface.co/aufklarer/Qwen3-ASR-0.6B-MLX-4bit")
        ),
        components: [
            "config.json": component(
                size: 7_187,
                sha256: "923618cf5ca452fda0253a6be5c1a17f94a2e4851d3b98beb45848565587bd72"
            ),
            "merges.txt": component(
                size: 1_671_853,
                sha256: "8831e4f1a044471340f7c0a83d7bd71306a5b867e95fd870f74d0c5308a904d5"
            ),
            "model.safetensors": component(
                size: 708_236_945,
                sha256: "70c7e67e588062adce4f10796e47ad42ead51c6671eda61a0987eae38ca95ddf"
            ),
            "model.safetensors.index.json": component(
                size: 71_814,
                sha256: "e3bb80ef0fd42a5be07b04e90c97d60460bbde8af3531e0bfe9100a61404d81a"
            ),
            "tokenizer_config.json": component(
                size: 12_487,
                sha256: "4942d005604266809309cabc9f4e9cb89ce855d59b14681fdc0e1cc62ea26c4c"
            ),
            "vocab.json": component(
                size: 2_776_833,
                sha256: "ca10d7e9fb3ed18575dd1e277a2579c16d108e32f27439684afa0e10b1440910"
            ),
        ]
    )

    public static let qwen17SpeechSwift8BitMetadata = Qwen3ModelStoreMetadata(
        modelID: ModelID(rawValue: "qwen3-asr-1.7b-mlx-8bit"),
        version: "e5450a26d1fd417c45fc9c405651ddc3180a27a6",
        runtimeVersion: "mlx-8bit",
        supportedArchitectures: [.arm64],
        minimumOSVersion: "15.0",
        minimumMemoryBytes: 16 * 1_024 * 1_024 * 1_024,
        license: ModelLicense(
            name: "Apache-2.0",
            url: URL(string: "https://huggingface.co/aufklarer/Qwen3-ASR-1.7B-MLX-8bit")
        ),
        components: [
            "config.json": component(
                size: 7_188,
                sha256: "1b76b3b6c655fc54595da025f7a96474ad9fa86363303fbdd61a7d8483ccfaf7"
            ),
            "merges.txt": component(
                size: 1_671_853,
                sha256: "8831e4f1a044471340f7c0a83d7bd71306a5b867e95fd870f74d0c5308a904d5"
            ),
            "model.safetensors": component(
                size: 2_463_307_541,
                sha256: "bf304b009cc7eca79283056f787b44c952d24ac22cec787b39732bba3c23c13c"
            ),
            "model.safetensors.index.json": component(
                size: 78_968,
                sha256: "0a5d0ec11188602242ff81a9969883d0fdeb98cd5d85cd1413089d897c201af5"
            ),
            "tokenizer_config.json": component(
                size: 12_487,
                sha256: "4942d005604266809309cabc9f4e9cb89ce855d59b14681fdc0e1cc62ea26c4c"
            ),
            "vocab.json": component(
                size: 2_776_833,
                sha256: "ca10d7e9fb3ed18575dd1e277a2579c16d108e32f27439684afa0e10b1440910"
            ),
        ]
    )

    private static func component(
        size: Int64,
        sha256: String
    ) -> Qwen3ModelStoreComponentMetadata {
        Qwen3ModelStoreComponentMetadata(
            expectedSizeBytes: size,
            sha256: SHA256Digest(rawValue: sha256)
        )
    }
}

public extension Qwen3ModelStoreMetadata {
    static func metadata(for manifest: Qwen3ModelManifest) throws -> Qwen3ModelStoreMetadata {
        try Qwen3ManifestCatalog.metadata(for: manifest)
    }

    static var qwen06SpeechSwift4Bit: Qwen3ModelStoreMetadata {
        Qwen3ManifestCatalog.qwen06SpeechSwift4BitMetadata
    }

    static var qwen17SpeechSwift8Bit: Qwen3ModelStoreMetadata {
        Qwen3ManifestCatalog.qwen17SpeechSwift8BitMetadata
    }
}
