// swift-tools-version: 6.0
import Foundation
import PackageDescription

let coolPropXCFrameworkPath = "../Vendor/CoolProp/PhaseXpertCoolPropBridge.xcframework"
let hasLocalCoolPropXCFramework = FileManager.default.fileExists(
    atPath: coolPropXCFrameworkPath
)

var phaseXpertCoreDependencies: [Target.Dependency] = []
var phaseXpertCoreLinkerSettings: [LinkerSetting] = []
var packageTargets: [Target] = []

if hasLocalCoolPropXCFramework {
    phaseXpertCoreDependencies.append(
        .target(
            name: "PhaseXpertCoolPropBridge",
            condition: .when(platforms: [.iOS])
        )
    )
    phaseXpertCoreLinkerSettings.append(
        .linkedLibrary("c++", .when(platforms: [.iOS]))
    )
    packageTargets.append(
        .binaryTarget(
            name: "PhaseXpertCoolPropBridge",
            path: coolPropXCFrameworkPath
        )
    )
}

packageTargets.append(
    .target(
        name: "PhaseXpertCore",
        dependencies: phaseXpertCoreDependencies,
        linkerSettings: phaseXpertCoreLinkerSettings
    )
)

packageTargets.append(
    .testTarget(
        name: "PhaseXpertCoreTests",
        dependencies: ["PhaseXpertCore"]
    )
)

let package = Package(
    name: "PhaseXpertCore",
    platforms: [
        .iOS(.v18),
        .macOS(.v15)
    ],
    products: [
        .library(name: "PhaseXpertCore", targets: ["PhaseXpertCore"])
    ],
    targets: packageTargets
)
