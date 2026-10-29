// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "TranslationMac",
    platforms: [.macOS(.v27)],
    products: [
        .executable(
            name: "TranslationMacHelper",
            targets: ["TranslationMacHelper"]
        ),
    ],
    targets: [
        .executableTarget(
            name: "TranslationMacHelper",
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
