// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "BuildTools",
    platforms: [.macOS("27.0")],
    dependencies: [
        .package(url: "https://github.com/nicklockwood/SwiftFormat", from: "0.63.1"),
    ],
    targets: [.target(name: "BuildTools", path: "")]
)
