import Foundation
import PhaseXpertCore

struct EngineeringDisplayMeasurement: Equatable {
    let value: Double
    let unit: String

    var formatted: String {
        "\(value.formatted(.number.precision(.significantDigits(1...7)))) \(unit)"
    }
}

/// Presentation-only engineering units. Provider values and persisted provenance
/// remain in their original SI units.
enum EngineeringPropertyFormatter {
    static func measurement(for property: PropertyValue) -> EngineeringDisplayMeasurement? {
        guard property.hasFiniteCalculatedValue, let value = property.value else {
            return nil
        }

        switch (property.property, property.unit) {
        case (.dynamicViscosity, "Pa·s"):
            return .init(value: value * 1_000, unit: "mPa·s")
        case (.enthalpy, "J/kg"), (.internalEnergy, "J/kg"):
            return .init(value: value / 1_000, unit: "kJ/kg")
        case (.entropy, "J/(kg·K)"),
             (.isobaricHeatCapacity, "J/(kg·K)"),
             (.isochoricHeatCapacity, "J/(kg·K)"):
            return .init(value: value / 1_000, unit: "kJ/(kg·°C)")
        default:
            return .init(value: value, unit: property.unit)
        }
    }

    static func text(for property: PropertyValue) -> String {
        measurement(for: property)?.formatted ?? effectiveStatus(for: property).displayName
    }

    static func effectiveStatus(for property: PropertyValue) -> PropertyStatus {
        property.status == .calculated && !property.hasFiniteCalculatedValue
            ? .failed
            : property.status
    }
}

enum CalculationSummaryFormatter {
    static func text(for record: CalculationRecord) -> String {
        let composition = record.request.composition
            .filter { $0.moleFraction > 0 }
            .map {
                "\($0.component.symbol) \(($0.moleFraction * 100).formatted(.number.precision(.significantDigits(1...6)))) mol%"
            }
            .joined(separator: ", ")
        let properties = record.response.properties
            .filter { $0.status == .calculated }
            .sorted { $0.property.displayName < $1.property.displayName }
            .map { "\($0.property.displayName): \(EngineeringPropertyFormatter.text(for: $0))" }
            .joined(separator: "\n")

        return """
        PhaseXpert calculation
        Pressure: \((record.input.pressurePa / 100_000).formatted(.number.precision(.significantDigits(1...7)))) bar(a)
        Temperature: \((record.input.temperatureK - 273.15).formatted(.number.precision(.significantDigits(1...7)))) °C
        Composition: \(composition)
        Phase: \(record.response.phase.displayName)
        Model: \(record.response.model.name) \(record.response.model.modelVersion)
        Calculation ID: \(record.response.calculationID.uuidString)

        \(properties)

        PRELIMINARY — review complete provenance and model limitations before use.
        """
    }
}
