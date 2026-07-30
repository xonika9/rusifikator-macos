// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Rusifikator",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(name: "Rusifikator", targets: ["Rusifikator"])
    ],
    targets: [
        .executableTarget(
            name: "Rusifikator",
            exclude: ["Resources/Rusifikator-Info.plist"],
            resources: [
                .copy("Resources/Rusifikator.icns"),
                .copy("Resources/SystemPrompt.txt")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "RusifikatorTests",
            dependencies: ["Rusifikator"],
            path: "Tests",
            resources: [
                .copy("Fixtures")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        )
    ]
)
