// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "StatusBar",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "StatusBarKit"),
        .executableTarget(name: "StatusBarApp", dependencies: ["StatusBarKit"]),
        .testTarget(
            name: "StatusBarKitTests",
            dependencies: ["StatusBarKit"],
            resources: [.copy("Fixtures")]   // adresář Fixtures/ musí existovat už teď (viz Step 2)
        ),
    ]
)
