// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "TranslationMac",
    platforms: [.macOS(.v15)],
    products: [
        .library(
            name: "TranslationMac",
            type: .dynamic,
            targets: ["TranslationMac"]
        ),
        .executable(
            name: "TranslationMacHelper",
            targets: ["TranslationMacHelper"]
        ),
    ],
    targets: [
        .target(
            name: "TranslationMac"
        ),
        .executableTarget(
            name: "TranslationMacHelper",
            path: "Sources/TranslationMacHelper",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Resources/Info.plist",
                ])
            ]
        ),
    ]
)
