// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "midilove",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "MidiloveCore",
            path: "Sources/MidiloveCore"
        ),
        .executableTarget(
            name: "midilove",
            path: "Sources/midilove"
        ),
        .executableTarget(
            name: "midilove-app",
            dependencies: ["MidiloveCore"],
            path: "Sources/midilove-app"
        )
    ]
)
