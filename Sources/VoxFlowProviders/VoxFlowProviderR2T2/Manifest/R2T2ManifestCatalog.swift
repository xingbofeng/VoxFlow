import Foundation
import VoxFlowModelStore

/// R2T2 模型清单。
///
/// 与 Qwen3 的清单相比，这里**必须**显式固定 `revision`：上游 `Qwen3ModelManifest.remoteURL`
/// 走的是 `resolve/main`，那对 R2T2 是不可接受的——模型必须可复现、不可静默跟随分支。
public struct R2T2ModelManifest: Equatable, Sendable {
    public struct File: Equatable, Sendable {
        public let remotePath: String
        public let localPath: String

        public init(remotePath: String, localPath: String) {
            self.remotePath = remotePath
            self.localPath = localPath
        }
    }

    public let repository: String
    public let revision: String
    public let localDirectoryName: String
    public let files: [File]
    public let requiredLocalPaths: [String]

    public init(
        repository: String,
        revision: String,
        localDirectoryName: String,
        files: [File],
        requiredLocalPaths: [String]
    ) {
        self.repository = repository
        self.revision = revision
        self.localDirectoryName = localDirectoryName
        self.files = files
        self.requiredLocalPaths = requiredLocalPaths
    }

    public func remoteURL(for file: File) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "huggingface.co"
        components.path = "/\(repository)/resolve/\(revision)/\(file.remotePath)"
        return components.url!
    }

    public func modelStoreManifest(metadata: R2T2ModelStoreMetadata) throws -> ModelManifest {
        let components = try files.map { file -> ModelComponentManifest in
            guard let integrity = metadata.components[file.localPath] else {
                throw R2T2ModelStoreManifestError.missingIntegrityMetadata(localPath: file.localPath)
            }
            return ModelComponentManifest(
                providerID: ModelProviderID(rawValue: "confucius4_r2t2"),
                modelID: metadata.modelID,
                version: metadata.version,
                runtimeVersion: metadata.runtimeVersion,
                downloadURL: remoteURL(for: file),
                expectedSizeBytes: integrity.expectedSizeBytes,
                sha256: integrity.sha256,
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
}

public enum R2T2ModelStoreManifestError: Error, Equatable, Sendable {
    case missingIntegrityMetadata(localPath: String)
}

public struct R2T2ModelStoreComponentMetadata: Equatable, Sendable {
    public let expectedSizeBytes: Int64
    public let sha256: SHA256Digest

    public init(expectedSizeBytes: Int64, sha256: SHA256Digest) {
        self.expectedSizeBytes = expectedSizeBytes
        self.sha256 = sha256
    }
}

public struct R2T2ModelStoreMetadata: Equatable, Sendable {
    public let modelID: ModelID
    public let version: String
    public let runtimeVersion: String
    public let supportedArchitectures: [ModelArchitecture]
    public let minimumOSVersion: String
    public let minimumMemoryBytes: Int64
    public let license: ModelLicense
    public let components: [String: R2T2ModelStoreComponentMetadata]

    public init(
        modelID: ModelID,
        version: String,
        runtimeVersion: String,
        supportedArchitectures: [ModelArchitecture],
        minimumOSVersion: String,
        minimumMemoryBytes: Int64,
        license: ModelLicense,
        components: [String: R2T2ModelStoreComponentMetadata]
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

public enum R2T2ManifestCatalog {
    /// 固定 revision；升级模型必须显式改这里并重新核对全部 hash。
    public static let pinnedRevision = "2d6d997c3e09c65a65b1b2576b6b9b7728df8eab"

    public static let manifest = R2T2ModelManifest(
        repository: "mlx-community/Confucius4-R2T2-8bit",
        revision: pinnedRevision,
        localDirectoryName: "confucius4-r2t2-8bit",
        files: [
            .init(remotePath: "LICENSE", localPath: "LICENSE"),
            .init(remotePath: "MODEL_LICENSE_zh", localPath: "MODEL_LICENSE_zh"),
            .init(remotePath: "NOTICE", localPath: "NOTICE"),
            .init(remotePath: "config.json", localPath: "config.json"),
            .init(remotePath: "merges.txt", localPath: "merges.txt"),
            .init(remotePath: "model.safetensors", localPath: "model.safetensors"),
            .init(
                remotePath: "model.safetensors.index.json",
                localPath: "model.safetensors.index.json"
            ),
            .init(remotePath: "tokenizer.json", localPath: "tokenizer.json"),
            .init(remotePath: "tokenizer_config.json", localPath: "tokenizer_config.json"),
            .init(remotePath: "vocab.json", localPath: "vocab.json"),
        ],
        requiredLocalPaths: [
            "LICENSE",
            "MODEL_LICENSE_zh",
            "NOTICE",
            "config.json",
            "merges.txt",
            "model.safetensors",
            "model.safetensors.index.json",
            "tokenizer.json",
            "tokenizer_config.json",
            "vocab.json",
        ]
    )

    public static let metadata = R2T2ModelStoreMetadata(
        modelID: ModelID(rawValue: "confucius4-r2t2-8bit"),
        version: pinnedRevision,
        runtimeVersion: "mlx-8bit-r2t2",
        supportedArchitectures: [.arm64],
        minimumOSVersion: "15.0",
        minimumMemoryBytes: 16 * 1_024 * 1_024 * 1_024,
        license: ModelLicense(
            name: "Netease Youdao Model Use License",
            url: URL(string: "https://huggingface.co/mlx-community/Confucius4-R2T2-8bit")
        ),
        components: [
            // 权重许可与归属说明随模型一起安装：App 不打包权重，用户必须在本地能看到它适用的条款。
            "LICENSE": component(
                size: 11_071,
                sha256: "4d9321cdad58182faa878b015de7d60069881614ddd7571de70f751a9b8e3811"
            ),
            "MODEL_LICENSE_zh": component(
                size: 7_733,
                sha256: "18b438311ebb842c15a7c91d9dbb59034efdaf6fff0d105031ef7baf5eeed275"
            ),
            "NOTICE": component(
                size: 847,
                sha256: "473880a027d736ca2c9efb3da01cfd30b745d8259e0666b3dea946d4be4b58ef"
            ),
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
                sha256: "49b41186fbd139d0c9b3ec50f31834e47b93a6617c9271cb7c28793822ac6a98"
            ),
            "model.safetensors.index.json": component(
                size: 78_928,
                sha256: "b62daee0e37a7bedb8675f69c733eef18a398235ea513f0999f3805d5ac4dedf"
            ),
            "tokenizer.json": component(
                size: 11_429_499,
                sha256: "0499602714160467f2d68b910651d6216020689f1e016be87a2d0019ee3baeab"
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

    /// 安装键：下载与安装状态查询共用，避免两处各自拼装 modelID/version。
    public static var modelInstallKey: ModelInstallKey {
        ModelInstallKey(modelID: metadata.modelID, version: metadata.version)
    }

    /// 全部组件大小之和，用于设置页展示"约 X GB"。
    public static var expectedDownloadBytes: Int64 {
        metadata.components.values.reduce(Int64(0)) { $0 + $1.expectedSizeBytes }
    }

    public static func modelStoreManifest() throws -> ModelManifest {
        try manifest.modelStoreManifest(metadata: metadata)
    }

    private static func component(size: Int64, sha256: String) -> R2T2ModelStoreComponentMetadata {
        R2T2ModelStoreComponentMetadata(
            expectedSizeBytes: size,
            sha256: SHA256Digest(rawValue: sha256)
        )
    }
}
