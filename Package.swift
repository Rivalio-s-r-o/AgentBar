// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "StatusBar",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "StatusBarKit",
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "StatusBarApp",
            dependencies: ["StatusBarKit"],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "StatusBarKitTests",
            dependencies: ["StatusBarKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
