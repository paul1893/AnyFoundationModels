// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "AnyFoundationModels",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
        .visionOS(.v2),
        .watchOS(.v11),
    ],
    products: [
        .library(
            name: "AnyFoundationModels",
            targets: ["AnyFoundationModels"]
        ),
    ],
    traits: [
        .trait(name: "OpenAI"),
        .trait(name: "Claude"),
        .trait(name: "Google"),
        .default(enabledTraits: ["OpenAI", "Claude", "Google"]),
    ],
    dependencies: [
        // OpenAI
        .package(url: "https://github.com/paul1893/OpenAIForFoundationModels.git", from: "1.0.0"),
        // Anthropic
        .package(url: "https://github.com/marcomasser/ClaudeForFoundationModels.git", branch: "older-OS"),
        // Google
        .package(url: "https://github.com/paul1893/GoogleForFoundationModels.git", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "AnyFoundationModels",
            dependencies: [
                .product(
                    name: "ClaudeForFoundationModels",
                    package: "ClaudeForFoundationModels",
                    condition: .when(traits: ["Claude"])
                ),
                .product(
                    name: "OpenAIForFoundationModels",
                    package: "OpenAIForFoundationModels",
                    condition: .when(traits: ["OpenAI"])
                ),
                .product(
                    name: "GoogleForFoundationModels",
                    package: "GoogleForFoundationModels",
                    condition: .when(traits: ["Google"])
                ),
            ],
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency"),
                .define("CLAUDE_ENABLED", .when(traits: ["Claude"])),
                .define("OPENAI_ENABLED", .when(traits: ["OpenAI"])),
                .define("GOOGLE_ENABLED", .when(traits: ["Google"])),
            ],
        ),
    ]
)
