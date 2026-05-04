// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "HackClubAIPlugin",
    platforms: [.macOS(.v14)],
    products: [
        .library(
            name: "HackClubAIPlugin",
            type: .dynamic,
            targets: ["HackClubAIPlugin"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/TypeWhisper/typewhisper-mac.git", branch: "main")
    ],
    targets: [
        .target(
            name: "HackClubAIPlugin",
            dependencies: [
                .product(name: "TypeWhisperPluginSDK", package: "typewhisper-mac")
            ],
            path: "Sources/HackClubAIPlugin",
            resources: [
                .copy("../../Resources/manifest.json")
            ]
        )
    ]
)
