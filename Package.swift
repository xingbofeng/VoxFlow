// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VoxFlowApp",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "VoxFlowApp", targets: ["VoxFlowApp"])
    ],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.12.4"),
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", from: "1.0.0")
    ],
    targets: [
        .target(
            name: "CSherpaOnnx",
            path: "Vendor/CSherpaOnnx",
            publicHeadersPath: "include",
            linkerSettings: [
                .unsafeFlags([
                    "-LVendor/sherpa-onnx.xcframework/macos-arm64_x86_64",
                    "-lsherpa-onnx",
                    "-lonnxruntime",
                ]),
                .linkedLibrary("c++"),
                .linkedFramework("Accelerate"),
                .linkedFramework("Foundation"),
            ]
        ),
        .target(
            name: "VoxFlowDomain",
            path: "Sources/VoxFlowDomain"
        ),
        .target(
            name: "VoxFlowAudio",
            path: "Sources/VoxFlowAudio"
        ),
        .target(
            name: "VoxFlowASRCore",
            dependencies: [
                "VoxFlowAudio"
            ],
            path: "Sources/VoxFlowASRCore"
        ),
        .target(
            name: "VoxFlowModelStore",
            path: "Sources/VoxFlowModelStore"
        ),
        .target(
            name: "VoxFlowProviderApple",
            dependencies: [
                "VoxFlowASRCore",
                "VoxFlowAudio"
            ],
            path: "Sources/VoxFlowProviderApple"
        ),
        .target(
            name: "VoxFlowProviderQwen3",
            dependencies: [
                "VoxFlowASRCore",
                "VoxFlowAudio",
                "VoxFlowModelStore",
                .product(name: "FluidAudio", package: "FluidAudio")
            ],
            path: "Sources/VoxFlowProviderQwen3",
            resources: [
                .copy("Workers/voxflow-qwen3-mlx-worker")
            ]
        ),
        .target(
            name: "VoxFlowProviderNVIDIA",
            dependencies: [
                "VoxFlowASRCore",
                "VoxFlowAudio",
                .product(name: "FluidAudio", package: "FluidAudio")
            ],
            path: "Sources/VoxFlowProviderNVIDIA"
        ),
        .target(
            name: "VoxFlowProviderParaformer",
            dependencies: [
                "VoxFlowASRCore",
                "VoxFlowAudio",
                .product(name: "FluidAudio", package: "FluidAudio")
            ],
            path: "Sources/VoxFlowProviderParaformer"
        ),
        .target(
            name: "VoxFlowProviderFunASR",
            dependencies: [
                "VoxFlowASRCore",
                "VoxFlowAudio",
                "CSherpaOnnx"
            ],
            path: "Sources/VoxFlowProviderFunASR"
        ),
        .target(
            name: "VoxFlowProviderSenseVoice",
            dependencies: [
                "VoxFlowASRCore",
                "VoxFlowAudio",
                .product(name: "FluidAudio", package: "FluidAudio")
            ],
            path: "Sources/VoxFlowProviderSenseVoice"
        ),
        .target(
            name: "VoxFlowProviderWhisper",
            dependencies: [
                "VoxFlowASRCore",
                "VoxFlowAudio",
                .product(name: "WhisperKit", package: "argmax-oss-swift")
            ],
            path: "Sources/VoxFlowProviderWhisper"
        ),
        .target(
            name: "VoxFlowTextProcessing",
            path: "Sources/VoxFlowTextProcessing"
        ),
        .target(
            name: "VoxFlowTextInsertion",
            dependencies: [
                "VoxFlowDomain"
            ],
            path: "Sources/VoxFlowTextInsertion"
        ),
        .target(
            name: "VoxFlowLocalization",
            path: "Sources/VoxFlowLocalization"
        ),
        .target(
            name: "VoxFlowFeatures",
            path: "Sources/VoxFlowFeatures"
        ),
        .target(
            name: "VoxFlowDesignSystem",
            path: "Sources/VoxFlowDesignSystem"
        ),
        .target(
            name: "VoxFlowInfrastructure",
            path: "Sources/VoxFlowInfrastructure"
        ),
        .target(
            name: "VoxFlowASRWorker",
            path: "Sources/VoxFlowASRWorker"
        ),
        .executableTarget(
            name: "VoxFlowApp",
            dependencies: [
                "VoxFlowDomain",
                "VoxFlowAudio",
                "VoxFlowASRCore",
                "VoxFlowInfrastructure",
                "VoxFlowModelStore",
                "VoxFlowProviderNVIDIA",
                "VoxFlowProviderFunASR",
                "VoxFlowProviderParaformer",
                "VoxFlowProviderQwen3",
                "VoxFlowProviderSenseVoice",
                "VoxFlowProviderWhisper",
                "VoxFlowTextInsertion",
                "CSherpaOnnx"
            ],
            path: "Sources/VoxFlowApp",
            exclude: ["Resources/Info.plist"],
            resources: [
                .copy("Resources/AuthorWeChatQRCode.jpg"),
                .copy("Resources/GitHubMark.png"),
                .copy("Resources/ASRAppleSpeech.png"),
                .copy("Resources/ASRAssemblyAI.png"),
                .copy("Resources/ASRDoubao.png"),
                .copy("Resources/ASRElevenLabs.png"),
                .copy("Resources/ASRFunASR.png"),
                .copy("Resources/ASRGroqWhisper.png"),
                .copy("Resources/ASRMistralVoxtral.png"),
                .copy("Resources/ASRNVIDIANemotron.png"),
                .copy("Resources/ASRProviderParaformer.png"),
                .copy("Resources/ASRProviderIconAtlas.json"),
                .copy("Resources/ASRQwen.png"),
                .copy("Resources/ASRQwenCloud.png"),
                .copy("Resources/ASRSenseVoice.png"),
                .copy("Resources/ASRWhisper.png")
            ]
        ),
        .testTarget(
            name: "VoxFlowAudioTests",
            dependencies: [
                "VoxFlowAudio"
            ]
        ),
        .testTarget(
            name: "VoxFlowASRCoreTests",
            dependencies: [
                "VoxFlowASRCore",
                "VoxFlowAudio"
            ]
        ),
        .testTarget(
            name: "VoxFlowModelStoreTests",
            dependencies: [
                "VoxFlowModelStore"
            ]
        ),
        .testTarget(
            name: "VoxFlowDomainTests",
            dependencies: [
                "VoxFlowDomain"
            ]
        ),
        .testTarget(
            name: "VoxFlowInfrastructureTests",
            dependencies: [
                "VoxFlowInfrastructure"
            ]
        ),
        .testTarget(
            name: "VoxFlowTextInsertionTests",
            dependencies: [
                "VoxFlowDomain",
                "VoxFlowTextInsertion"
            ]
        ),
        .testTarget(
            name: "VoxFlowProviderNVIDIATests",
            dependencies: [
                "VoxFlowASRCore",
                "VoxFlowAudio",
                "VoxFlowProviderNVIDIA"
            ]
        ),
        .testTarget(
            name: "VoxFlowProviderParaformerTests",
            dependencies: [
                "VoxFlowASRCore",
                "VoxFlowAudio",
                "VoxFlowProviderParaformer"
            ]
        ),
        .testTarget(
            name: "VoxFlowProviderAppleTests",
            dependencies: [
                "VoxFlowASRCore",
                "VoxFlowAudio",
                "VoxFlowProviderApple"
            ]
        ),
        .testTarget(
            name: "VoxFlowProviderQwen3Tests",
            dependencies: [
                "VoxFlowASRCore",
                "VoxFlowAudio",
                "VoxFlowModelStore",
                "VoxFlowProviderQwen3"
            ]
        ),
        .testTarget(
            name: "VoxFlowProviderWhisperTests",
            dependencies: [
                "VoxFlowASRCore",
                "VoxFlowAudio",
                "VoxFlowProviderWhisper"
            ]
        ),
        .testTarget(
            name: "VoxFlowProviderFunASRTests",
            dependencies: [
                "VoxFlowASRCore",
                "VoxFlowAudio",
                "VoxFlowProviderFunASR"
            ]
        ),
        .testTarget(
            name: "VoxFlowProviderSenseVoiceTests",
            dependencies: [
                "VoxFlowASRCore",
                "VoxFlowAudio",
                "VoxFlowProviderSenseVoice"
            ]
        ),
        .testTarget(
            name: "VoxFlowProviderSmokeTests",
            dependencies: [
                "VoxFlowASRCore",
                "VoxFlowAudio",
                "VoxFlowProviderApple",
                "VoxFlowProviderFunASR",
                "VoxFlowProviderNVIDIA",
                "VoxFlowProviderParaformer",
                "VoxFlowProviderQwen3",
                "VoxFlowProviderSenseVoice",
                "VoxFlowProviderWhisper"
            ]
        ),
        .testTarget(
            name: "VoxFlowAppTests",
            dependencies: [
                "VoxFlowApp",
                "VoxFlowAudio",
                "VoxFlowASRCore",
                "VoxFlowDomain",
                "VoxFlowInfrastructure",
                "VoxFlowModelStore",
                "VoxFlowProviderFunASR",
                "VoxFlowProviderNVIDIA",
                "VoxFlowProviderParaformer",
                "VoxFlowProviderQwen3",
                "VoxFlowProviderSenseVoice",
                "VoxFlowProviderWhisper",
                "VoxFlowTextInsertion"
            ]
        )
    ]
)
