// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "QuietSpeech",
    platforms: [.macOS("26.0")],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.10.0"),
    ],
    targets: [
        .target(
            name: "Licensing",
            path: "Sources/Licensing"
        ),
        .executableTarget(
            name: "QuietSpeech",
            dependencies: [
                "Licensing",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/QuietSpeech",
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
            ]
        ),
        .testTarget(
            name: "LicensingTests",
            dependencies: ["Licensing"],
            path: "Tests/LicensingTests"
        ),
    ]
)
