// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CapacitorHealth",
    platforms: [.iOS(.v13)],
    products: [
        .library(
            name: "CapacitorHealth",
            targets: ["HealthPluginPlugin"])
    ],
    dependencies: [
        .package(url: "https://github.com/ionic-team/capacitor-swift-pm.git", branch: "main")
    ],
    targets: [
        .target(
            name: "HealthPluginPlugin",
            dependencies: [
                .product(name: "Capacitor", package: "capacitor-swift-pm"),
                .product(name: "Cordova", package: "capacitor-swift-pm")
            ],
            path: "ios/Sources/HealthPluginPlugin"),
        .testTarget(
            name: "HealthPluginPluginTests",
            dependencies: ["HealthPluginPlugin"],
            path: "ios/Tests/HealthPluginPluginTests")
    ]
)