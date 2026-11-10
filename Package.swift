// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Overview",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Overview",
            path: "Sources/Overview"
        )
    ]
)
