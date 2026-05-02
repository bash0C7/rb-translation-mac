// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "TranslationMac",
    platforms: [.macOS(.v12)],
    products: [
        .library(
            name: "TranslationMac",
            type: .dynamic,
            targets: ["TranslationMac"]
        ),
    ],
    targets: [
        .target(
            name: "TranslationMac"
        ),
    ]
)
