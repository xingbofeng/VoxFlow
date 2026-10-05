// swift-tools-version: 6.1
//
// VoxFlowR2T2Core — VoxFlow 内部隔离的 R2T2 流式推理核心。
//
// 上游：https://github.com/xocialize/qwen3-asr-mlx-swift
// 固定 commit：7c8768ead04c886489e62929f2c23902b99631ab
// 许可证：MIT（Copyright (c) 2026 xocialize），见 LICENSE；归属与衍化说明见 NOTICE。
//
// 本地改动（仅包定义，源码与上游逐字节一致，见 PROVENANCE.md）：
//   1. swift-tools-version 6.2 → 6.1，以适配当前 Xcode 16.4 / Swift 6.1.2。
//   2. mlx-swift 由 from: "0.31.5" 改为 exact: "0.31.4"，即 VoxFlow 现有版本，避免工具链升级外溢。
//   3. swift-transformers 由 from: "1.3.0" 提到 from: "1.3.3"，与 VoxFlow 现有解析结果一致。
//   4. 丢弃 qwen3asr-gates 可执行 target（上游自身存在 @main/top-level-code 冲突，且 VoxFlow 不需要）。
//   5. module/product 由 Qwen3ASR 改名为 VoxFlowR2T2Core，以与 speech-swift 的同名 Qwen3ASR 并存。
//   6. 该 target 关闭警告（-suppress-warnings）：上游源码使用当前 SDK 已弃用的
//      `cblas_dgemm`（需 -DACCELERATE_NEW_LAPACK）与 `createAttentionMask(h:cache:)`，
//      而 VoxFlow 的 `make debug` 门禁带 -warnings-as-errors。为保持源码与上游逐字节一致，
//      选择在此隔离包内关闭警告，而不是修改第三方源码。
import PackageDescription

let package = Package(
    name: "VoxFlowR2T2Core",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "VoxFlowR2T2Core", targets: ["VoxFlowR2T2Core"]),
    ],
    dependencies: [
        // 锁定到 VoxFlow 现有版本，禁止静默升级全局 MLX 基线。
        .package(url: "https://github.com/ml-explore/mlx-swift", exact: "0.31.4"),
        // MLXLMCommon（KVCache / attention helpers）；这是本包唯一新增到 VoxFlow 依赖图的包。
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", from: "3.31.4"),
        .package(url: "https://github.com/huggingface/swift-transformers", from: "1.3.3"),
    ],
    targets: [
        .target(
            name: "VoxFlowR2T2Core",
            dependencies: [
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXNN", package: "mlx-swift"),
                .product(name: "MLXFast", package: "mlx-swift"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "Tokenizers", package: "swift-transformers"),
            ],
            path: "Sources/VoxFlowR2T2Core",
            swiftSettings: [.swiftLanguageMode(.v5), .unsafeFlags(["-Xfrontend", "-suppress-warnings"])]
        ),
        .testTarget(
            name: "VoxFlowR2T2CoreTests",
            dependencies: ["VoxFlowR2T2Core"],
            path: "Tests/VoxFlowR2T2CoreTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
