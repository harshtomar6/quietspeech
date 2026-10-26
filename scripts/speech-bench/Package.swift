// swift-tools-version: 6.2
import PackageDescription

// A separate package so the app never links Desert Ant's SDK: only this
// bench does. Run it with scripts/speech-bench/run.sh.
let package = Package(
    name: "SpeechBench",
    platforms: [.macOS("26.0")],
    dependencies: [
        .package(url: "https://github.com/Desert-Ant-Labs/desert-ant-core.git", from: "4.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "SpeechBench",
            dependencies: [
                .product(name: "Voz", package: "desert-ant-core"),
            ],
            path: "Sources/SpeechBench",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
