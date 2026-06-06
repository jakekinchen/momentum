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
        .executable(
            name: "MotionReferenceRecorder",
            targets: ["MotionReferenceRecorder"]
        ),
        .library(
            name: "KGKit",
            targets: ["KGKit"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/warrenm/GLTFKit2.git", exact: "0.5.15")
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
            dependencies: [
                "CamiFitEngine",
                "KGKit",
                .product(name: "GLTFKit2", package: "GLTFKit2")
            ],
            resources: [
                .copy("Resources/Avatars"),
                .copy("Resources/Brand"),
                .copy("Resources/Presets"),
                .copy("Resources/RecordedRuns"),
                .copy("Resources/Demo"),
                .copy("Resources/MotionDemos")
            ]
        ),
        .executableTarget(
            name: "MotionReferenceRecorder"
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
            dependencies: [
                "CamiFitApp",
                "CamiFitEngine",
                "KGKit",
                .product(name: "GLTFKit2", package: "GLTFKit2")
            ]
        )
    ]
)
