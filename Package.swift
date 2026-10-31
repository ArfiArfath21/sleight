// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Sleight",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "Sleight", targets: ["Sleight"]),
        .executable(name: "sleight-icon", targets: ["SleightIcon"]),
    ],
    targets: [
        // Pure gesture logic: no AppKit, no Vision. Everything here is unit tested.
        .target(
            name: "SleightCore",
            path: "Sources/SleightCore"
        ),
        // Logo drawing shared by the app (menu bar, icon) and the icon generator.
        .target(
            name: "SleightBrand",
            path: "Sources/SleightBrand"
        ),
        .executableTarget(
            name: "Sleight",
            dependencies: ["SleightCore", "SleightBrand"],
            path: "Sources/Sleight",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "SleightIcon",
            dependencies: ["SleightBrand"],
            path: "Sources/SleightIcon"
        ),
        .testTarget(
            name: "SleightCoreTests",
            dependencies: ["SleightCore"],
            path: "Tests/SleightCoreTests",
            resources: [.copy("Fixtures")]
        ),
    ]
)
