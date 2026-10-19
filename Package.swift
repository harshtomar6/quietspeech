// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WhisprProto",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(
            name: "WhisprProto",
            path: "Sources/WhisprProto"
        )
    ]
)
