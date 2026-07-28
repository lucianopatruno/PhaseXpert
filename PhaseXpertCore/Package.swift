// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PhaseXpertCore",
    platforms: [
        .iOS(.v18),
        .macOS(.v15)
    ],
    products: [
        .library(name: "PhaseXpertCore", targets: ["PhaseXpertCore"])
    ],
    targets: [
        .target(name: "PhaseXpertCore"),
        .testTarget(
            name: "PhaseXpertCoreTests",
            dependencies: ["PhaseXpertCore"]
        )
    ]
)

