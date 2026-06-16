// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VoiceInputApp",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "VoiceInputApp", targets: ["VoiceInputApp"])
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
        .executableTarget(
            name: "VoiceInputApp",
            dependencies: [
                .product(name: "FluidAudio", package: "FluidAudio"),
                .product(name: "WhisperKit", package: "argmax-oss-swift"),
                "CSherpaOnnx"
            ],
            path: "Sources/VoiceInputApp",
            exclude: ["Resources/Info.plist"],
            resources: [
                .copy("Resources/AuthorWeChatQRCode.jpg"),
                .copy("Resources/GitHubMark.png"),
                .copy("Resources/ASRFunASR.png"),
                .copy("Resources/ASRParaformer.png"),
                .copy("Resources/ASRQwen.png"),
                .copy("Resources/ASRSenseVoice.png"),
                .copy("Resources/ASRWhisper.png")
            ]
        ),
        .testTarget(
            name: "VoiceInputAppTests",
            dependencies: ["VoiceInputApp"]
        )
    ]
)
