import XCTest
@testable import PhaseXpertCore

final class GeneralPropertiesCapabilityMatrixTests: XCTestCase {
    func testAuditedComponentListMatchesCurrentGeneralPropertiesProvider() {
        let provider = CoolPropProvider(engine: MatrixMockCoolPropEngine())

        XCTAssertEqual(
            Set(GeneralPropertiesCapabilityMatrix.auditedComponents),
            provider.descriptor.supportedComponents
        )
        XCTAssertEqual(
            GeneralPropertiesCapabilityMatrix.auditedComponents,
            [
                .carbonDioxide, .nitrogen, .methane, .oxygen, .argon, .hydrogen,
                .carbonMonoxide, .hydrogenSulfide, .water
            ]
        )
        XCTAssertEqual(provider.descriptor.providerVersion, "0.11.0")
    }

    func testLimitedProductionDensityDomainsAreCompositionSpecific() {
        let methaneInside = GeneralPropertiesCapabilityMatrix.decision(
            for: [
                MixtureComponent(component: .carbonDioxide, moleFraction: 0.95),
                MixtureComponent(component: .methane, moleFraction: 0.05)
            ],
            property: .density,
            pressurePa: 6_976_000,
            temperatureK: 301.133
        )
        let methaneOutside = GeneralPropertiesCapabilityMatrix.decision(
            for: [
                MixtureComponent(component: .carbonDioxide, moleFraction: 0.95),
                MixtureComponent(component: .methane, moleFraction: 0.05)
            ],
            property: .density,
            pressurePa: 3_000_000,
            temperatureK: 293.15
        )
        let oxygenInside = GeneralPropertiesCapabilityMatrix.decision(
            for: [
                MixtureComponent(component: .carbonDioxide, moleFraction: 0.94967911),
                MixtureComponent(component: .oxygen, moleFraction: 0.05032089)
            ],
            property: .compressibilityFactor,
            pressurePa: 3_999_000,
            temperatureK: 293.101
        )
        let oxygenOutsideComposition = GeneralPropertiesCapabilityMatrix.decision(
            for: [
                MixtureComponent(component: .carbonDioxide, moleFraction: 0.9),
                MixtureComponent(component: .oxygen, moleFraction: 0.1)
            ],
            property: .density,
            pressurePa: 3_999_000,
            temperatureK: 293.101
        )
        let hydrogenInside = GeneralPropertiesCapabilityMatrix.decision(
            for: [
                MixtureComponent(component: .carbonDioxide, moleFraction: 0.94638),
                MixtureComponent(component: .hydrogen, moleFraction: 0.05362)
            ],
            property: .specificVolume,
            pressurePa: 5_997_370,
            temperatureK: 323.15
        )

        XCTAssertEqual(methaneInside.status, .limitedProduction)
        XCTAssertTrue(methaneInside.isInsideValidatedDomain)
        XCTAssertEqual(methaneOutside.status, .preliminaryValidationPending)
        XCTAssertFalse(methaneOutside.isInsideValidatedDomain)
        XCTAssertEqual(oxygenInside.status, .limitedProduction)
        XCTAssertTrue(oxygenInside.isInsideValidatedDomain)
        XCTAssertEqual(oxygenOutsideComposition.status, .preliminaryValidationPending)
        XCTAssertFalse(oxygenOutsideComposition.isInsideValidatedDomain)
        XCTAssertEqual(hydrogenInside.status, .limitedProduction)
        XCTAssertTrue(hydrogenInside.isInsideValidatedDomain)
    }

    func testUnpromotedDryImpuritiesRemainPreliminaryAndCalculableForDensity() {
        for impurity in [ComponentID.nitrogen, .argon, .carbonMonoxide, .hydrogenSulfide] {
            let decision = GeneralPropertiesCapabilityMatrix.decision(
                for: [
                    MixtureComponent(component: .carbonDioxide, moleFraction: 0.99),
                    MixtureComponent(component: impurity, moleFraction: 0.01)
                ],
                property: .density,
                pressurePa: 3_000_000,
                temperatureK: 293.15
            )

            XCTAssertTrue(decision.isCalculable, "\(impurity)")
            XCTAssertFalse(decision.isInsideValidatedDomain, "\(impurity)")
            XCTAssertEqual(decision.status, .preliminaryValidationPending, "\(impurity)")
        }
    }

    func testDryMulticomponentDensityRemainsPreliminaryWithoutDroppingComponents() {
        let decision = GeneralPropertiesCapabilityMatrix.decision(
            for: [
                MixtureComponent(component: .carbonDioxide, moleFraction: 0.93),
                MixtureComponent(component: .nitrogen, moleFraction: 0.05),
                MixtureComponent(component: .methane, moleFraction: 0.02)
            ],
            property: .density,
            pressurePa: 10_000_000,
            temperatureK: 293.15
        )

        XCTAssertTrue(decision.isCalculable)
        XCTAssertEqual(decision.status, .preliminaryValidationPending)
        XCTAssertFalse(decision.isInsideValidatedDomain)
        XCTAssertNil(decision.capability)
    }

    func testMixtureCaloricAcousticAndTransportRemainUnsupported() {
        let composition = [
            MixtureComponent(component: .carbonDioxide, moleFraction: 0.95),
            MixtureComponent(component: .nitrogen, moleFraction: 0.05)
        ]

        for property in [
            PropertyID.enthalpy,
            .entropy,
            .internalEnergy,
            .isobaricHeatCapacity,
            .isochoricHeatCapacity,
            .speedOfSound,
            .dynamicViscosity,
            .thermalConductivity
        ] {
            let decision = GeneralPropertiesCapabilityMatrix.decision(
                for: composition,
                property: property,
                pressurePa: 3_000_000,
                temperatureK: 293.15
            )

            XCTAssertFalse(decision.isCalculable, "\(property)")
            XCTAssertEqual(decision.status, .unsupported, "\(property)")
        }
    }

    func testWetHomogeneousGateRemainsPreliminaryAndNarrow() {
        let composition = [
            MixtureComponent(component: .carbonDioxide, moleFraction: 0.9995),
            MixtureComponent(component: .water, moleFraction: 0.0005)
        ]
        let densityDecision = GeneralPropertiesCapabilityMatrix.decision(
            for: composition,
            property: .density,
            pressurePa: 4_000_000,
            temperatureK: 373.15
        )
        let heatCapacityDecision = GeneralPropertiesCapabilityMatrix.decision(
            for: composition,
            property: .isobaricHeatCapacity,
            pressurePa: 4_000_000,
            temperatureK: 373.15
        )

        XCTAssertEqual(densityDecision.status, .preliminaryValidationPending)
        XCTAssertTrue(densityDecision.isCalculable)
        XCTAssertFalse(densityDecision.isInsideValidatedDomain)
        XCTAssertEqual(densityDecision.capability?.temperatureDomainK, 350...423.15)
        XCTAssertEqual(densityDecision.capability?.pressureDomainPa, 500_000...5_000_000)
        XCTAssertEqual(heatCapacityDecision.status, .unsupported)
        XCTAssertFalse(heatCapacityDecision.isCalculable)
    }
}

private struct MatrixMockCoolPropEngine: CoolPropEngine {
    let isAvailable = true
    let libraryVersion = "8.0.0"

    func calculatePureCarbonDioxide(
        pressurePa: Double,
        temperatureK: Double
    ) async throws -> CoolPropEngineResult {
        CoolPropEngineResult(
            densityKilogramsPerCubicMetre: 1,
            dynamicViscosityPascalSeconds: 1,
            phaseIdentifier: "gas"
        )
    }

    func calculateDryCarbonDioxideMixture(
        pressurePa: Double,
        temperatureK: Double,
        composition: [MixtureComponent]
    ) async throws -> CoolPropBinaryEngineResult {
        CoolPropBinaryEngineResult(
            densityKilogramsPerCubicMetre: 1,
            phaseIdentifier: "gas"
        )
    }

    func pureCarbonDioxideSaturationLimits() async throws -> CoolPropSaturationLimits {
        CoolPropSaturationLimits(
            triplePointTemperatureK: 216.592,
            criticalPointTemperatureK: 304.1282,
            criticalPointPressurePa: 7_377_300
        )
    }

    func pureCarbonDioxideSaturationPressure(temperatureK: Double) async throws -> Double {
        1_000_000
    }
}
