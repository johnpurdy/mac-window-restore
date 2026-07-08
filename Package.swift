// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "WindowRestore",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.0.0")
    ],
    targets: [
        .target(
            name: "CAXWindowID",
            linkerSettings: [
                .linkedFramework("ApplicationServices")
            ]
        ),
        .executableTarget(
            name: "WindowRestore",
            dependencies: ["KeyboardShortcuts", "CAXWindowID"]
        ),
        .testTarget(
            name: "WindowRestoreTests",
            dependencies: ["WindowRestore", "KeyboardShortcuts", "CAXWindowID"]
        ),
    ]
)
