// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "TranslationMac",
    platforms: [.macOS(.v15)],
    products: [
        .executable(
            name: "TranslationMacHelper",
            targets: ["TranslationMacHelper"]
        ),
    ],
    targets: [
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
