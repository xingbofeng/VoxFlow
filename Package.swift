// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VoxFlowApp",
    defaultLocalization: "en",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "VoxFlowApp", targets: ["VoxFlowApp"])
    ],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.12.4"),
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "1.0.0"),
        .package(url: "https://github.com/soniqo/speech-swift.git", from: "0.0.21"),
        .package(url: "https://github.com/ordo-one/FuzzyMatch.git", from: "1.4.0"),
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", from: "2.0.2"),
        .package(url: "https://github.com/getsentry/sentry-cocoa.git", from: "9.19.0"),
        .package(path: "Packages/TextDiffing"),
        .package(path: "Packages/VoxFlowContextBoostKit"),
        .package(path: "Packages/VoxFlowVoiceCorrectionKit")
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
            path: "Sources/VoxFlowProviders/VoxFlowProviderApple"
        ),
        .target(
            name: "VoxFlowProviderQwen3",
            dependencies: [
                "VoxFlowASRCore",
                "VoxFlowAudio",
                "VoxFlowModelStore",
                .product(name: "Qwen3ASR", package: "speech-swift")
            ],
            path: "Sources/VoxFlowProviders/VoxFlowProviderQwen3"
        ),
        .target(
            name: "VoxFlowProviderNVIDIA",
            dependencies: [
                "VoxFlowASRCore",
                "VoxFlowAudio",
                .product(name: "AudioCommon", package: "speech-swift"),
                .product(name: "NemotronStreamingASR", package: "speech-swift")
            ],
            path: "Sources/VoxFlowProviders/VoxFlowProviderNVIDIA"
        ),
        .target(
            name: "VoxFlowProviderParakeet",
            dependencies: [
                "VoxFlowASRCore",
                "VoxFlowAudio",
                .product(name: "AudioCommon", package: "speech-swift"),
                .product(name: "ParakeetStreamingASR", package: "speech-swift")
            ],
            path: "Sources/VoxFlowProviders/VoxFlowProviderParakeet"
        ),
        .target(
            name: "VoxFlowProviderOmnilingual",
            dependencies: [
                "VoxFlowASRCore",
                "VoxFlowAudio",
                .product(name: "OmnilingualASR", package: "speech-swift")
            ],
            path: "Sources/VoxFlowProviders/VoxFlowProviderOmnilingual"
        ),
        .target(
            name: "VoxFlowProviderParaformer",
            dependencies: [
                "VoxFlowASRCore",
                "VoxFlowAudio",
                .product(name: "FluidAudio", package: "FluidAudio")
            ],
            path: "Sources/VoxFlowProviders/VoxFlowProviderParaformer"
        ),
        .target(
            name: "VoxFlowProviderFunASR",
            dependencies: [
                "VoxFlowASRCore",
                "VoxFlowAudio",
                "CSherpaOnnx"
            ],
            path: "Sources/VoxFlowProviders/VoxFlowProviderFunASR"
        ),
        .target(
            name: "VoxFlowProviderSenseVoice",
            dependencies: [
                "VoxFlowASRCore",
                "VoxFlowAudio",
                .product(name: "FluidAudio", package: "FluidAudio")
            ],
            path: "Sources/VoxFlowProviders/VoxFlowProviderSenseVoice"
        ),
        .target(
            name: "VoxFlowProviderWhisper",
            dependencies: [
                "VoxFlowASRCore",
                "VoxFlowAudio",
                .product(name: "WhisperKit", package: "WhisperKit")
            ],
            path: "Sources/VoxFlowProviders/VoxFlowProviderWhisper"
        ),
        .target(
            name: "VoxFlowProviderCloudCore",
            path: "Sources/VoxFlowProviders/VoxFlowProviderCloudCore"
        ),
        .target(
            name: "VoxFlowProviderGroq",
            dependencies: [
                "VoxFlowProviderCloudCore"
            ],
            path: "Sources/VoxFlowProviders/VoxFlowProviderGroq"
        ),
        .target(
            name: "VoxFlowProviderTencentCloud",
            dependencies: [
                "VoxFlowProviderCloudCore"
            ],
            path: "Sources/VoxFlowProviders/VoxFlowProviderTencentCloud"
        ),
        .target(
            name: "VoxFlowProviderAliyunDashScope",
            dependencies: [
                "VoxFlowProviderCloudCore"
            ],
            path: "Sources/VoxFlowProviders/VoxFlowProviderAliyunDashScope"
        ),
        .target(
            name: "VoxFlowProviderVolcengine",
            dependencies: [
                "VoxFlowProviderCloudCore"
            ],
            path: "Sources/VoxFlowProviders/VoxFlowProviderVolcengine"
        ),
        .target(
            name: "VoxFlowTextProcessing",
            path: "Sources/VoxFlowTextProcessing"
        ),
        .target(
            name: "VoxFlowPromptKit",
            path: "Sources/VoxFlowPromptKit"
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
            name: "VoxFlowObjCExceptionSupport",
            path: "Sources/VoxFlowObjCExceptionSupport",
            publicHeadersPath: "include"
        ),
        .target(
            name: "VoxFlowScreenshotKit",
            dependencies: [
                "VoxFlowDomain"
            ],
            path: "Sources/VoxFlowScreenshotKit",
            resources: [
                .process("Resources/zh-Hans.lproj"),
                .process("Resources/zh-Hant.lproj"),
                .process("Resources/en.lproj"),
                .process("Resources/ja.lproj"),
                .process("Resources/ko.lproj"),
            ]
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
                "VoxFlowObjCExceptionSupport",
                "VoxFlowProviderNVIDIA",
                "VoxFlowProviderParakeet",
                "VoxFlowProviderOmnilingual",
                "VoxFlowProviderFunASR",
                "VoxFlowProviderAliyunDashScope",
                "VoxFlowProviderCloudCore",
                "VoxFlowProviderGroq",
                "VoxFlowProviderVolcengine",
                "VoxFlowProviderParaformer",
                "VoxFlowProviderQwen3",
                "VoxFlowProviderSenseVoice",
                "VoxFlowProviderTencentCloud",
                "VoxFlowProviderWhisper",
                "VoxFlowScreenshotKit",
                "VoxFlowTextInsertion",
                "VoxFlowPromptKit",
                "VoxFlowTextProcessing",
                "CSherpaOnnx",
                .product(name: "VoxFlowContextBoost", package: "VoxFlowContextBoostKit"),
                .product(name: "VoxFlowVoiceCorrection", package: "VoxFlowVoiceCorrectionKit"),
                .product(name: "AudioCommon", package: "speech-swift"),
                .product(name: "FuzzyMatch", package: "FuzzyMatch"),
                .product(name: "CosyVoiceTTS", package: "speech-swift"),
                .product(name: "KokoroTTS", package: "speech-swift"),
                .product(name: "MADLADTranslation", package: "speech-swift"),
                .product(name: "Qwen3TTS", package: "speech-swift"),
                .product(name: "Qwen3Chat", package: "speech-swift"),
                .product(name: "MarkdownUI", package: "swift-markdown-ui"),
                .product(name: "Sentry", package: "sentry-cocoa"),
                .product(name: "TextDiffing", package: "TextDiffing")
            ],
            path: "Sources/VoxFlowApp",
            exclude: ["Resources/Info.plist", "Resources/zh-Hans.lproj", "Resources/zh-Hant.lproj", "Resources/en.lproj", "Resources/ja.lproj", "Resources/ko.lproj"],
            resources: [
                .copy("Resources/AuthorWeChatQRCode.jpg"),
                .copy("Resources/UserGroupQRCode.jpg"),
                .copy("Resources/GitHubMark.png"),
                .copy("Resources/ASRAppleSpeech.png"),
                .copy("Resources/ASRAssemblyAI.png"),
                .copy("Resources/ASRDoubao.png"),
                .copy("Resources/ASRElevenLabs.png"),
                .copy("Resources/ASRFunASR.png"),
                .copy("Resources/ASRGroqWhisper.png"),
                .copy("Resources/ASRMistralVoxtral.png"),
                .copy("Resources/ASRNVIDIANemotron.png"),
                .copy("Resources/ASROmnilingual.png"),
                .copy("Resources/ASRParakeetStreaming.png"),
                .copy("Resources/ASRProviderParaformer.png"),
                .copy("Resources/ASRProviderIconAtlas.json"),
                .copy("Resources/ASRQwen.png"),
                .copy("Resources/ASRQwenCloud.png"),
                .copy("Resources/ASRSenseVoice.png"),
                .copy("Resources/ASRTencentCloud.png"),
                .copy("Resources/ASRWhisper.png"),
                .copy("Resources/QuicklinkIcons"),
                .copy("Persistence/AppDatabaseSchema.sql")
            ],
            linkerSettings: [
                .linkedFramework("IOKit")
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
            name: "VoxFlowScreenshotKitTests",
            dependencies: [
                "VoxFlowScreenshotKit"
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
            name: "VoxFlowPromptKitTests",
            dependencies: [
                "VoxFlowPromptKit"
            ]
        ),
        .testTarget(
            name: "VoxFlowTextProcessingTests",
            dependencies: [
                "VoxFlowTextProcessing"
            ],
            resources: [
                .process("Fixtures")
            ]
        ),
        .testTarget(
            name: "VoxFlowProviderNVIDIATests",
            dependencies: [
                "VoxFlowASRCore",
                "VoxFlowAudio",
                "VoxFlowProviderNVIDIA"
            ],
            path: "Tests/VoxFlowProviders/VoxFlowProviderNVIDIATests"
        ),
        .testTarget(
            name: "VoxFlowProviderParaformerTests",
            dependencies: [
                "VoxFlowASRCore",
                "VoxFlowAudio",
                "VoxFlowProviderParaformer"
            ],
            path: "Tests/VoxFlowProviders/VoxFlowProviderParaformerTests"
        ),
        .testTarget(
            name: "VoxFlowProviderAppleTests",
            dependencies: [
                "VoxFlowASRCore",
                "VoxFlowAudio",
                "VoxFlowProviderApple"
            ],
            path: "Tests/VoxFlowProviders/VoxFlowProviderAppleTests"
        ),
        .testTarget(
            name: "VoxFlowProviderQwen3Tests",
            dependencies: [
                "VoxFlowASRCore",
                "VoxFlowAudio",
                "VoxFlowModelStore",
                "VoxFlowProviderQwen3"
            ],
            path: "Tests/VoxFlowProviders/VoxFlowProviderQwen3Tests"
        ),
        .testTarget(
            name: "VoxFlowProviderWhisperTests",
            dependencies: [
                "VoxFlowASRCore",
                "VoxFlowAudio",
                "VoxFlowProviderWhisper"
            ],
            path: "Tests/VoxFlowProviders/VoxFlowProviderWhisperTests"
        ),
        .testTarget(
            name: "VoxFlowProviderFunASRTests",
            dependencies: [
                "VoxFlowASRCore",
                "VoxFlowAudio",
                "VoxFlowProviderFunASR"
            ],
            path: "Tests/VoxFlowProviders/VoxFlowProviderFunASRTests"
        ),
        .testTarget(
            name: "VoxFlowProviderSenseVoiceTests",
            dependencies: [
                "VoxFlowASRCore",
                "VoxFlowAudio",
                "VoxFlowProviderSenseVoice"
            ],
            path: "Tests/VoxFlowProviders/VoxFlowProviderSenseVoiceTests"
        ),
        .testTarget(
            name: "VoxFlowProviderCloudCoreTests",
            dependencies: [
                "VoxFlowApp",
                "VoxFlowProviderCloudCore"
            ],
            path: "Tests/VoxFlowProviders/VoxFlowProviderCloudCoreTests"
        ),
        .testTarget(
            name: "VoxFlowProviderGroqTests",
            dependencies: [
                "VoxFlowProviderCloudCore",
                "VoxFlowProviderGroq"
            ],
            path: "Tests/VoxFlowProviders/VoxFlowProviderGroqTests"
        ),
        .testTarget(
            name: "VoxFlowProviderTencentCloudTests",
            dependencies: [
                "VoxFlowApp",
                "VoxFlowProviderCloudCore",
                "VoxFlowProviderTencentCloud"
            ],
            path: "Tests/VoxFlowProviders/VoxFlowProviderTencentCloudTests"
        ),
        .testTarget(
            name: "VoxFlowProviderAliyunDashScopeTests",
            dependencies: [
                "VoxFlowApp",
                "VoxFlowProviderAliyunDashScope",
                "VoxFlowProviderCloudCore"
            ],
            path: "Tests/VoxFlowProviders/VoxFlowProviderAliyunDashScopeTests"
        ),
        .testTarget(
            name: "VoxFlowProviderVolcengineTests",
            dependencies: [
                "VoxFlowApp",
                "VoxFlowProviderCloudCore",
                "VoxFlowProviderVolcengine"
            ],
            path: "Tests/VoxFlowProviders/VoxFlowProviderVolcengineTests"
        ),
        .testTarget(
            name: "VoxFlowProviderSmokeTests",
            dependencies: [
                "VoxFlowASRCore",
                "VoxFlowAudio",
                "VoxFlowProviderApple",
                "VoxFlowProviderFunASR",
                "VoxFlowProviderNVIDIA",
                "VoxFlowProviderParakeet",
                "VoxFlowProviderOmnilingual",
                "VoxFlowProviderAliyunDashScope",
                "VoxFlowProviderCloudCore",
                "VoxFlowProviderParaformer",
                "VoxFlowProviderGroq",
                "VoxFlowProviderVolcengine",
                "VoxFlowProviderQwen3",
                "VoxFlowProviderSenseVoice",
                "VoxFlowProviderTencentCloud",
                "VoxFlowProviderWhisper"
            ],
            path: "Tests/VoxFlowProviders/VoxFlowProviderSmokeTests"
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
                "VoxFlowPromptKit",
                "VoxFlowProviderFunASR",
                "VoxFlowProviderNVIDIA",
                "VoxFlowProviderParakeet",
                "VoxFlowProviderOmnilingual",
                "VoxFlowProviderAliyunDashScope",
                "VoxFlowProviderCloudCore",
                "VoxFlowProviderParaformer",
                "VoxFlowProviderGroq",
                "VoxFlowProviderVolcengine",
                "VoxFlowProviderQwen3",
                "VoxFlowProviderSenseVoice",
                "VoxFlowProviderTencentCloud",
                "VoxFlowProviderWhisper",
                "VoxFlowTextInsertion",
                .product(name: "VoxFlowContextBoost", package: "VoxFlowContextBoostKit")
            ],
            resources: [
                .copy("Fixtures")
            ]
        )
    ]
)
