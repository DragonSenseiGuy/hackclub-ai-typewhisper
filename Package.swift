// swift-tools-version: 6.0
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
        .package(url: "https://github.com/TypeWhisper/TypeWhisperPluginSDK.git", branch: "main")
    ],
    targets: [
        .target(
            name: "HackClubAIPlugin",
            dependencies: [
                .product(name: "TypeWhisperPluginSDK", package: "TypeWhisperPluginSDK")
            ],
            path: "Sources/HackClubAIPlugin"
        )
    ]
)
