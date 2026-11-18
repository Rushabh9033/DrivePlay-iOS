// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CarTV",
    platforms: [
        .iOS(.v18),
    ],
    products: [
        .library(
            name: "CarTV",
            targets: ["CarTV"]
        ),
        .library(
            name: "ScreenRelay",
            targets: ["ScreenRelay"]
        ),
    ],
    targets: [
        .target(
            name: "Shared",
            path: "Shared"
        ),
        .target(
            name: "CarTV",
            dependencies: ["Shared"],
            path: "CarTV/Sources"
        ),
        .target(
            name: "ScreenRelay",
            dependencies: ["Shared"],
            path: "ScreenRelay",
            exclude: ["Info.plist"]
        ),
    ],
    swiftLanguageModes: [.v5]
)
