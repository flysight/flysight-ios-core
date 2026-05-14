// swift-tools-version:5.5
import PackageDescription

let package = Package(
    name: "FlySightCore",
    platforms: [
        .macOS(.v10_15),
        .iOS(.v14)
    ],
    products: [
        .library(
            name: "FlySightCore",
            targets: ["FlySightCore"]),
        .library(
            name: "FlySightFirmware",
            targets: ["FlySightFirmware"]),
    ],
    dependencies: [
        // Specify any dependencies here
    ],
    targets: [
        .target(
            name: "FlySightCore",
            dependencies: ["FlySightFirmware"]),
        .target(
            name: "FlySightFirmware",
            dependencies: []),
        .testTarget(
            name: "FlySightCoreTests",
            dependencies: ["FlySightCore"]),
        .testTarget(
            name: "FlySightFirmwareTests",
            dependencies: ["FlySightFirmware"]),
    ]
)
