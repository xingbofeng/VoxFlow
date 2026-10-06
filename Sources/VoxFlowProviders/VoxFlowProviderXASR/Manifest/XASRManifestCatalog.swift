import Foundation
import VoxFlowModelStore

public enum XASRManifestCatalog {
    public static let pinnedRevision = "689ff18c584d29910da37b6fe904db0c1489c9d1"
    public static let modelID = ModelID(rawValue: "xasr-zh-en-480ms")
    public static let runtimeVersion = "sherpa-onnx-1.13.3-xasr"
    public static let supportedArchitectures: [ModelArchitecture] = [.arm64]
    public static let minimumOSVersion = "15.0"
    public static let minimumMemoryBytes: Int64 = 8 * 1_024 * 1_024 * 1_024
    public static var modelInstallKey: ModelInstallKey {
        ModelInstallKey(modelID: modelID, version: pinnedRevision)
    }
    public static let license = ModelLicense(
        name: "Apache-2.0",
        url: URL(string: "https://huggingface.co/GilgameshWind/X-ASR-zh-en/blob/\(pinnedRevision)/README.md")
    )

    /// M0 下载后逐文件验证的精确大小与 SHA256。权重不打包进 App。
    private static let assets: [(path: String, bytes: Int64, sha256: String)] = [
        (XASRModel.encoderPath, 592_968_361, "0c3454033d249081df124ddcd7adaf3deca07d0b999b26f2ee5d2475d37abc74"),
        (XASRModel.decoderPath, 11_309_084, "3658368d274a5d5fd39a7ac20c46bed0ad9cfea1f0feddef30d5d89797c1f499"),
        (XASRModel.joinerPath, 10_260_467, "03781c98165a2385024c9cecdd2b6b13310d81db23a62c7da420782c2915cf81"),
        (XASRModel.tokensPath, 58_806, "b818a60878b9aae978cbb8ad594acbd403d76d1af2e31ef4197c84e2dbdba27c"),
    ]

    public static var expectedDownloadBytes: Int64 {
        assets.reduce(Int64(0)) { $0 + $1.bytes }
    }

    public static func modelStoreManifest() throws -> ModelManifest {
        ModelManifest(schemaVersion: 1, components: assets.map { asset in
            ModelComponentManifest(
                providerID: ModelProviderID(rawValue: XASRProviderDescriptor.providerID.rawValue),
                modelID: modelID,
                version: pinnedRevision,
                runtimeVersion: runtimeVersion,
                downloadURL: URL(string: "https://huggingface.co/GilgameshWind/X-ASR-zh-en/resolve/\(pinnedRevision)/deployment/models/chunk-480ms-model/\(asset.path)")!,
                expectedSizeBytes: asset.bytes,
                sha256: SHA256Digest(rawValue: asset.sha256),
                localPath: asset.path,
                requirement: .required,
                supportedArchitectures: supportedArchitectures,
                minimumOSVersion: minimumOSVersion,
                minimumMemoryBytes: minimumMemoryBytes,
                license: license
            )
        })
    }
}
