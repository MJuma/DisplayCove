// swift-tools-version:6.0

import PackageDescription

let package = Package(
    name: "DisplayCoveCore",
    platforms: [
        .macOS("27.0"),
    ],
    products: [
        .library(
            name: "DisplayCoveCore",
            targets: ["DisplayCoveCore"]
        ),
    ],
    targets: [
        .target(
            name: "DisplayCoveCore",
            path: "DisplayCove/Core",
            exclude: [
                "DisplayCaptureController.swift",
                "DisplaySession.swift",
                "VirtualDisplayBackend.swift",
            ]
        ),
        .testTarget(
            name: "DisplayCoveCoreTests",
            dependencies: ["DisplayCoveCore"],
            path: "Tests/DisplayCoveCoreTests"
        ),
    ]
)
