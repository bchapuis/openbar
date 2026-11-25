// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "OpenBar",
    platforms: [.macOS("15.0")],
    targets: [
        // XPC protocol and constants shared by the app and the helper.
        .target(name: "HelperShared", path: "Sources/HelperShared"),
        // The menu bar app.
        .executableTarget(
            name: "OpenBar",
            dependencies: ["HelperShared"],
            path: "Sources/OpenBar"
        ),
        // The privileged helper (launchd daemon, runs as root).
        .executableTarget(
            name: "OpenBarHelper",
            dependencies: ["HelperShared"],
            path: "Sources/OpenBarHelper"
        ),
        .testTarget(
            name: "HelperSharedTests",
            dependencies: ["HelperShared"],
            path: "Tests/HelperSharedTests"
        ),
    ]
)
