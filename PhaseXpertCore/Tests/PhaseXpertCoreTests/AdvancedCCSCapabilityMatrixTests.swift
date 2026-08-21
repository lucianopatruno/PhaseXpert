import XCTest
@testable import PhaseXpertCore

final class AdvancedCCSCapabilityMatrixTests: XCTestCase {
    func testCanonicalCompositionOrdersByStableComponentCatalogWithoutNormalizing() throws {
        let composition = try CanonicalComposition([
            .init(component: .methane, moleFraction: 0.05),
            .init(component: .carbonDioxide, moleFraction: 0.95)
        ])

        XCTAssertEqual(
            composition.components.map(\.component),
            [.carbonDioxide, .methane]
        )
        XCTAssertEqual(composition.moleFraction(of: .methane), 0.05)
        XCTAssertEqual(composition.moleFraction(of: .carbonDioxide), 0.95)
    }

    func testCanonicalCompositionRejectsDuplicateAndOffTotalInputs() {
        XCTAssertThrowsError(try CanonicalComposition([
            .init(component: .carbonDioxide, moleFraction: 0.95),
            .init(component: .carbonDioxide, moleFraction: 0.05)
        ])) { error in
            XCTAssertEqual(error as? CanonicalCompositionError, .duplicate(.carbonDioxide))
        }

        XCTAssertThrowsError(try CanonicalComposition([
            .init(component: .carbonDioxide, moleFraction: 0.95),
            .init(component: .nitrogen, moleFraction: 0.049)
        ])) { error in
            guard case let CanonicalCompositionError.total(total) = error else {
                return XCTFail("Expected total error, got \(error).")
            }
            XCTAssertEqual(total, 0.999, accuracy: 1e-12)
        }
    }

    func testPropertySpecificCapabilitySeparatesDensityFromAcousticProperties() throws {
        let matrix = AdvancedCCSCapabilityMatrix()
        let methane = try CanonicalComposition([
            .init(component: .carbonDioxide, moleFraction: 0.95),
            .init(component: .methane, moleFraction: 0.05)
        ])

        let density = matrix.decision(
            for: methane,
            property: .density,
            pressurePa: 4_979_790,
            temperatureK: 301.147
        )
        XCTAssertTrue(density.isSupported)
        XCTAssertEqual(density.validationState, .validated)
        XCTAssertEqual(
            density.formulationID,
            TeqpFormulationCatalog.co2MethaneEOSCGGasDensity.id
        )

        let speed = matrix.decision(
            for: methane,
            property: .speedOfSound,
            pressurePa: 4_979_790,
            temperatureK: 301.147
        )
        XCTAssertFalse(speed.isSupported)
        XCTAssertEqual(speed.validationState, .unsupported)
        XCTAssertNil(speed.formulationID)
    }

    func testTernaryAdvancedMixtureIsRejectedWithAllComponentsPreserved() throws {
        let matrix = AdvancedCCSCapabilityMatrix()
        let ternary = try CanonicalComposition([
            .init(component: .methane, moleFraction: 0.03),
            .init(component: .carbonDioxide, moleFraction: 0.94),
            .init(component: .nitrogen, moleFraction: 0.03)
        ])

        let decision = matrix.decision(
            for: ternary,
            property: .density,
            pressurePa: 10_000_000,
            temperatureK: 303.15
        )

        XCTAssertFalse(decision.isSupported)
        XCTAssertEqual(decision.validationState, .unsupported)
        XCTAssertTrue(
            decision.reasons.joined(separator: " ")
                .contains("CO₂ + N₂ + CH₄")
        )
        XCTAssertEqual(
            ternary.components.map(\.component),
            [.carbonDioxide, .nitrogen, .methane]
        )
    }

    func testExactPreCombIIMulticomponentDensityGate() throws {
        let matrix = AdvancedCCSCapabilityMatrix()
        let composition = try CanonicalComposition([
            .init(component: .carbonDioxide, moleFraction: 0.942),
            .init(component: .nitrogen, moleFraction: 0.023),
            .init(component: .methane, moleFraction: 0.022),
            .init(component: .hydrogen, moleFraction: 0.013)
        ])

        let density = matrix.decision(
            for: composition, property: .density,
            pressurePa: 10_000_000, temperatureK: 313.15
        )
        XCTAssertTrue(density.isSupported)
        XCTAssertEqual(density.formulationID, TeqpFormulationCatalog.preCombIIMulticomponentDensity.id)
        XCTAssertFalse(matrix.decision(
            for: composition, property: .speedOfSound,
            pressurePa: 10_000_000, temperatureK: 313.15
        ).isSupported)
        XCTAssertFalse(matrix.decision(
            for: composition, property: .density,
            pressurePa: 10_000_000, temperatureK: 300
        ).isSupported)
    }

    func testTransportSpecDisjointPressureGateDoesNotBridgeUnvalidatedGap() throws {
        let matrix = AdvancedCCSCapabilityMatrix()
        let composition = try CanonicalComposition([
            .init(component: .carbonDioxide, moleFraction: 0.952),
            .init(component: .nitrogen, moleFraction: 0.028),
            .init(component: .argon, moleFraction: 0.005),
            .init(component: .methane, moleFraction: 0.010),
            .init(component: .hydrogen, moleFraction: 0.005)
        ])
        XCTAssertTrue(matrix.decision(for: composition, property: .density, pressurePa: 3_000_000, temperatureK: 293.15).isSupported)
        XCTAssertFalse(matrix.decision(for: composition, property: .density, pressurePa: 7_000_000, temperatureK: 293.15).isSupported)
        XCTAssertTrue(matrix.decision(for: composition, property: .density, pressurePa: 10_000_000, temperatureK: 293.15).isSupported)

        let offComposition = try CanonicalComposition([
            .init(component: .carbonDioxide, moleFraction: 0.951),
            .init(component: .nitrogen, moleFraction: 0.029),
            .init(component: .argon, moleFraction: 0.005),
            .init(component: .methane, moleFraction: 0.010),
            .init(component: .hydrogen, moleFraction: 0.005)
        ])
        XCTAssertFalse(matrix.decision(for: offComposition, property: .density, pressurePa: 3_000_000, temperatureK: 293.15).isSupported)
    }

    func testEveryMulticomponentGateRejectsAdjacentStateAndComposition() throws {
        struct Gate {
            let composition: [(ComponentID, Double)]
            let temperature: Double
            let minimumPressure: Double
            let maximumPressure: Double
        }
        let gates = [
            Gate(composition: [(.carbonDioxide, 0.920), (.nitrogen, 0.043), (.oxygen, 0.016), (.argon, 0.021)], temperature: 312.35, minimumPressure: 1_952_000, maximumPressure: 6_951_000),
            Gate(composition: [(.carbonDioxide, 0.950), (.methane, 0.033), (.hydrogen, 0.017)], temperature: 313.00, minimumPressure: 1_995_000, maximumPressure: 7_000_000),
            Gate(composition: [(.carbonDioxide, 0.942), (.nitrogen, 0.023), (.methane, 0.022), (.hydrogen, 0.013)], temperature: 313.15, minimumPressure: 2_000_000, maximumPressure: 20_002_000),
            Gate(composition: [(.carbonDioxide, 0.952), (.nitrogen, 0.028), (.argon, 0.005), (.methane, 0.010), (.hydrogen, 0.005)], temperature: 313.15, minimumPressure: 1_996_000, maximumPressure: 22_000_000)
        ]
        let matrix = AdvancedCCSCapabilityMatrix()
        for gate in gates {
            let composition = try CanonicalComposition(gate.composition.map { .init(component: $0.0, moleFraction: $0.1) })
            let midpoint = (gate.minimumPressure + gate.maximumPressure) / 2
            for property in [PropertyID.density, .molarMass, .specificVolume, .compressibilityFactor] {
                XCTAssertTrue(matrix.decision(for: composition, property: property, pressurePa: midpoint, temperatureK: gate.temperature).isSupported)
            }
            XCTAssertFalse(matrix.decision(for: composition, property: .density, pressurePa: gate.minimumPressure - 1, temperatureK: gate.temperature).isSupported)
            XCTAssertFalse(matrix.decision(for: composition, property: .density, pressurePa: gate.maximumPressure + 1, temperatureK: gate.temperature).isSupported)
            XCTAssertFalse(matrix.decision(for: composition, property: .density, pressurePa: midpoint, temperatureK: gate.temperature + 0.051).isSupported)

            var shifted = gate.composition
            shifted[0].1 -= 0.000101
            shifted[1].1 += 0.000101
            let shiftedComposition = try CanonicalComposition(shifted.map { .init(component: $0.0, moleFraction: $0.1) })
            XCTAssertFalse(matrix.decision(for: shiftedComposition, property: .density, pressurePa: midpoint, temperatureK: gate.temperature).isSupported)
        }
    }

    func testPorthosAndAramisDoNotAccidentallyMatchNewExactGates() throws {
        let matrix = AdvancedCCSCapabilityMatrix()
        for id in [
            "porthos-pipeline-specification-example",
            "aramis-ship-specification-example"
        ] {
            let builtIn = try XCTUnwrap(BuiltInCaseCatalog.caseWithID(id))
            let composition = try CanonicalComposition(try XCTUnwrap(builtIn.composition))
            XCTAssertFalse(matrix.decision(
                for: composition,
                property: .density,
                pressurePa: try XCTUnwrap(builtIn.defaultPressurePa),
                temperatureK: try XCTUnwrap(builtIn.defaultTemperatureK)
            ).isSupported, id)
        }
    }

    func testNitrogenHasOnlyNarrowHomogeneousGasDensityGate() throws {
        XCTAssertTrue(
            TeqpFormulationCatalog.surveyedBinaryImpurities.contains(.nitrogen)
        )
        XCTAssertEqual(
            TeqpFormulationCatalog.co2NitrogenGernertGergDiagnostic.status,
            .failedValidation
        )
        XCTAssertTrue(
            TeqpFormulationCatalog.productionFormulations.contains {
                $0.id == TeqpFormulationCatalog.co2NitrogenGernertGasDensity.id
            }
        )

        let matrix = AdvancedCCSCapabilityMatrix()
        let validated = try CanonicalComposition([
            .init(component: .carbonDioxide, moleFraction: 0.9873),
            .init(component: .nitrogen, moleFraction: 0.0127)
        ])

        let density = matrix.decision(
            for: validated,
            property: .density,
            pressurePa: 3_000_000,
            temperatureK: 283.15
        )
        XCTAssertTrue(density.isSupported)
        XCTAssertEqual(density.validationState, .validated)
        XCTAssertEqual(
            density.formulationID,
            TeqpFormulationCatalog.co2NitrogenGernertGasDensity.id
        )
        XCTAssertFalse(matrix.decision(
            for: validated,
            property: .speedOfSound,
            pressurePa: 3_000_000,
            temperatureK: 283.15
        ).isSupported)
        XCTAssertTrue(matrix.decision(
            for: validated,
            property: .density,
            pressurePa: 1_000_000,
            temperatureK: 283.15
        ).isSupported)
        XCTAssertTrue(matrix.decision(
            for: validated,
            property: .density,
            pressurePa: 4_500_000,
            temperatureK: 283.15
        ).isSupported)
        XCTAssertFalse(matrix.decision(
            for: validated,
            property: .density,
            pressurePa: 999_999,
            temperatureK: 283.15
        ).isSupported)
        XCTAssertFalse(matrix.decision(
            for: validated,
            property: .density,
            pressurePa: 4_500_001,
            temperatureK: 283.15
        ).isSupported)
        XCTAssertFalse(matrix.decision(
            for: validated,
            property: .density,
            pressurePa: 4_000_000,
            temperatureK: 283.171
        ).isSupported)

        let offComposition = try CanonicalComposition([
            .init(component: .carbonDioxide, moleFraction: 0.987199),
            .init(component: .nitrogen, moleFraction: 0.012801)
        ])
        XCTAssertFalse(matrix.decision(
            for: offComposition,
            property: .density,
            pressurePa: 4_000_000,
            temperatureK: 283.15
        ).isSupported)

        let broad = try CanonicalComposition([
            .init(component: .carbonDioxide, moleFraction: 0.95),
            .init(component: .nitrogen, moleFraction: 0.05)
        ])
        let broadDecision = matrix.decision(
            for: broad,
            property: .density,
            pressurePa: 3_000_000,
            temperatureK: 283.15
        )
        XCTAssertFalse(broadDecision.isSupported)
        XCTAssertEqual(broadDecision.validationState, .unsupported)
        XCTAssertNil(broadDecision.formulationID)
    }

    func testOxygenDensityIsEnabledOnlyInsideExactValidatedGasDomain() throws {
        let matrix = AdvancedCCSCapabilityMatrix()
        let validated = try CanonicalComposition([
            .init(component: .carbonDioxide, moleFraction: 0.94967911),
            .init(component: .oxygen, moleFraction: 0.05032089)
        ])
        XCTAssertTrue(matrix.decision(for: validated, property: .density, pressurePa: 3_940_000, temperatureK: 275.001).isSupported)
        XCTAssertTrue(matrix.decision(for: validated, property: .density, pressurePa: 3_000_000, temperatureK: 293.15).isSupported)
        XCTAssertFalse(matrix.decision(for: validated, property: .speedOfSound, pressurePa: 3_940_000, temperatureK: 275.001).isSupported)
        XCTAssertFalse(matrix.decision(for: validated, property: .density, pressurePa: 8_000_000, temperatureK: 275.001).isSupported)
        XCTAssertFalse(matrix.decision(for: validated, property: .density, pressurePa: 900_000, temperatureK: 293.15).isSupported)
        XCTAssertFalse(matrix.decision(for: validated, property: .density, pressurePa: 5_200_000, temperatureK: 293.15).isSupported)
        XCTAssertFalse(matrix.decision(for: validated, property: .density, pressurePa: 3_000_000, temperatureK: 294.15).isSupported)

        let nominal = try CanonicalComposition([
            .init(component: .carbonDioxide, moleFraction: 0.95),
            .init(component: .oxygen, moleFraction: 0.05)
        ])
        XCTAssertFalse(matrix.decision(for: nominal, property: .density, pressurePa: 3_940_000, temperatureK: 275.001).isSupported)
    }
}
