import Foundation
import VoxFlowModelStore

/// FireRedASR2-AED 的 ModelStore 清单。
///
/// **与 R2T2 的关键差异**：上游 sherpa-onnx 只发布**一个 tar.bz2**，不是逐文件下载源。
/// 所以这里描述的是**解包之后**应当出现的三个产物；`downloadURL` 填的是它们共同的来源归档。
/// `ModelIntegrityValidator` 只读本地文件、不会拿 `downloadURL` 逐个下载，因此这个清单
/// 可以同时承担「归档从哪来」和「解包后应该有什么」两件事的说明责任。
///
/// 归档自身的 sha256 不在这个清单里：`ModelComponentManifest.sha256` 描述的是
/// `localPath` 指向的本地文件。归档校验由 `FireRedASRModelStoreDownloader` 在解包之前单独做，
/// 用的是 `FireRedASRModel.archiveSHA256`。
///
/// 许可现状：`license.name` 填的是上游**代码仓库**可验证的 Apache-2.0。sherpa-onnx 发布的
/// 权重资产里没有任何 LICENSE / NOTICE，权重自身的条款仍未确认，见 `docs/third-party-licenses.md`。
public enum FireRedASRManifestCatalog {
    public static let modelID = ModelID(rawValue: "fireredasr-aed-int8")

    /// 版本即安装目录名：上游按日期切资产，目录名已经唯一确定了一份权重。
    public static let version = FireRedASRModel.directoryName

    /// 运行时标识。改动 sherpa-onnx 版本并需要让旧安装失效时改这里。
    public static let runtimeVersion = "sherpa-onnx-1.13.3-fire-red-asr"

    /// 尝试门槛：AED 实测峰值 RSS 2814 MB，16 GB 是留出系统与其它 App 之后的可用配置。
    public static let minimumMemoryBytes: Int64 = 16 * 1_024 * 1_024 * 1_024

    /// sherpa-onnx 静态库同时支持两种架构，没有理由人为限制。
    public static let supportedArchitectures: [ModelArchitecture] = [.arm64, .x86_64]

    public static let minimumOSVersion = "15.0"

    /// 安装完成后磁盘上的字节数。
    public static var installedBytes: Int64 {
        FireRedASRModel.installedBytes
    }

    /// 下载 + 解包期间需要**同时**容纳归档与解包结果，所以门槛是两者之和而不是取较大者。
    /// 用户实际要下载的字节数（归档本体）。
    ///
    /// 与 `installedBytes` / `requiredDiskBytes` 区分开：设置页的「模型大小」在安装前就要显示，
    /// 所以取的是传输量，与 FunASR / SenseVoice 等既有本地 Provider 的口径一致。
    public static var expectedDownloadBytes: Int64 {
        FireRedASRModel.archiveBytes
    }

    public static var requiredDiskBytes: Int64 {
        FireRedASRModel.archiveBytes + FireRedASRModel.installedBytes
    }

    /// 下载与安装状态查询共用的安装键。
    public static var modelInstallKey: ModelInstallKey {
        ModelInstallKey(modelID: modelID, version: version)
    }

    /// 描述**解包产物**的清单，交给 `ModelIntegrityValidator` 与 `ModelAtomicInstaller`。
    public static func installedManifest() -> ModelManifest {
        ModelManifest(
            schemaVersion: 1,
            components: FireRedASRModel.componentDigests.map { digest in
                ModelComponentManifest(
                    providerID: ModelProviderID(rawValue: "fireredasr"),
                    modelID: modelID,
                    version: version,
                    runtimeVersion: runtimeVersion,
                    downloadURL: FireRedASRModel.archiveURL,
                    expectedSizeBytes: digest.bytes,
                    sha256: SHA256Digest(rawValue: digest.sha256),
                    localPath: digest.path,
                    requirement: .required,
                    supportedArchitectures: supportedArchitectures,
                    minimumOSVersion: minimumOSVersion,
                    minimumMemoryBytes: minimumMemoryBytes,
                    license: ModelLicense(
                        name: "Apache-2.0",
                        url: URL(string: "https://github.com/FireRedTeam/FireRedASR/blob/main/LICENSE")
                    )
                )
            }
        )
    }

    /// 描述**下载归档**的单组件清单，交给 `ResumableModelDownloader` 做断点续传下载。
    ///
    /// 它只用于下载：`localPath` 是归档在 staging 里的文件名，sha256 是归档自身的哈希。
    /// 解包之后这个文件会被删掉，因此它不会出现在最终安装目录里。
    public static func archiveManifest() -> ModelManifest {
        ModelManifest(
            schemaVersion: 1,
            components: [
                ModelComponentManifest(
                    providerID: ModelProviderID(rawValue: "fireredasr"),
                    modelID: modelID,
                    version: version,
                    runtimeVersion: runtimeVersion,
                    downloadURL: FireRedASRModel.archiveURL,
                    expectedSizeBytes: FireRedASRModel.archiveBytes,
                    sha256: SHA256Digest(rawValue: FireRedASRModel.archiveSHA256),
                    localPath: FireRedASRModel.archiveName,
                    requirement: .required,
                    supportedArchitectures: supportedArchitectures,
                    minimumOSVersion: minimumOSVersion,
                    minimumMemoryBytes: minimumMemoryBytes,
                    license: ModelLicense(
                        name: "Apache-2.0",
                        url: URL(string: "https://github.com/FireRedTeam/FireRedASR/blob/main/LICENSE")
                    )
                )
            ]
        )
    }
}
