// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "CamiFit",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "CamiFitEngine",
            targets: ["CamiFitEngine"]
        )
    ],
    targets: [
        .target(
            name: "CamiFitEngine"
        ),
        .testTarget(
            name: "CamiFitEngineTests",
            dependencies: ["CamiFitEngine"]
        )
    ]
)
