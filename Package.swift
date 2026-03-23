// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "NeptuneDesktopMacOS",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "NeptuneDesktopMacOS", targets: ["NeptuneDesktopMacOS"])
    ],
    targets: [
        .executableTarget(
            name: "NeptuneDesktopMacOS",
            path: "Sources/NeptuneDesktopMacOS"
        ),
        .testTarget(
            name: "NeptuneDesktopMacOSTests",
            dependencies: ["NeptuneDesktopMacOS"],
            path: "Tests/NeptuneDesktopMacOSTests"
        )
    ]
)
