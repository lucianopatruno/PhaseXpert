import XCTest
@testable import PhaseXpertCore

final class DerivedPropertyCalculatorTests: XCTestCase {
    private let calculator = DerivedPropertyCalculator()

    func testPureCO2PropertiesUseDocumentedDefinitions() throws {
        let density = 821.4
        let pressure = 15_000_000.0
        let temperature = 293.15
        let values = calculator.values(
            requestedProperties: [.molarMass, .specificVolume, .compressibilityFactor],
            pressurePa: pressure,
            temperatureK: temperature,
            composition: [.init(component: .carbonDioxide, moleFraction: 1)],
            densityKilogramsPerCubicMetre: density
        )

        let molarMass = try value(.molarMass, in: values)
        let specificVolume = try value(.specificVolume, in: values)
        let compressibility = try value(.compressibilityFactor, in: values)

        XCTAssertEqual(molarMass.unit, "g/mol")
        XCTAssertEqual(molarMass.value!, 44.0095, accuracy: 1e-12)
        XCTAssertEqual(specificVolume.unit, "m³/kg")
        XCTAssertEqual(specificVolume.value!, 1 / density, accuracy: 1e-15)

        let expectedZ = pressure * 0.044_009_5
            / (
                density
                    * DerivedPropertyCalculator.universalGasConstantJoulesPerMoleKelvin
                    * temperature
            )
        XCTAssertEqual(compressibility.unit, "1")
        XCTAssertEqual(compressibility.value!, expectedZ, accuracy: 1e-12)
        XCTAssertTrue(compressibility.message?.contains("pM/(ρRT)") == true)
    }

    func testCO2NitrogenMolarMassIsMoleFractionWeighted() throws {
        let values = calculator.values(
            requestedProperties: [.molarMass, .compressibilityFactor],
            pressurePa: 15_000_000,
            temperatureK: 293.15,
            composition: [
                .init(component: .carbonDioxide, moleFraction: 0.95),
                .init(component: .nitrogen, moleFraction: 0.05)
            ],
            densityKilogramsPerCubicMetre: 760.2
        )

        let expectedGramsPerMole = 0.95 * 44.0095 + 0.05 * 28.0134
        XCTAssertEqual(
            try value(.molarMass, in: values).value!,
            expectedGramsPerMole,
            accuracy: 1e-12
        )
        XCTAssertEqual(
            try value(.compressibilityFactor, in: values).status,
            .calculated
        )
    }

    func testMissingReviewedMolarMassIsUnavailableRatherThanFabricated() throws {
        let values = calculator.values(
            requestedProperties: [.molarMass, .compressibilityFactor, .specificVolume],
            pressurePa: 10_000_000,
            temperatureK: 300,
            composition: [
                .init(component: .carbonDioxide, moleFraction: 0.99),
                .init(component: .oxygen, moleFraction: 0.01)
            ],
            densityKilogramsPerCubicMetre: 500
        )

        XCTAssertEqual(try value(.molarMass, in: values).status, .unavailable)
        XCTAssertTrue(
            try value(.molarMass, in: values).message?.contains("O₂") == true
        )
        XCTAssertEqual(
            try value(.compressibilityFactor, in: values).status,
            .unavailable
        )
        XCTAssertEqual(try value(.specificVolume, in: values).status, .calculated)
    }

    func testInvalidDensityFailsOnlyDensityDependentProperties() throws {
        let values = calculator.values(
            requestedProperties: [.molarMass, .compressibilityFactor, .specificVolume],
            pressurePa: 10_000_000,
            temperatureK: 300,
            composition: [.init(component: .carbonDioxide, moleFraction: 1)],
            densityKilogramsPerCubicMetre: .nan
        )

        XCTAssertEqual(try value(.molarMass, in: values).status, .calculated)
        XCTAssertEqual(try value(.compressibilityFactor, in: values).status, .failed)
        XCTAssertEqual(try value(.specificVolume, in: values).status, .failed)
        XCTAssertNil(try value(.compressibilityFactor, in: values).value)
        XCTAssertNil(try value(.specificVolume, in: values).value)
    }

    func testReturnsOnlyRequestedDerivedProperties() {
        let values = calculator.values(
            requestedProperties: [.density, .specificVolume],
            pressurePa: 10_000_000,
            temperatureK: 300,
            composition: [.init(component: .carbonDioxide, moleFraction: 1)],
            densityKilogramsPerCubicMetre: 500
        )

        XCTAssertEqual(values.map(\.property), [.specificVolume])
    }

    private func value(
        _ property: PropertyID,
        in values: [PropertyValue]
    ) throws -> PropertyValue {
        try XCTUnwrap(values.first { $0.property == property })
    }
}
