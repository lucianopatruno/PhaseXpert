import Foundation

/// Calculates simple engineering properties from a validated thermodynamic
/// state without calling a model library.
///
/// These values are derived, not independent equation-of-state outputs:
/// - mixture molar mass: M = Σ xᵢMᵢ
/// - specific volume: v = 1/ρ
/// - compressibility factor: Z = pM/(ρRT)
///
/// All equations use SI internally. Molar mass is returned in g/mol for
/// engineering display; pressure is Pa, temperature is K, density is kg/m³,
/// and R is the molar gas constant in J/(mol·K).
public struct DerivedPropertyCalculator: Sendable {
    public static let universalGasConstantJoulesPerMoleKelvin = 8.314_462_618_153_24

    public init() {}

    /// Returns one explicit value/status for each requested derived property.
    ///
    /// Invalid state data produces a failed status; missing reviewed component
    /// molar masses produce unavailable. No input is normalized or extrapolated.
    public func values(
        requestedProperties: Set<PropertyID>,
        pressurePa: Double,
        temperatureK: Double,
        composition: [MixtureComponent],
        densityKilogramsPerCubicMetre: Double
    ) -> [PropertyValue] {
        let requested = requestedProperties.intersection([
            .molarMass,
            .compressibilityFactor,
            .specificVolume
        ])
        guard !requested.isEmpty else { return [] }

        let molarMass = mixtureMolarMassKilogramsPerMole(composition)
        return requested.sorted { $0.rawValue < $1.rawValue }.map { property in
            switch property {
            case .molarMass:
                guard let molarMass else {
                    return unavailable(
                        property,
                        unit: "g/mol",
                        message: molarMassUnavailableMessage(for: composition)
                    )
                }
                return finitePositiveValue(
                    property,
                    value: molarMass * 1_000,
                    unit: "g/mol",
                    message: "Derived from M = ΣxᵢMᵢ using recorded mole fractions."
                )
            case .specificVolume:
                guard densityKilogramsPerCubicMetre.isFinite,
                      densityKilogramsPerCubicMetre > 0
                else {
                    return failed(
                        property,
                        unit: "m³/kg",
                        message: "A finite, positive calculated density is required."
                    )
                }
                return finitePositiveValue(
                    property,
                    value: 1 / densityKilogramsPerCubicMetre,
                    unit: "m³/kg",
                    message: "Derived from v = 1/ρ using the calculated density."
                )
            case .compressibilityFactor:
                guard let molarMass else {
                    return unavailable(
                        property,
                        unit: "1",
                        message: molarMassUnavailableMessage(for: composition)
                    )
                }
                guard pressurePa.isFinite, pressurePa > 0,
                      temperatureK.isFinite, temperatureK > 0,
                      densityKilogramsPerCubicMetre.isFinite,
                      densityKilogramsPerCubicMetre > 0
                else {
                    return failed(
                        property,
                        unit: "1",
                        message: "Finite, positive pressure, temperature and calculated density are required."
                    )
                }
                let value = pressurePa * molarMass
                    / (
                        densityKilogramsPerCubicMetre
                            * Self.universalGasConstantJoulesPerMoleKelvin
                            * temperatureK
                    )
                return finitePositiveValue(
                    property,
                    value: value,
                    unit: "1",
                    message: "Derived from Z = pM/(ρRT) using SI state values."
                )
            default:
                preconditionFailure("Only derived properties are handled here.")
            }
        }
    }

    private func mixtureMolarMassKilogramsPerMole(
        _ composition: [MixtureComponent]
    ) -> Double? {
        guard !composition.isEmpty,
              composition.allSatisfy({
                  $0.moleFraction.isFinite && $0.moleFraction >= 0
              })
        else {
            return nil
        }

        let total = composition.reduce(0) { $0 + $1.moleFraction }
        guard total.isFinite,
              abs(total - 1) <= CalculationValidator.compositionTolerance
        else {
            return nil
        }

        var molarMass = 0.0
        for item in composition where item.moleFraction > 0 {
            guard let componentMass = item.component.molarMassKilogramsPerMole,
                  componentMass.isFinite,
                  componentMass > 0
            else {
                return nil
            }
            molarMass += item.moleFraction * componentMass
        }
        return molarMass.isFinite && molarMass > 0 ? molarMass : nil
    }

    private func molarMassUnavailableMessage(
        for composition: [MixtureComponent]
    ) -> String {
        let missing = composition
            .filter {
                $0.moleFraction > 0
                    && $0.component.molarMassKilogramsPerMole == nil
            }
            .map(\.component.symbol)
            .joined(separator: ", ")
        if !missing.isEmpty {
            return "No reviewed molar-mass data are configured for: \(missing)."
        }
        return "A valid composition totaling 100 mol% is required."
    }

    private func finitePositiveValue(
        _ property: PropertyID,
        value: Double,
        unit: String,
        message: String
    ) -> PropertyValue {
        guard value.isFinite, value > 0 else {
            return failed(
                property,
                unit: unit,
                message: "The derived result was non-finite or non-positive."
            )
        }
        return PropertyValue(
            property: property,
            value: value,
            unit: unit,
            status: .calculated,
            message: message
        )
    }

    private func unavailable(
        _ property: PropertyID,
        unit: String,
        message: String
    ) -> PropertyValue {
        PropertyValue(
            property: property,
            value: nil,
            unit: unit,
            status: .unavailable,
            message: message
        )
    }

    private func failed(
        _ property: PropertyID,
        unit: String,
        message: String
    ) -> PropertyValue {
        PropertyValue(
            property: property,
            value: nil,
            unit: unit,
            status: .failed,
            message: message
        )
    }
}
