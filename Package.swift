// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Halo",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Halo", targets: ["HaloApp"]),
        .library(name: "HaloCore", targets: ["HaloCore"]),
        .library(name: "HaloUI", targets: ["HaloUI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/jaywcjlove/PermissionFlow.git", exact: "2.11.3"),
    ],
    targets: [
        .target(
            name: "HaloCore",
            path: "Sources/HaloCore"
        ),
        .target(
            name: "HaloUI",
            dependencies: ["HaloCore"],
            path: "Sources/HaloUI"
        ),
        .executableTarget(
            name: "HaloApp",
            dependencies: [
                "HaloCore",
                "HaloUI",
                .product(name: "PermissionFlow", package: "PermissionFlow"),
            ],
            path: "Sources/HaloApp",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "HaloCoreTests",
            dependencies: ["HaloCore"],
            path: "Tests/HaloCoreTests"
        ),
        .testTarget(
            name: "HaloUITests",
            dependencies: ["HaloUI", "HaloCore"],
            path: "Tests/HaloUITests"
        ),
    ],
    swiftLanguageModes: [.v6]
)
