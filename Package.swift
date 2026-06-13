// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "TokenMeter",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "TokenMeter", targets: ["TokenMeter"])
    ],
    targets: [
        .executableTarget(
            name: "TokenMeter",
            path: "Sources/TokenMeter"
        ),
        .testTarget(
            name: "TokenMeterTests",
            dependencies: ["TokenMeter"],
            path: "Tests/TokenMeterTests",
            resources: [.copy("Fixtures")]
        )
    ],
    swiftLanguageModes: [.v6]
)
