// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VoxFlowVoiceCorrectionKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "VoxFlowVoiceCorrection", targets: ["VoxFlowVoiceCorrection"]),
        .executable(name: "VoxFlowVoiceCorrectionBench", targets: ["VoxFlowVoiceCorrectionBench"])
    ],
    targets: [
        .target(
            name: "VoxFlowVoiceCorrection"
        ),
        .executableTarget(
            name: "VoxFlowVoiceCorrectionBench",
            dependencies: [
                "VoxFlowVoiceCorrection"
            ]
        ),
        .testTarget(
            name: "VoxFlowVoiceCorrectionTests",
            dependencies: [
                "VoxFlowVoiceCorrection"
            ]
        )
    ]
)
