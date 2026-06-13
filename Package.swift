// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "TokenMeter",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "TokenMeter", targets: ["TokenMeter"])
    ],
    targets: [
        .executableTarget(
            name: "TokenMeter",
            path: "Sources/TokenMeter",
            resources: [.process("Resources")]
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
