// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "WindowRestore",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "WindowRestore"
        ),
        .testTarget(
            name: "WindowRestoreTests",
            dependencies: ["WindowRestore"]
        ),
    ]
)
