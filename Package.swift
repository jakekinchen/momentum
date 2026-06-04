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
        ),
        .executable(
            name: "CamiFitApp",
            targets: ["CamiFitApp"]
        )
    ],
    targets: [
        .target(
            name: "CamiFitEngine"
        ),
        .executableTarget(
            name: "CamiFitApp",
            dependencies: ["CamiFitEngine"],
            resources: [
                .copy("Resources/Presets")
            ]
        ),
        .testTarget(
            name: "CamiFitEngineTests",
            dependencies: ["CamiFitEngine"],
            resources: [
                .copy("Fixtures")
            ]
        ),
        .testTarget(
            name: "CamiFitAppTests",
            dependencies: ["CamiFitApp", "CamiFitEngine"]
        )
    ]
)
