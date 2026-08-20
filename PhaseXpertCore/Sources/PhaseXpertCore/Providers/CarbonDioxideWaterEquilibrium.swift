import Foundation

public enum WaterEquilibriumStatus: String, Codable, Equatable, Sendable {
    case belowSaturation
    case atSaturation
    case aqueousWaterExpected
    case unknown

    public var displayName: String {
        switch self {
        case .belowSaturation: "Below saturation"
        case .atSaturation: "At saturation"
        case .aqueousWaterExpected: "Aqueous water expected"
        case .unknown: "Unknown / outside validated domain"
        }
    }
}

/// Phase-equilibrium result for the binary CO₂/pure-H₂O system.
///
/// This is intentionally separate from homogeneous property providers. Mole
/// fractions are those of the two coexisting phases, not an EOS evaluation of
/// the stream's overall composition.
public struct CarbonDioxideWaterEquilibriumResult: Codable, Equatable, Sendable {
    public let waterInCarbonDioxideRichPhaseMoleFraction: Double
    public let carbonDioxideInWaterRichPhaseMoleFraction: Double
    public let currentWaterMoleFraction: Double?
    public let waterStatus: WaterEquilibriumStatus
    public let waterDropoutPressurePa: Double?
    public let waterDropoutTemperatureK: Double?
    public let modelIdentifier: String
    public let validationStatus: String
    public let durationMilliseconds: Double

    public var waterInCarbonDioxideRichPhasePPM: Double {
        waterInCarbonDioxideRichPhaseMoleFraction * 1_000_000
    }

    public var currentWaterPPM: Double? {
        currentWaterMoleFraction.map { $0 * 1_000_000 }
    }

    public var marginToSaturationPPM: Double? {
        currentWaterPPM.map { waterInCarbonDioxideRichPhasePPM - $0 }
    }

    public var waterSaturationRatio: Double? {
        currentWaterMoleFraction.map { $0 / waterInCarbonDioxideRichPhaseMoleFraction }
    }
}

public enum CarbonDioxideWaterEquilibriumError: Error, Equatable, Sendable {
    case outsideValidatedDomain
    case invalidInput
    case noPhysicalRoot
    case dropoutPressureUnavailable
    case dropoutTemperatureUnavailable
}

/// Spycher, Pruess & Ennis-King (2003) binary pure-water model.
///
/// Equations 11–14 and Appendix B (B1–B10) are implemented from the primary
/// publication. All constants below are Table 1 or Table 2 values. No source
/// code or coefficients were copied from a third-party implementation.
public struct SpycherPruess2003WaterEquilibrium: Sendable {
    public static let modelIdentifier = "Spycher-Pruess-Ennis-King-2003-pure-water"

    public struct ValidatedRegion: Equatable, Sendable {
        public let temperatureRangeK: ClosedRange<Double>
        public let pressureRangePa: ClosedRange<Double>
    }

    /// Independent validation regions. Meyer & Harvey (2015) supplies four
    /// isotherms spanning 30–80 °C below 5 MPa; Sánchez-Vicente & Trusler
    /// (2022) supplies the separate 100 °C, 4.70–15.09 MPa region.
    public static let validatedRegions = [
        ValidatedRegion(
            temperatureRangeK: 303.14...353.15,
            pressureRangePa: 499_900.0...5_005_500.0
        ),
        ValidatedRegion(
            temperatureRangeK: 373.15...373.30,
            pressureRangePa: 4_700_000.0...15_090_000.0
        )
    ]

    public static let validatedRangeSummary =
        "30–80 °C at 4.999–50.055 bar(a), plus 100 °C at 47.0–150.9 bar(a)."

    // Largest absolute model/experiment discrepancy in the independently
    // encoded 2022 CO₂-rich-phase validation rows. It defines only the
    // uncertainty-aware classification band, not an adjustable fit tolerance.
    public static let waterClassificationRelativeBand = 0.10

    public init() {}

    public func equilibrium(
        pressurePa: Double,
        temperatureK: Double,
        currentWaterMoleFraction: Double? = nil
    ) throws -> CarbonDioxideWaterEquilibriumResult {
        let startedAt = Date()
        guard pressurePa.isFinite, temperatureK.isFinite,
              pressurePa > 0, temperatureK > 0,
              currentWaterMoleFraction?.isFinite != false,
              currentWaterMoleFraction.map({ (0...1).contains($0) }) != false else {
            throw CarbonDioxideWaterEquilibriumError.invalidInput
        }
        guard Self.isValidated(pressurePa: pressurePa, temperatureK: temperatureK) else {
            throw CarbonDioxideWaterEquilibriumError.outsideValidatedDomain
        }

        let composition = try mutualSolubility(
            pressurePa: pressurePa,
            temperatureK: temperatureK
        )
        let status: WaterEquilibriumStatus
        if let currentWaterMoleFraction {
            let delta = currentWaterMoleFraction - composition.water
            if abs(delta) <= composition.water * Self.waterClassificationRelativeBand {
                status = .atSaturation
            } else if delta < 0 {
                status = .belowSaturation
            } else {
                status = .aqueousWaterExpected
            }
        } else {
            status = .unknown
        }

        let dropoutPressure = currentWaterMoleFraction.flatMap {
            try? waterDropoutPressurePa(
                temperatureK: temperatureK,
                waterMoleFraction: $0
            )
        }
        let dropoutTemperature = currentWaterMoleFraction.flatMap {
            try? waterDropoutTemperatureK(
                pressurePa: pressurePa,
                waterMoleFraction: $0
            )
        }
        return CarbonDioxideWaterEquilibriumResult(
            waterInCarbonDioxideRichPhaseMoleFraction: composition.water,
            carbonDioxideInWaterRichPhaseMoleFraction: composition.carbonDioxide,
            currentWaterMoleFraction: currentWaterMoleFraction,
            waterStatus: status,
            waterDropoutPressurePa: dropoutPressure,
            waterDropoutTemperatureK: dropoutTemperature,
            modelIdentifier: Self.modelIdentifier,
            validationStatus: "Limited production — independent 30–80 °C and 100 °C binary pure-water validation",
            durationMilliseconds: Date().timeIntervalSince(startedAt) * 1_000
        )
    }

    /// Solves the validated-isotherm saturation equation at fixed temperature.
    /// No root is returned when the requested water content does not cross the
    /// saturation curve inside the independently validated pressure interval.
    public func waterDropoutPressurePa(
        temperatureK: Double,
        waterMoleFraction: Double
    ) throws -> Double {
        guard waterMoleFraction.isFinite,
              (0...1).contains(waterMoleFraction),
              let region = Self.validatedRegions.first(where: {
                  $0.temperatureRangeK.contains(temperatureK)
              }) else {
            throw CarbonDioxideWaterEquilibriumError.invalidInput
        }
        var lower = region.pressureRangePa.lowerBound
        var upper = region.pressureRangePa.upperBound
        guard Self.isValidated(pressurePa: lower, temperatureK: temperatureK),
              Self.isValidated(pressurePa: upper, temperatureK: temperatureK) else {
            throw CarbonDioxideWaterEquilibriumError.dropoutPressureUnavailable
        }
        var lowerResidual = try mutualSolubility(
            pressurePa: lower,
            temperatureK: temperatureK
        ).water - waterMoleFraction
        let upperResidual = try mutualSolubility(
            pressurePa: upper,
            temperatureK: temperatureK
        ).water - waterMoleFraction
        guard lowerResidual == 0 || upperResidual == 0 || lowerResidual.sign != upperResidual.sign else {
            throw CarbonDioxideWaterEquilibriumError.dropoutPressureUnavailable
        }
        if lowerResidual == 0 { return lower }
        if upperResidual == 0 { return upper }

        for _ in 0..<80 {
            let midpoint = 0.5 * (lower + upper)
            let residual = try mutualSolubility(
                pressurePa: midpoint,
                temperatureK: temperatureK
            ).water - waterMoleFraction
            if abs(residual) <= 1e-12 || upper - lower <= 0.1 {
                return midpoint
            }
            if residual.sign == lowerResidual.sign {
                lower = midpoint
                lowerResidual = residual
            } else {
                upper = midpoint
            }
        }
        return 0.5 * (lower + upper)
    }

    /// Solves water saturation at fixed pressure using only the contiguous
    /// independently validated 30–80 °C region. The isolated 100 °C region is
    /// deliberately not bridged by interpolation.
    public func waterDropoutTemperatureK(
        pressurePa: Double,
        waterMoleFraction: Double
    ) throws -> Double {
        let region = Self.validatedRegions[0]
        guard pressurePa.isFinite, waterMoleFraction.isFinite,
              region.pressureRangePa.contains(pressurePa),
              (0...1).contains(waterMoleFraction) else {
            throw CarbonDioxideWaterEquilibriumError.invalidInput
        }
        var lower = region.temperatureRangeK.lowerBound
        var upper = region.temperatureRangeK.upperBound
        var lowerResidual = try mutualSolubility(
            pressurePa: pressurePa,
            temperatureK: lower
        ).water - waterMoleFraction
        let upperResidual = try mutualSolubility(
            pressurePa: pressurePa,
            temperatureK: upper
        ).water - waterMoleFraction
        guard lowerResidual == 0 || upperResidual == 0 || lowerResidual.sign != upperResidual.sign else {
            throw CarbonDioxideWaterEquilibriumError.dropoutTemperatureUnavailable
        }
        if lowerResidual == 0 { return lower }
        if upperResidual == 0 { return upper }
        for _ in 0..<80 {
            let midpoint = 0.5 * (lower + upper)
            let residual = try mutualSolubility(
                pressurePa: pressurePa,
                temperatureK: midpoint
            ).water - waterMoleFraction
            if abs(residual) <= 1e-12 || upper - lower <= 1e-7 {
                return midpoint
            }
            if residual.sign == lowerResidual.sign {
                lower = midpoint
                lowerResidual = residual
            } else {
                upper = midpoint
            }
        }
        return 0.5 * (lower + upper)
    }

    public static func isValidated(pressurePa: Double, temperatureK: Double) -> Bool {
        validatedRegions.contains {
            $0.temperatureRangeK.contains(temperatureK)
                && $0.pressureRangePa.contains(pressurePa)
        }
    }

    func mutualSolubility(
        pressurePa: Double,
        temperatureK: Double
    ) throws -> (water: Double, carbonDioxide: Double) {
        let pressureBar = pressurePa / 100_000
        let gas = try compressedCarbonDioxideState(
            pressureBar: pressureBar,
            temperatureK: temperatureK
        )
        let phiCarbonDioxide = fugacityCoefficient(
            molarVolume: gas.volume,
            pressureBar: pressureBar,
            temperatureK: temperatureK,
            attractionCrossParameter: gas.attraction,
            componentRepulsionParameter: 27.80,
            mixtureAttractionParameter: gas.attraction
        )
        let phiWater = fugacityCoefficient(
            molarVolume: gas.volume,
            pressureBar: pressureBar,
            temperatureK: temperatureK,
            attractionCrossParameter: 7.89e7,
            componentRepulsionParameter: 18.18,
            mixtureAttractionParameter: gas.attraction
        )
        let temperatureCelsius = temperatureK - 273.15
        let logWaterK0 = -2.209
            + 3.097e-2 * temperatureCelsius
            - 1.098e-4 * pow(temperatureCelsius, 2)
            + 2.048e-7 * pow(temperatureCelsius, 3)
        let logCarbonDioxideK0 = 1.189
            + 1.304e-2 * temperatureCelsius
            - 5.446e-5 * pow(temperatureCelsius, 2)
        let waterK0 = pow(10, logWaterK0)
        let carbonDioxideK0 = pow(10, logCarbonDioxideK0)
        let gasConstant = 83.14462618 // bar·cm³·mol⁻¹·K⁻¹
        let deltaPressureBar = pressureBar - 1
        let a = waterK0 / (phiWater * pressureBar)
            * exp(deltaPressureBar * 18.1 / (gasConstant * temperatureK))
        let b = phiCarbonDioxide * pressureBar / (55.508 * carbonDioxideK0)
            * exp(-deltaPressureBar * 32.6 / (gasConstant * temperatureK))
        let water = (1 - b) / (1 / a - b)
        let carbonDioxide = b * (1 - water)
        guard water.isFinite, carbonDioxide.isFinite,
              (0...1).contains(water), (0...1).contains(carbonDioxide) else {
            throw CarbonDioxideWaterEquilibriumError.noPhysicalRoot
        }
        return (water, carbonDioxide)
    }

    private func compressedCarbonDioxideState(
        pressureBar: Double,
        temperatureK: Double
    ) throws -> (volume: Double, attraction: Double) {
        let gasConstant = 83.14462618
        let repulsion = 27.80
        let attraction = 7.54e7 - 4.13e4 * temperatureK
        let rootA = -gasConstant * temperatureK / pressureBar
        let rootB = -pow(repulsion, 2)
            - gasConstant * temperatureK * repulsion / pressureBar
            + attraction / (pressureBar * sqrt(temperatureK))
        let rootC = -attraction * repulsion / (pressureBar * sqrt(temperatureK))
        let roots = cubicRealRoots(a: rootA, b: rootB, c: rootC)
            .filter { $0.isFinite && $0 > repulsion }
            .sorted()
        guard let liquid = roots.first, let gas = roots.last else {
            throw CarbonDioxideWaterEquilibriumError.noPhysicalRoot
        }
        guard roots.count > 1 else { return (gas, attraction) }

        let straightWork = pressureBar * (gas - liquid)
        let eosWork = gasConstant * temperatureK
            * log((gas - repulsion) / (liquid - repulsion))
            + attraction / (sqrt(temperatureK) * repulsion)
            * log(((gas + repulsion) * liquid) / ((liquid + repulsion) * gas))
        return (eosWork - straightWork >= 0 ? gas : liquid, attraction)
    }

    private func fugacityCoefficient(
        molarVolume: Double,
        pressureBar: Double,
        temperatureK: Double,
        attractionCrossParameter: Double,
        componentRepulsionParameter: Double,
        mixtureAttractionParameter: Double
    ) -> Double {
        let gasConstant = 83.14462618
        let mixtureRepulsion = 27.80
        let logarithmicTerm = log((molarVolume + mixtureRepulsion) / molarVolume)
        let logPhi = log(molarVolume / (molarVolume - mixtureRepulsion))
            + componentRepulsionParameter / (molarVolume - mixtureRepulsion)
            - 2 * attractionCrossParameter
                / (gasConstant * pow(temperatureK, 1.5) * mixtureRepulsion)
                * logarithmicTerm
            + mixtureAttractionParameter * componentRepulsionParameter
                / (gasConstant * pow(temperatureK, 1.5) * pow(mixtureRepulsion, 2))
                * (logarithmicTerm - mixtureRepulsion / (molarVolume + mixtureRepulsion))
            - log(pressureBar * molarVolume / (gasConstant * temperatureK))
        return exp(logPhi)
    }

    /// Real roots of x³ + ax² + bx + c = 0.
    private func cubicRealRoots(a: Double, b: Double, c: Double) -> [Double] {
        let p = b - pow(a, 2) / 3
        let q = 2 * pow(a, 3) / 27 - a * b / 3 + c
        let discriminant = pow(q / 2, 2) + pow(p / 3, 3)
        if discriminant >= 0 {
            let squareRoot = sqrt(discriminant)
            return [cubeRoot(-q / 2 + squareRoot) + cubeRoot(-q / 2 - squareRoot) - a / 3]
        }
        let radius = 2 * sqrt(-p / 3)
        let angle = acos((3 * q / (2 * p)) * sqrt(-3 / p))
        return (0..<3).map {
            radius * cos((angle + 2 * Double($0) * .pi) / 3) - a / 3
        }
    }

    private func cubeRoot(_ value: Double) -> Double {
        value >= 0 ? pow(value, 1.0 / 3.0) : -pow(-value, 1.0 / 3.0)
    }
}
