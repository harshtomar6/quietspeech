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
        .target(
            name: "Learning",
            path: "Sources/Learning"
        ),
        .executableTarget(
            name: "QuietSpeech",
            dependencies: [
                "Licensing",
                "Learning",
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
        .testTarget(
            name: "LearningTests",
            dependencies: ["Learning"],
            path: "Tests/LearningTests"
        ),
    ]
)
