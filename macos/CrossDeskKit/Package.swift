// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CrossDeskKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CrossDeskKit", targets: ["CrossDeskKit"]),
        .executable(name: "CrossDeskApp", targets: ["CrossDeskApp"])
    ],
    dependencies: [
        // Auto-update (sparkle-auto-update). Só o executável depende disso —
        // a lib CrossDeskKit e seus testes ficam livres do framework.
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0")
    ],
    targets: [
        .target(name: "CrossDeskKit", path: "Sources"),
        .executableTarget(
            name: "CrossDeskApp",
            dependencies: [
                "CrossDeskKit",
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "App",
            // SPM doesn't add the app-bundle rpath Xcode adds automatically —
            // without it, dyld can't find Sparkle.framework in
            // Contents/Frameworks at launch (crashes: "Library not loaded").
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])
            ]
        ),
        .testTarget(name: "CrossDeskKitTests", dependencies: ["CrossDeskKit"], path: "Tests")
    ]
)
