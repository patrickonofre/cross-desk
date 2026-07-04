// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "conceal-spike",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "conceal-spike", path: "Sources")
    ]
)
