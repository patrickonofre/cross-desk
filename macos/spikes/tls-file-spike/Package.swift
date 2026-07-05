// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "tls-file-spike",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "tls-file-spike", path: "Sources")
    ]
)
