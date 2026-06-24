// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VoxFlowContextBoostKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "VoxFlowContextBoost", targets: ["VoxFlowContextBoost"]),
        .executable(name: "VoxFlowContextBoostBench", targets: ["VoxFlowContextBoostBench"])
    ],
    targets: [
        .target(name: "VoxFlowContextBoost"),
        .executableTarget(
            name: "VoxFlowContextBoostBench",
            dependencies: ["VoxFlowContextBoost"]
        ),
        .testTarget(
            name: "VoxFlowContextBoostTests",
            dependencies: ["VoxFlowContextBoost"]
        )
    ]
)
