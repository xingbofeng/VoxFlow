import Foundation
import VoxFlowModelStore

public enum Qwen3ModelVariant: String, Sendable {
    case qwen06CoreMLInt8
    case qwen17MLX4Bit
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
            && (!requiresCoreMLEmbeddingValidation
                || Self.hasValidEmbeddingFile(at: directory, fileManager: fileManager))
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
        } && hasValidEmbeddingFile(at: directory, fileManager: fileManager)
    }

    public static let requiredLoadablePaths = [
        "qwen3_asr_audio_encoder_v2.mlmodelc/coremldata.bin",
        "qwen3_asr_decoder_stateful.mlmodelc/coremldata.bin",
        "qwen3_asr_embeddings.bin",
        "vocab.json",
    ]

    public static let supportedLoadablePathSets = [
        requiredLoadablePaths,
        [
            "qwen3_asr_audio_encoder_v2.mlpackage/Manifest.json",
            "qwen3_asr_decoder_stateful.mlpackage/Manifest.json",
            "qwen3_asr_embeddings.bin",
            "vocab.json",
        ],
    ]

    private var requiresCoreMLEmbeddingValidation: Bool {
        requiredLocalPaths.contains("qwen3_asr_embeddings.bin")
    }

    private static func hasValidEmbeddingFile(
        at directory: URL,
        fileManager: FileManager
    ) -> Bool {
        let url = directory.appendingPathComponent("qwen3_asr_embeddings.bin")
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let fileSize = (attributes[.size] as? NSNumber)?.uint64Value,
              fileSize == 8 + UInt64(151_936) * 1_024 * 2,
              let handle = try? FileHandle(forReadingFrom: url) else {
            return false
        }
        defer { try? handle.close() }
        guard let header = try? handle.read(upToCount: 8), header.count == 8 else {
            return false
        }
        let vocab = header.withUnsafeBytes {
            UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: 0, as: UInt32.self))
        }
        let hidden = header.withUnsafeBytes {
            UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: 4, as: UInt32.self))
        }
        return vocab == 151_936 && hidden == 1_024
    }
}

public enum Qwen3ManifestCatalog {
    public static func manifest(for variant: Qwen3ModelVariant) -> Qwen3ModelManifest {
        switch variant {
        case .qwen06CoreMLInt8:
            return Qwen3ModelManifest(
                repository: "FluidInference/qwen3-asr-0.6b-coreml",
                localDirectoryName: "qwen3-asr-0.6b-coreml-int8",
                files: [
                    .init(remotePath: "int8/metadata.json", localPath: "metadata.json"),
                    .init(remotePath: "int8/vocab.json", localPath: "vocab.json"),
                    .init(remotePath: "int8/qwen3_asr_embeddings.bin", localPath: "qwen3_asr_embeddings.bin"),
                    .init(remotePath: "int8/qwen3_asr_audio_encoder_v2.mlmodelc/analytics/coremldata.bin", localPath: "qwen3_asr_audio_encoder_v2.mlmodelc/analytics/coremldata.bin"),
                    .init(remotePath: "int8/qwen3_asr_audio_encoder_v2.mlmodelc/coremldata.bin", localPath: "qwen3_asr_audio_encoder_v2.mlmodelc/coremldata.bin"),
                    .init(remotePath: "int8/qwen3_asr_audio_encoder_v2.mlmodelc/metadata.json", localPath: "qwen3_asr_audio_encoder_v2.mlmodelc/metadata.json"),
                    .init(remotePath: "int8/qwen3_asr_audio_encoder_v2.mlmodelc/model.mil", localPath: "qwen3_asr_audio_encoder_v2.mlmodelc/model.mil"),
                    .init(remotePath: "int8/qwen3_asr_audio_encoder_v2.mlmodelc/weights/weight.bin", localPath: "qwen3_asr_audio_encoder_v2.mlmodelc/weights/weight.bin"),
                    .init(remotePath: "int8/qwen3_asr_decoder_stateful.mlmodelc/analytics/coremldata.bin", localPath: "qwen3_asr_decoder_stateful.mlmodelc/analytics/coremldata.bin"),
                    .init(remotePath: "int8/qwen3_asr_decoder_stateful.mlmodelc/coremldata.bin", localPath: "qwen3_asr_decoder_stateful.mlmodelc/coremldata.bin"),
                    .init(remotePath: "int8/qwen3_asr_decoder_stateful.mlmodelc/metadata.json", localPath: "qwen3_asr_decoder_stateful.mlmodelc/metadata.json"),
                    .init(remotePath: "int8/qwen3_asr_decoder_stateful.mlmodelc/model.mil", localPath: "qwen3_asr_decoder_stateful.mlmodelc/model.mil"),
                    .init(remotePath: "int8/qwen3_asr_decoder_stateful.mlmodelc/weights/weight.bin", localPath: "qwen3_asr_decoder_stateful.mlmodelc/weights/weight.bin"),
                ],
                requiredLocalPaths: Qwen3ModelManifest.requiredLoadablePaths
            )
        case .qwen17MLX4Bit:
            return Qwen3ModelManifest(
                repository: "mlx-community/Qwen3-ASR-1.7B-4bit",
                localDirectoryName: "qwen3-asr-1.7b-mlx-4bit",
                files: [
                    .init(remotePath: "chat_template.json", localPath: "chat_template.json"),
                    .init(remotePath: "config.json", localPath: "config.json"),
                    .init(remotePath: "generation_config.json", localPath: "generation_config.json"),
                    .init(remotePath: "merges.txt", localPath: "merges.txt"),
                    .init(remotePath: "model.safetensors", localPath: "model.safetensors"),
                    .init(remotePath: "model.safetensors.index.json", localPath: "model.safetensors.index.json"),
                    .init(remotePath: "preprocessor_config.json", localPath: "preprocessor_config.json"),
                    .init(remotePath: "tokenizer_config.json", localPath: "tokenizer_config.json"),
                    .init(remotePath: "vocab.json", localPath: "vocab.json"),
                ],
                requiredLocalPaths: [
                    "chat_template.json",
                    "config.json",
                    "generation_config.json",
                    "merges.txt",
                    "model.safetensors",
                    "model.safetensors.index.json",
                    "preprocessor_config.json",
                    "tokenizer_config.json",
                    "vocab.json",
                ]
            )
        }
    }

    public static func metadata(for manifest: Qwen3ModelManifest) throws -> Qwen3ModelStoreMetadata {
        switch manifest.localDirectoryName {
        case "qwen3-asr-0.6b-coreml-int8":
            return qwen06CoreMLInt8Metadata
        case "qwen3-asr-1.7b-mlx-4bit":
            return qwen17MLX4BitMetadata
        default:
            throw Qwen3ModelStoreManifestError.runtimeUnsupported
        }
    }

    public static let qwen06CoreMLInt8Metadata = Qwen3ModelStoreMetadata(
        modelID: ModelID(rawValue: "qwen3-asr-0.6b-coreml-int8"),
        version: "c081689ec58bcf29c2ef7c474ef78a164bda672b",
        runtimeVersion: "coreml-int8",
        supportedArchitectures: [.arm64],
        minimumOSVersion: "14.0",
        minimumMemoryBytes: 8 * 1_024 * 1_024 * 1_024,
        license: ModelLicense(
            name: "Apache-2.0",
            url: URL(string: "https://huggingface.co/FluidInference/qwen3-asr-0.6b-coreml")
        ),
        components: [
            "metadata.json": component(
                size: 1_802,
                sha256: "a039f49bd774a42f1607abf9d8951334a5e9908a01952b621bccee9d928321c9"
            ),
            "vocab.json": component(
                size: 2_776_833,
                sha256: "ca10d7e9fb3ed18575dd1e277a2579c16d108e32f27439684afa0e10b1440910"
            ),
            "qwen3_asr_embeddings.bin": component(
                size: 311_164_936,
                sha256: "dd1da448e68e0ee14a74f024ebfad964f39c9abcd30ac70632796c7ce76de873"
            ),
            "qwen3_asr_audio_encoder_v2.mlmodelc/analytics/coremldata.bin": component(
                size: 243,
                sha256: "279247406b9e8e33dc1c256d4e2b5488b9a183daf9a8314172dac9e6f64b449a"
            ),
            "qwen3_asr_audio_encoder_v2.mlmodelc/coremldata.bin": component(
                size: 385,
                sha256: "b319012fd80686a009585fc87f50d7e683bb4da8b5bd14bd506c53e54e5bfb6f"
            ),
            "qwen3_asr_audio_encoder_v2.mlmodelc/metadata.json": component(
                size: 2_088,
                sha256: "fff797c7966cefa7fa68e8400aac81acd0542ceb5cf5eef3bff8faa373cc6840"
            ),
            "qwen3_asr_audio_encoder_v2.mlmodelc/model.mil": component(
                size: 726_626,
                sha256: "15bc926f1d77c12307fc94178571b95861b385babfaea6f92e071e544abbb647"
            ),
            "qwen3_asr_audio_encoder_v2.mlmodelc/weights/weight.bin": component(
                size: 372_798_784,
                sha256: "7173c9f195f8fed12354edb5861d041f623ca6dc057dd0f4a3cb436ef38f3141"
            ),
            "qwen3_asr_decoder_stateful.mlmodelc/analytics/coremldata.bin": component(
                size: 243,
                sha256: "94f53ae20d39827cba410e845d27deaba7f9f7728d8074a26a1b5f6170405624"
            ),
            "qwen3_asr_decoder_stateful.mlmodelc/coremldata.bin": component(
                size: 2_347,
                sha256: "27ca2172ef8a63b6fc6c5105e501de16f2e2d4f4a0ddef9dd8b37cc26d5675e3"
            ),
            "qwen3_asr_decoder_stateful.mlmodelc/metadata.json": component(
                size: 18_844,
                sha256: "7d59f653586c9ea3059cdb5cf40044d81fb76549a13494ddddcbcd7c251d7e57"
            ),
            "qwen3_asr_decoder_stateful.mlmodelc/model.mil": component(
                size: 939_591,
                sha256: "4a6205cfc691ded83ec354fd8dc758e3d0a8b884249158f4b1e150da91cc71e5"
            ),
            "qwen3_asr_decoder_stateful.mlmodelc/weights/weight.bin": component(
                size: 597_456_384,
                sha256: "b5bc06697cdcf6ba241feb6f67a0a0b79042c53bc9a5f81a81ae3b8e4d410b69"
            ),
        ]
    )

    public static let qwen17MLX4BitMetadata = Qwen3ModelStoreMetadata(
        modelID: ModelID(rawValue: "qwen3-asr-1.7b-mlx-4bit"),
        version: "78a389c776a5483b2d0d4ea5494e11012e0d6159",
        runtimeVersion: "mlx-4bit",
        supportedArchitectures: [.arm64],
        minimumOSVersion: "14.0",
        minimumMemoryBytes: 16 * 1_024 * 1_024 * 1_024,
        license: ModelLicense(
            name: "Apache-2.0",
            url: URL(string: "https://huggingface.co/mlx-community/Qwen3-ASR-1.7B-4bit")
        ),
        components: [
            "chat_template.json": component(
                size: 1_161,
                sha256: "75a8cfca24f00de72d796fbfed6858fc9614ef3dabd8696684cc3bc03a9c58ff"
            ),
            "config.json": component(
                size: 7_188,
                sha256: "539c6c9d482349066e2e740241e39896f3bf4de0866c245f6539c85dbb19d93c"
            ),
            "generation_config.json": component(
                size: 142,
                sha256: "1da527824d81e07118facff437e03f2e24a23311e3bdeb2368973fe77e5f275c"
            ),
            "merges.txt": component(
                size: 1_671_853,
                sha256: "8831e4f1a044471340f7c0a83d7bd71306a5b867e95fd870f74d0c5308a904d5"
            ),
            "model.safetensors": component(
                size: 1_603_081_617,
                sha256: "9848eaf7a5c1589c671b35035ac27b72e248dd0c604eacae547e7e403d29db45"
            ),
            "model.safetensors.index.json": component(
                size: 78_968,
                sha256: "2612ab715223843b3dec0742737bc85f50914ca1484ade45955f99b4e012f2bb"
            ),
            "preprocessor_config.json": component(
                size: 330,
                sha256: "45e120a4eda2c20c5d7f2ea9354e63536bf35e27aa573fb7cdf78017b378770d"
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

    static var qwen06CoreMLInt8: Qwen3ModelStoreMetadata {
        Qwen3ManifestCatalog.qwen06CoreMLInt8Metadata
    }

    static var qwen17MLX4Bit: Qwen3ModelStoreMetadata {
        Qwen3ManifestCatalog.qwen17MLX4BitMetadata
    }
}
