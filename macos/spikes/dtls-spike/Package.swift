// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "dtls-spike",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "dtls-spike", path: "Sources")
    ]
)
