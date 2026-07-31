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
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.4")
    ],
    targets: [
        .executableTarget(
            name: "Rusifikator",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            exclude: ["Resources/Rusifikator-Info.plist"],
            resources: [
                .copy("Resources/Rusifikator.icns"),
                .copy("Resources/SystemPrompt.txt")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ],
            linkerSettings: [
                // The bundle is assembled by scripts/package-app.sh, which places
                // Sparkle.framework in Contents/Frameworks.
                .unsafeFlags([
                    "-Xlinker", "-rpath",
                    "-Xlinker", "@executable_path/../Frameworks"
                ])
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
