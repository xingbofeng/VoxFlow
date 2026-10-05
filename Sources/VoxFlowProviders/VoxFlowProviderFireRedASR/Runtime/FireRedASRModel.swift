import Foundation

/// FireRedASR2-AED 的权重文件布局与必需路径。
///
/// 上游 sherpa-onnx 为 FireRedASR2-AED 提供**两个不同的导出**，不能混用：
///
/// | 导出 | 文件 | 实测 4 线程 RTF | 实测峰值 RSS |
/// |---|---|---|---|
/// | AED int8（本 Provider 使用） | `encoder.int8.onnx` + `decoder.int8.onnx` | 0.443 | 2814 MB |
/// | CTC int8 | `model.int8.onnx`（单文件） | 0.193 | 1270 MB |
///
/// 两个包都从同一个 ModelScope 仓库 `FireRedTeam/FireRedASR2-AED` 转换而来，但 CTC 包是把
/// AED 权重裁成纯 CTC 分支（该包 README 明写「We export only the encoder and the CTC branch.
/// The attention decoder is not used.」），**AED 包没有这句话**。同一批官方样本上 AED 明显更准
/// （`MONDAY TODAY` vs `MOAY TOAY`、`频繁` vs `平繁`、`现在时对吧` vs `现代时对我`），代价是
/// 2.3 倍解码时间与 2.2 倍内存 —— 因此本 Provider 首发 AED，并把内存门槛定在 16 GB。
///
/// CTC 导出的完整实测元数据（备后续做低内存降级档用）：
///
/// ```
/// https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-fire-red-asr2-ctc-zh_en-int8-2026-02-25.tar.bz2
/// tarball 520,516,278 B  1da8b737ecc5e29f36759a4460c754863e7c919a4ba325aea187331fbfc83274
/// model.int8.onnx 775,861,420 B  ca3dbabd82170110cc0b343c2890866d449984bc9cd92b9a18371ff80a81bb99
/// ```
///
/// `tokens.txt` 两个包完全同源（size 79,172，sha256
/// `1bc613de2112d257e61a349c3e72d1b1a9cf19c33d3ca954197ad2171e5ea07b`），可互为交叉验证。
public enum FireRedASRModel {
    /// 上游 tar.bz2 资产名。
    public static let archiveName = "sherpa-onnx-fire-red-asr2-zh_en-int8-2026-02-26.tar.bz2"

    /// 解包后的顶层目录名（= archiveName 去掉 `.tar.bz2`）。
    public static let directoryName = "sherpa-onnx-fire-red-asr2-zh_en-int8-2026-02-26"

    /// ModelStore 的安装目录：`modelsDirectory/<modelID>/<version>`。
    ///
    /// **不是**既有 sherpa 变体那种扁平布局（`modelsDirectory/<directoryName>`）：
    /// FireRedASR2-AED 由 `ModelAtomicInstaller` 安装到 `<modelID>/<version>` 下，
    /// 两条路径混用会让设置页显示一个永远不存在的目录。
    public static func installedDirectoryURL(modelsDirectory: URL) -> URL {
        let key = FireRedASRManifestCatalog.modelInstallKey
        return modelsDirectory
            .appendingPathComponent(key.modelID.rawValue, isDirectory: true)
            .appendingPathComponent(key.version, isDirectory: true)
    }

    /// 下载源。固定 release 资产，不跟随分支。
    public static let archiveURL = URL(
        string: "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/\(archiveName)"
    )!

    /// tar.bz2 自身大小（本机实测）。
    public static let archiveBytes: Int64 = 838_589_068

    /// tar.bz2 自身的 sha256（本机实测）。归档由 `FireRedASRModelStoreDownloader` 在解包前校验。
    public static let archiveSHA256 =
        "43015b3f1643a5688b4821e8ed323473d38b798c4ec291471fe00df1bcfc4f1c"

    /// 推理必需的本地文件。`README.md` 与 `test_wavs/` 不参与推理，因此不列为必需项。
    public static let requiredPaths = [
        "encoder.int8.onnx",
        "decoder.int8.onnx",
        "tokens.txt",
    ]

    public static let encoderPath = "encoder.int8.onnx"
    public static let decoderPath = "decoder.int8.onnx"
    public static let tokensPath = "tokens.txt"

    /// 实测磁盘占用（解包后三个必需文件之和）。
    public static let installedBytes: Int64 = 817_286_833 + 417_291_928 + 79_172

    /// 逐文件实测大小与 sha256，供 ModelStore 清单使用。
    ///
    /// 这些值来自本机对官方 release 资产的实测（naive 读取 + SHA256），不是从上游文档抄来的。
    public static let componentDigests: [(path: String, bytes: Int64, sha256: String)] = [
        (
            path: encoderPath,
            bytes: 817_286_833,
            sha256: "54048d66b6e8f3c80ea7ce95efe794587b0fd81d7271651d0decd3803852ae82"
        ),
        (
            path: decoderPath,
            bytes: 417_291_928,
            sha256: "b840ce7196ae4a14d05ae84bbf56082b6b61ccec5610fda907dddbcea37354ff"
        ),
        (
            path: tokensPath,
            bytes: 79_172,
            sha256: "1bc613de2112d257e61a349c3e72d1b1a9cf19c33d3ca954197ad2171e5ea07b"
        ),
    ]

    /// 推理线程数。
    ///
    /// 4 线程相对 2 线程在 sherpa-onnx 的 FireRedASR 路径上约快 1.6 倍，峰值内存基本不变；
    /// 听写是短时突发负载，不需要为省电降线程。
    public static let numThreads: Int32 = 4

    public static func modelsExist(
        at directory: URL,
        fileManager: FileManager = .default
    ) -> Bool {
        requiredPaths.allSatisfy { relativePath in
            let path = directory.appendingPathComponent(relativePath).path
            guard fileManager.isReadableFile(atPath: path),
                  let attributes = try? fileManager.attributesOfItem(atPath: path),
                  let size = attributes[.size] as? NSNumber else {
                return false
            }
            return size.int64Value > 0
        }
    }

    public static func missingRequiredPaths(
        at directory: URL,
        fileManager: FileManager = .default
    ) -> [String] {
        requiredPaths.filter { relativePath in
            let path = directory.appendingPathComponent(relativePath).path
            guard fileManager.isReadableFile(atPath: path),
                  let attributes = try? fileManager.attributesOfItem(atPath: path),
                  let size = attributes[.size] as? NSNumber else {
                return true
            }
            return size.int64Value <= 0
        }
    }
}
