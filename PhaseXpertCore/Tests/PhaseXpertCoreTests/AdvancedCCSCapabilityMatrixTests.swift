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

    func testNitrogenIsSurveyedButNotProductionEnabled() throws {
        XCTAssertTrue(
            TeqpFormulationCatalog.surveyedBinaryImpurities.contains(.nitrogen)
        )
        XCTAssertEqual(
            TeqpFormulationCatalog.co2NitrogenGernertGergDiagnostic.status,
            .failedValidation
        )
        XCTAssertFalse(
            TeqpFormulationCatalog.productionFormulations.contains {
                $0.components == [.carbonDioxide, .nitrogen]
            }
        )

        let matrix = AdvancedCCSCapabilityMatrix()
        let binary = try CanonicalComposition([
            .init(component: .carbonDioxide, moleFraction: 0.97),
            .init(component: .nitrogen, moleFraction: 0.03)
        ])

        let decision = matrix.decision(
            for: binary,
            property: .density,
            pressurePa: 10_000_000,
            temperatureK: 303.15
        )

        XCTAssertFalse(decision.isSupported)
        XCTAssertEqual(decision.validationState, .unsupported)
        XCTAssertNil(decision.formulationID)
    }
}
