// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "CamiFit",
    platforms: [
        .macOS("26.0")
    ],
    products: [
        .library(
            name: "CamiFitEngine",
            targets: ["CamiFitEngine"]
        ),
        .executable(
            name: "CamiFitApp",
            targets: ["CamiFitApp"]
        ),
        .library(
            name: "KGKit",
            targets: ["KGKit"]
        ),
    ],
    targets: [
        .target(
            name: "CamiFitEngine"
        ),
        .target(
            name: "KGKit",
            exclude: ["README.md"],
            resources: [
                .copy("Resources/Artifact")
            ]
        ),
        .testTarget(
            name: "KGKitTests",
            dependencies: ["KGKit"],
            resources: [
                .copy("Fixtures")
            ]
        ),
        .executableTarget(
            name: "CamiFitApp",
            dependencies: ["CamiFitEngine", "KGKit"],
            resources: [
                .copy("Resources/Presets"),
                .copy("Resources/RecordedRuns"),
                .copy("Resources/Demo")
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
            dependencies: ["CamiFitApp", "CamiFitEngine", "KGKit"]
        )
    ]
)
