// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "TVVolumeBridge",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .library(
            name: "VolumeBridgeCore",
            targets: ["VolumeBridgeCore"]
        ),
    ],
    targets: [
        .target(name: "VolumeBridgeCore"),
        .testTarget(
            name: "VolumeBridgeCoreTests",
            dependencies: ["VolumeBridgeCore"]
        ),
    ]
)
