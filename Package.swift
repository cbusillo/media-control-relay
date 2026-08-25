// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MediaControlRelay",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .library(
            name: "MediaControlCore",
            targets: ["MediaControlCore"]
        ),
    ],
    targets: [
        .target(name: "MediaControlCore"),
        .testTarget(
            name: "MediaControlCoreTests",
            dependencies: ["MediaControlCore"]
        ),
    ]
)
