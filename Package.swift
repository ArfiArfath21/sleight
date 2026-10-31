// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Maestro",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "Maestro", targets: ["Maestro"]),
        .executable(name: "maestro-icon", targets: ["MaestroIcon"]),
    ],
    targets: [
        // Pure gesture logic: no AppKit, no Vision. Everything here is unit tested.
        .target(
            name: "MaestroCore",
            path: "Sources/MaestroCore"
        ),
        // Logo drawing shared by the app (menu bar, icon) and the icon generator.
        .target(
            name: "MaestroBrand",
            path: "Sources/MaestroBrand"
        ),
        .executableTarget(
            name: "Maestro",
            dependencies: ["MaestroCore", "MaestroBrand"],
            path: "Sources/Maestro",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "MaestroIcon",
            dependencies: ["MaestroBrand"],
            path: "Sources/MaestroIcon"
        ),
        .testTarget(
            name: "MaestroCoreTests",
            dependencies: ["MaestroCore"],
            path: "Tests/MaestroCoreTests"
        ),
    ]
)
