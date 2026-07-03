// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CrossDeskKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CrossDeskKit", targets: ["CrossDeskKit"]),
        .executable(name: "CrossDeskApp", targets: ["CrossDeskApp"])
    ],
    targets: [
        .target(name: "CrossDeskKit", path: "Sources"),
        .executableTarget(name: "CrossDeskApp", dependencies: ["CrossDeskKit"], path: "App"),
        .testTarget(name: "CrossDeskKitTests", dependencies: ["CrossDeskKit"], path: "Tests")
    ]
)
