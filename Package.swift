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
        .library(
            name: "UPnPMediaTarget",
            targets: ["UPnPMediaTarget"]
        ),
    ],
    targets: [
        .target(name: "MediaControlCore"),
        .target(
            name: "UPnPMediaTarget",
            dependencies: ["MediaControlCore"]
        ),
        .testTarget(
            name: "MediaControlCoreTests",
            dependencies: ["MediaControlCore"]
        ),
        .testTarget(
            name: "UPnPMediaTargetTests",
            dependencies: ["UPnPMediaTarget"]
        ),
    ]
)
