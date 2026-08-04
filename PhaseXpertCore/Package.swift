// swift-tools-version: 6.0
import Foundation
import PackageDescription

let coolPropXCFrameworkPath = "../Vendor/CoolProp/PhaseXpertCoolPropBridge.xcframework"
let thermoPackXCFrameworkPath = "../Vendor/ThermoPack/PhaseXpertThermoPackBridge.xcframework"
let packageDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let coolPropXCFrameworkURL = packageDirectory.appendingPathComponent(coolPropXCFrameworkPath)
let hasLocalCoolPropXCFramework = FileManager.default.fileExists(
    atPath: coolPropXCFrameworkURL.path
)
let thermoPackXCFrameworkURL = packageDirectory.appendingPathComponent(
    thermoPackXCFrameworkPath
)
let hasLocalThermoPackXCFramework = FileManager.default.fileExists(
    atPath: thermoPackXCFrameworkURL.path
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

if hasLocalThermoPackXCFramework {
    phaseXpertCoreDependencies.append(
        .target(
            name: "PhaseXpertThermoPackBridge",
            condition: .when(platforms: [.iOS])
        )
    )
    phaseXpertCoreLinkerSettings.append(
        .linkedLibrary("c++", .when(platforms: [.iOS]))
    )
    phaseXpertCoreLinkerSettings.append(
        .linkedFramework("Accelerate", .when(platforms: [.iOS]))
    )
    packageTargets.append(
        .binaryTarget(
            name: "PhaseXpertThermoPackBridge",
            path: thermoPackXCFrameworkPath
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
