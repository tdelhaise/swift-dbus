// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "swift-dbus",
    products: [
        .library(name: "SwiftDBus", targets: ["SwiftDBus"]),
        .executable(name: "swift-dbus-examples", targets: ["swift-dbus-examples"]),
    ],
    targets: [
        // Low-level system library target that gives Swift access to libdbus-1
        .systemLibrary(
            name: "CDbus",
            pkgConfig: "dbus-1",
            providers: [
                .apt(["libdbus-1-dev"])
            ]
        ),
        // High-level Swift API target
        .target(
            name: "SwiftDBus",
            dependencies: ["CDbus"],
            path: "Sources/SwiftDBus",
            swiftSettings: [
                .define("LINUX", .when(platforms: [.linux]))
            ]
        ),
        // Minimal example executable target
        .executableTarget(
            name: "swift-dbus-examples",
            dependencies: ["SwiftDBus"],
            path: "Sources/swift-dbus-examples"
        ),
        // Tests
        .testTarget(
            name: "SwiftDBusTests",
            dependencies: ["SwiftDBus"],
            path: "Tests/SwiftDBusTests"
        ),
    ]
)
