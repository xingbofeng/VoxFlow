// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VoxFlowContextBoostKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "VoxFlowContextBoost", targets: ["VoxFlowContextBoost"])
    ],
    targets: [
        .target(name: "VoxFlowContextBoost"),
        .testTarget(
            name: "VoxFlowContextBoostTests",
            dependencies: ["VoxFlowContextBoost"]
        )
    ]
)
