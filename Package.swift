// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "midilove",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "midilove",
            path: "Sources/midilove"
        )
    ]
)
