// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "AnyFoundationModels",
    platforms: [
        .iOS(.v18), .macOS(.v15), .visionOS(.v2), .watchOS(.v11),
    ],
    products: [
        .library(
            name: "AnyFoundationModels",
            targets: ["AnyFoundationModels"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/marcomasser/ClaudeForFoundationModels.git", branch: "older-OS"),
    ],
    targets: [
        .target(
            name: "AnyFoundationModels",
            dependencies: [
                .product(name: "ClaudeForFoundationModels", package: "ClaudeForFoundationModels")
            ],
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency"),
            ],
        ),
        .testTarget(
            name: "AnyFoundationModelsTests",
            dependencies: ["AnyFoundationModels"]
        ),

    ]
)
