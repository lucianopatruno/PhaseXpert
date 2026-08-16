import XCTest
@testable import PhaseXpertCore

final class TeqpProviderTests: XCTestCase {
    private struct MockEngine: TeqpEngine {
        let isAvailable = true
        let libraryVersion = "teqp-test"
        var result = TeqpEngineResult(
            densityKilogramsPerCubicMetre: 801.2,
            isochoricHeatCapacityJoulesPerKilogramKelvin: 850.1,
            isobaricHeatCapacityJoulesPerKilogramKelvin: 1_250.2,
            heatCapacityRatio: 1.47,
            speedOfSoundMetresPerSecond: 410.3,
            densityRootCount: 1,
            phaseIdentifier: "supercritical"
        )
        var methanePhaseIdentifier = "gas"

        func calculatePureCarbonDioxide(
            pressurePa: Double,
            temperatureK: Double
        ) async throws -> TeqpEngineResult {
            result
        }

        func pureCarbonDioxideSaturation(
            temperatureK: Double
        ) async throws -> TeqpSaturationPoint {
            TeqpSaturationPoint(
                temperatureK: temperatureK,
                pressurePa: temperatureK * 1_000,
                liquidDensityKilogramsPerCubicMetre: 1_000 - temperatureK,
                vaporDensityKilogramsPerCubicMetre: temperatureK / 10
            )
        }

        func calculateCarbonDioxideHydrogenGasDensity(
            pressurePa: Double,
            temperatureK: Double,
            hydrogenMoleFraction: Double
        ) async throws -> TeqpMixtureDensityResult {
            TeqpMixtureDensityResult(
                densityKilogramsPerCubicMetre: 11.42,
                molarDensityMolesPerCubicMetre: 270.2,
                densityRootCount: 1,
                phaseIdentifier: "gas",
                formulationID: TeqpFormulationCatalog.co2HydrogenEOSCGGasDensity.id
            )
        }

        func calculateCarbonDioxideMethaneGasDensity(
            pressurePa: Double,
            temperatureK: Double,
            methaneMoleFraction: Double
        ) async throws -> TeqpMixtureDensityResult {
            TeqpMixtureDensityResult(
                densityKilogramsPerCubicMetre: 117.93,
                molarDensityMolesPerCubicMetre: 2_852.4,
                densityRootCount: 1,
                phaseIdentifier: methanePhaseIdentifier,
                formulationID: TeqpFormulationCatalog.co2MethaneEOSCGGasDensity.id
            )
        }

        func calculateBinaryVLE(
            formulation: TeqpBinaryFormulationID,
            temperatureK: Double,
            liquidComponent2MoleFraction: Double,
            initialGuess: TeqpBinaryVLEInitialGuess?
        ) async throws -> TeqpBinaryVLEResult {
            TeqpBinaryVLEResult(
                converged: true,
                iterationCount: 6,
                returnCode: 1,
                pressurePa: 6_000_000
                    + 20_000_000 * liquidComponent2MoleFraction
                    + 100_000 * (temperatureK - 293.13),
                liquidMolarDensityMolesPerCubicMetre: 20_000,
                vaporMolarDensityMolesPerCubicMetre: 1_000,
                liquidComponent2MoleFraction: liquidComponent2MoleFraction,
                vaporComponent2MoleFraction: liquidComponent2MoleFraction * 2,
                pressureResidualPa: 0,
                component1ChemicalPotentialResidual: 0,
                component2ChemicalPotentialResidual: 0
            )
        }

        func calculateBinaryThermodynamicState(
            formulation: TeqpBinaryFormulationID,
            pressurePa: Double,
            temperatureK: Double,
            component2MoleFraction: Double
        ) async throws -> TeqpMixtureThermodynamicResult {
            TeqpMixtureThermodynamicResult(
                densityKilogramsPerCubicMetre: formulation == .eoscgCarbonDioxideMethane
                    ? 118.5
                    : 11.7,
                molarDensityMolesPerCubicMetre: formulation == .eoscgCarbonDioxideMethane
                    ? 2_865
                    : 276,
                pressurePa: pressurePa,
                pressureDerivativeWithRespectToMolarDensityJoulesPerMole: 2_600,
                pressureDerivativeWithRespectToTemperaturePascalsPerKelvin: 9_500,
                isochoricHeatCapacityJoulesPerKilogramKelvin: 770,
                isobaricHeatCapacityJoulesPerKilogramKelvin: 1_040,
                heatCapacityRatio: 1.350_649,
                speedOfSoundMetresPerSecond: 285,
                speedOfSoundSquaredMetresSquaredPerSecondSquared: 81_225,
                minimumStabilityEigenvalue: 1.2,
                densityRootCount: 1,
                converged: true,
                phaseIdentifier: "gas",
                formulationID: formulation == .eoscgCarbonDioxideMethane
                    ? TeqpFormulationCatalog.co2MethaneEOSCGDiagnostic.id
                    : TeqpFormulationCatalog.co2HydrogenEOSCGDiagnostic.id
            )
        }

        func calculateBinaryCriticalPoint(
            formulation: TeqpBinaryFormulationID,
            component2MoleFraction: Double
        ) async throws -> TeqpBinaryCriticalResult {
            TeqpBinaryCriticalResult(
                converged: true,
                iterationCount: 8,
                temperatureK: 306.9,
                pressurePa: 7_860_000,
                molarDensityMolesPerCubicMetre: 10_300,
                densityKilogramsPerCubicMetre: 425,
                component2MoleFraction: component2MoleFraction,
                minimumStabilityEigenvalue: 4e-7,
                thirdOrderResidual: 2e-9,
                formulationID: formulation == .eoscgCarbonDioxideMethane
                    ? TeqpFormulationCatalog.co2MethaneEOSCGDiagnostic.id
                    : TeqpFormulationCatalog.co2HydrogenEOSCGDiagnostic.id
            )
        }
    }

    private struct FailingEngine: TeqpEngine {
        let isAvailable = true
        let libraryVersion = "teqp-test"

        func calculatePureCarbonDioxide(
            pressurePa: Double,
            temperatureK: Double
        ) async throws -> TeqpEngineResult {
            throw ProviderError.malformedResponse(
                "Engine should not be called for unsupported mixtures."
            )
        }

        func pureCarbonDioxideSaturation(
            temperatureK: Double
        ) async throws -> TeqpSaturationPoint {
            throw ProviderError.malformedResponse(
                "Engine should not be called for unsupported mixtures."
            )
        }

        func calculateCarbonDioxideHydrogenGasDensity(
            pressurePa: Double,
            temperatureK: Double,
            hydrogenMoleFraction: Double
        ) async throws -> TeqpMixtureDensityResult {
            throw ProviderError.malformedResponse(
                "Engine should not be called for unsupported mixtures."
            )
        }

        func calculateCarbonDioxideMethaneGasDensity(
            pressurePa: Double,
            temperatureK: Double,
            methaneMoleFraction: Double
        ) async throws -> TeqpMixtureDensityResult {
            throw ProviderError.malformedResponse(
                "Engine should not be called for unsupported mixtures."
            )
        }

        func calculateBinaryVLE(
            formulation: TeqpBinaryFormulationID,
            temperatureK: Double,
            liquidComponent2MoleFraction: Double,
            initialGuess: TeqpBinaryVLEInitialGuess?
        ) async throws -> TeqpBinaryVLEResult {
            throw ProviderError.malformedResponse(
                "Engine should not be called for unsupported mixtures."
            )
        }

        func calculateBinaryThermodynamicState(
            formulation: TeqpBinaryFormulationID,
            pressurePa: Double,
            temperatureK: Double,
            component2MoleFraction: Double
        ) async throws -> TeqpMixtureThermodynamicResult {
            throw ProviderError.malformedResponse(
                "Engine should not be called for unsupported mixtures."
            )
        }

        func calculateBinaryCriticalPoint(
            formulation: TeqpBinaryFormulationID,
            component2MoleFraction: Double
        ) async throws -> TeqpBinaryCriticalResult {
            throw ProviderError.malformedResponse(
                "Engine should not be called for unsupported mixtures."
            )
        }
    }

    func testUnavailableEngineDoesNotClaimCapabilities() {
        let provider = TeqpProvider(engine: UnavailableTeqpEngine())

        XCTAssertEqual(provider.descriptor.id, "teqp-pure-co2-experimental")
        XCTAssertEqual(provider.descriptor.name, "Advanced CO₂ & Phase Model (teqp)")
        XCTAssertEqual(provider.descriptor.availability, .unavailable)
        XCTAssertTrue(provider.descriptor.supportedComponents.isEmpty)
        XCTAssertTrue(provider.descriptor.supportedProperties.isEmpty)
    }

    func testFormulationCatalogSeparatesProductionAndResearchModels() {
        XCTAssertEqual(TeqpFormulationCatalog.teqpVersion, "v0.23.1")
        XCTAssertEqual(
            TeqpFormulationCatalog.teqpCommit,
            "a68eb9cabf47af2c4aba0d272ac10fbca4c10eca"
        )
        XCTAssertEqual(
            TeqpFormulationCatalog.surveyedBinaryImpurities,
            [.nitrogen, .oxygen, .argon, .hydrogen, .methane]
        )
        XCTAssertEqual(
            TeqpFormulationCatalog.productionFormulations.map(\.id),
            [
                "teqp-v0.23.1-pure-co2-span-wagner-density",
                "teqp-v0.23.1-eoscg2021-co2-h2-gas-density-souissi2017",
                "teqp-v0.23.1-eoscg2021-co2-ch4-gas-density-ghafri2016"
            ]
        )
        XCTAssertTrue(TeqpFormulationCatalog.pureCarbonDioxide.supportsPhaseEnvelope)
        XCTAssertTrue(TeqpFormulationCatalog.co2MethaneEOSCGGasDensity.supportsPhaseEnvelope)
        XCTAssertTrue(TeqpFormulationCatalog.co2MethaneEOSCGVLE.supportsContinuousEnvelope)
        XCTAssertFalse(TeqpFormulationCatalog.co2MethaneEOSCGVLE.supportsCriticalPoint)
        XCTAssertTrue(
            TeqpFormulationCatalog.co2MethaneEOSCGVLE
                .accuracySummary
                .contains("pressure AARD 0.608899%")
        )
        XCTAssertEqual(
            TeqpFormulationCatalog.productionSupportedComponents,
            [.carbonDioxide, .methane, .hydrogen]
        )
        XCTAssertTrue(
            TeqpFormulationCatalog.productionSupportedProperties
                .isSuperset(of: [
                    .isobaricHeatCapacity,
                    .isochoricHeatCapacity,
                    .heatCapacityRatio,
                    .speedOfSound
                ])
        )
        XCTAssertEqual(
            TeqpFormulationCatalog.co2NitrogenGernertGergDiagnostic.status,
            .failedValidation
        )
        XCTAssertEqual(
            TeqpFormulationCatalog.co2OxygenGernertDiagnostic.status,
            .failedValidation
        )
        XCTAssertEqual(
            TeqpFormulationCatalog.co2ArgonGernertDiagnostic.status,
            .failedValidation
        )
        XCTAssertEqual(
            TeqpFormulationCatalog.co2OxygenEOSCGDiagnostic.status,
            .failedValidation
        )
        XCTAssertEqual(
            TeqpFormulationCatalog.co2ArgonEOSCGDiagnostic.status,
            .failedValidation
        )
        XCTAssertEqual(
            TeqpFormulationCatalog.co2HydrogenEOSCGDiagnostic.status,
            .surveyPending
        )
        XCTAssertEqual(
            TeqpFormulationCatalog.co2MethaneEOSCGDiagnostic.status,
            .surveyPending
        )
        XCTAssertTrue(
            TeqpFormulationCatalog.researchFormulations.contains {
                $0.family == .eosCG2021
            }
        )
        XCTAssertFalse(
            TeqpFormulationCatalog.productionFormulations.contains {
                $0.components.contains(.nitrogen)
            }
        )
        XCTAssertFalse(
            TeqpFormulationCatalog.productionFormulations.contains {
                $0.components.contains(.oxygen)
                    || $0.components.contains(.argon)
            }
        )
        XCTAssertTrue(
            TeqpFormulationCatalog.productionFormulations.contains {
                $0.components == [.carbonDioxide, .hydrogen]
                    && $0.propertyCapabilities.contains {
                        $0.property == .density
                            && $0.phaseDomain == .homogeneousGas
                    }
            }
        )
        XCTAssertTrue(
            TeqpFormulationCatalog.productionFormulations.contains {
                $0.components == [.carbonDioxide, .methane]
                    && $0.propertyCapabilities.contains {
                        $0.property == .density
                            && $0.phaseDomain == .homogeneousGas
                    }
            }
        )
        XCTAssertFalse(
            TeqpFormulationCatalog.productionFormulations.contains {
                $0.components.contains(.hydrogen)
                    && $0.supportsPhaseEnvelope
            }
        )
        XCTAssertFalse(
            TeqpFormulationCatalog.productionFormulations.contains {
                $0.components.contains(.methane)
                    && $0.supportedProperties.contains(.speedOfSound)
            }
        )
    }

    func testPureCO2DensityAndDerivedValuesAreTraceable() async throws {
        let provider = TeqpProvider(engine: MockEngine())
        let response = try await provider.calculate(
            CalculationRequest(
                modelID: provider.descriptor.id,
                pressurePa: 15_000_000,
                temperatureK: 293.15,
                composition: [.init(component: .carbonDioxide, moleFraction: 1)],
                requestedProperties: [
                    .density,
                    .molarMass,
                    .compressibilityFactor,
                    .specificVolume
                ],
                clientVersion: "test"
            )
        )

        XCTAssertEqual(response.model.availability, .preliminary)
        XCTAssertEqual(response.phase, .supercritical)
        XCTAssertTrue(response.isScientificResult)
        XCTAssertTrue(response.warnings.contains { $0.contains("EXPERIMENTAL teqp") })
        XCTAssertEqual(
            response.properties.first { $0.property == .density }?.value,
            801.2
        )
        XCTAssertEqual(
            response.properties.first { $0.property == .molarMass }?.status,
            .calculated
        )
        XCTAssertTrue(response.solver.method.contains("stable-branch selection"))
    }

    func testDiagnosticBinaryThermodynamicEngineContractReturnsFiniteValues() async throws {
        let engine = MockEngine()

        let methane = try await engine.calculateBinaryThermodynamicState(
            formulation: .eoscgCarbonDioxideMethane,
            pressurePa: 5_000_000,
            temperatureK: 301.14,
            component2MoleFraction: 0.05
        )
        XCTAssertTrue(methane.converged)
        XCTAssertEqual(
            methane.formulationID,
            TeqpFormulationCatalog.co2MethaneEOSCGDiagnostic.id
        )
        XCTAssertGreaterThan(
            methane.isochoricHeatCapacityJoulesPerKilogramKelvin,
            0
        )
        XCTAssertGreaterThan(
            methane.isobaricHeatCapacityJoulesPerKilogramKelvin,
            methane.isochoricHeatCapacityJoulesPerKilogramKelvin
        )
        XCTAssertGreaterThan(methane.speedOfSoundMetresPerSecond, 0)
        XCTAssertGreaterThan(
            methane.pressureDerivativeWithRespectToMolarDensityJoulesPerMole,
            0
        )
        XCTAssertGreaterThan(methane.minimumStabilityEigenvalue, 0)

        let hydrogen = try await engine.calculateBinaryThermodynamicState(
            formulation: .eoscgCarbonDioxideHydrogen,
            pressurePa: 3_000_000,
            temperatureK: 293.15,
            component2MoleFraction: 0.05362
        )
        XCTAssertTrue(hydrogen.converged)
        XCTAssertEqual(
            hydrogen.formulationID,
            TeqpFormulationCatalog.co2HydrogenEOSCGDiagnostic.id
        )
        XCTAssertGreaterThan(hydrogen.speedOfSoundSquaredMetresSquaredPerSecondSquared, 0)
    }

    func testDiagnosticBinaryCriticalEngineContractReturnsFiniteResult() async throws {
        let result = try await MockEngine().calculateBinaryCriticalPoint(
            formulation: .eoscgCarbonDioxideMethane,
            component2MoleFraction: 0.05
        )

        XCTAssertTrue(result.converged)
        XCTAssertEqual(result.component2MoleFraction, 0.05)
        XCTAssertEqual(
            result.formulationID,
            TeqpFormulationCatalog.co2MethaneEOSCGDiagnostic.id
        )
        XCTAssertGreaterThan(result.temperatureK, 300)
        XCTAssertGreaterThan(result.pressurePa, 0)
        XCTAssertGreaterThan(result.densityKilogramsPerCubicMetre, 0)
    }

    func testViscosityIsExplicitlyUnavailableWithoutFallback() async throws {
        let provider = TeqpProvider(engine: MockEngine())
        let response = try await provider.calculate(
            CalculationRequest(
                modelID: provider.descriptor.id,
                pressurePa: 10_000_000,
                temperatureK: 313.15,
                composition: [.init(component: .carbonDioxide, moleFraction: 1)],
                requestedProperties: [.dynamicViscosity],
                clientVersion: "test"
            )
        )

        let viscosity = try XCTUnwrap(
            response.properties.first { $0.property == .dynamicViscosity }
        )
        XCTAssertNil(viscosity.value)
        XCTAssertEqual(viscosity.status, .unavailable)
        XCTAssertTrue(viscosity.message?.contains("no CoolProp fallback") == true)
    }

    func testPureCO2HeatCapacitiesAndSpeedOfSoundAreMapped() async throws {
        let provider = TeqpProvider(engine: MockEngine())
        let response = try await provider.calculate(
            CalculationRequest(
                modelID: provider.descriptor.id,
                pressurePa: 10_000_000,
                temperatureK: 313.15,
                composition: [.init(component: .carbonDioxide, moleFraction: 1)],
                requestedProperties: [
                    .isobaricHeatCapacity,
                    .isochoricHeatCapacity,
                    .heatCapacityRatio,
                    .speedOfSound
                ],
                clientVersion: "test"
            )
        )

        XCTAssertEqual(
            response.properties.first { $0.property == .isobaricHeatCapacity }?.value,
            1_250.2
        )
        XCTAssertEqual(
            response.properties.first { $0.property == .isochoricHeatCapacity }?.value,
            850.1
        )
        XCTAssertEqual(
            response.properties.first { $0.property == .heatCapacityRatio }?.value,
            1.47
        )
        XCTAssertEqual(
            response.properties.first { $0.property == .speedOfSound }?.value,
            410.3
        )
    }

    func testPureCO2ReferenceStatePropertiesRemainUnavailable() async throws {
        let provider = TeqpProvider(engine: MockEngine())
        let response = try await provider.calculate(
            CalculationRequest(
                modelID: provider.descriptor.id,
                pressurePa: 10_000_000,
                temperatureK: 313.15,
                composition: [.init(component: .carbonDioxide, moleFraction: 1)],
                requestedProperties: [
                    .enthalpy,
                    .entropy,
                    .internalEnergy
                ],
                clientVersion: "test"
            )
        )

        XCTAssertEqual(response.properties.count, 3)
        XCTAssertTrue(response.properties.allSatisfy { $0.status == .unavailable })
    }

    func testUnsupportedMixtureReturnsProviderDomainIssueAndDoesNotFallback() async {
        let provider = TeqpProvider(engine: MockEngine())
        let composition = [
            MixtureComponent(component: .carbonDioxide, moleFraction: 0.97),
            MixtureComponent(component: .nitrogen, moleFraction: 0.03)
        ]

        let issues = provider.applicabilityIssues(for: composition)
        XCTAssertEqual(issues.first?.code, .componentOutsideModelRange)
        XCTAssertTrue(issues.first?.message.contains("not routed to CoolProp") == true)

        await XCTAssertThrowsErrorAsync({
            try await provider.calculate(
                CalculationRequest(
                    modelID: provider.descriptor.id,
                    pressurePa: 10_000_000,
                    temperatureK: 293.15,
                    composition: composition,
                    requestedProperties: [.density],
                    clientVersion: "test"
                )
            )
        }, { error in
            XCTAssertEqual(
                error as? ProviderError,
                .invalidRequest(
                    "Advanced CCS Properties supports pure CO₂ plus validation-gated CO₂+H₂ and CO₂+CH₄ homogeneous density domains only. No CoolProp fallback is used."
                )
            )
        })
    }

    func testCO2N2RemainsValidationGatedDespiteNativeDiagnosticBridge() async {
        let provider = TeqpProvider(engine: FailingEngine())
        let descriptor = provider.descriptor
        XCTAssertEqual(descriptor.supportedComponents, [.carbonDioxide, .methane, .hydrogen])
        XCTAssertFalse(descriptor.supportedComponents.contains(.nitrogen))
        XCTAssertTrue(
            descriptor.limitations.contains {
                $0.contains("N₂, O₂, Ar and simultaneous impurity mixtures remain unsupported")
            }
        )

        await XCTAssertThrowsErrorAsync({
            try await provider.calculate(
                CalculationRequest(
                    modelID: descriptor.id,
                    pressurePa: 12_000_000,
                    temperatureK: 303.15,
                    composition: [
                        .init(component: .carbonDioxide, moleFraction: 0.9585),
                        .init(component: .nitrogen, moleFraction: 0.0415)
                    ],
                    requestedProperties: [.density],
                    clientVersion: "test"
                )
            )
        }, { error in
            XCTAssertEqual(
                error as? ProviderError,
                .invalidRequest(
                    "Advanced CCS Properties supports pure CO₂ plus validation-gated CO₂+H₂ and CO₂+CH₄ homogeneous density domains only. No CoolProp fallback is used."
                )
            )
        })
    }

    func testHydrogenGasDensityLimitedDomainIsCalculatedWithoutFallback() async throws {
        let provider = TeqpProvider(engine: MockEngine())
        XCTAssertEqual(provider.descriptor.name, "Advanced CCS Properties")
        XCTAssertTrue(provider.descriptor.supportedComponents.contains(.hydrogen))

        let response = try await provider.calculate(
            CalculationRequest(
                modelID: provider.descriptor.id,
                pressurePa: 3_000_000,
                temperatureK: 293.15,
                composition: [
                    .init(component: .carbonDioxide, moleFraction: 0.94638),
                    .init(component: .hydrogen, moleFraction: 0.05362)
                ],
                requestedProperties: [
                    .density,
                    .molarMass,
                    .compressibilityFactor,
                    .specificVolume,
                    .isobaricHeatCapacity
                ],
                clientVersion: "test"
            )
        )

        XCTAssertEqual(response.phase, .gas)
        XCTAssertTrue(response.solver.method.contains("EOS-CG-2021 CO₂+H₂"))
        XCTAssertTrue(response.solver.method.contains("teqp v0.23.1"))
        XCTAssertTrue(response.solver.method.contains("EOSCGDirectTeqpDensityProbeResults"))
        XCTAssertEqual(
            response.properties.first { $0.property == .density }?.value,
            11.42
        )
        XCTAssertEqual(
            response.properties.first { $0.property == .isobaricHeatCapacity }?.status,
            .unavailable
        )
        XCTAssertTrue(
            response.properties.first { $0.property == .isobaricHeatCapacity }?
                .message?
                .contains("Souissi et al. 2017") == true
        )
        XCTAssertTrue(
            response.properties.first { $0.property == .isobaricHeatCapacity }?
                .message?
                .contains("CoolProp fallback") == true
        )
        XCTAssertTrue(
            response.warnings.contains {
                $0.contains("LIMITED PASS")
            }
        )
        XCTAssertTrue(response.warnings.contains { $0.contains("Phase equilibrium") })
        XCTAssertTrue(response.warnings.contains { $0.contains("No CoolProp fallback") })
    }

    func testHydrogenOutOfValidatedDomainIsRejectedBeforeEngineCall() async {
        let provider = TeqpProvider(engine: FailingEngine())

        await XCTAssertThrowsErrorAsync({
            try await provider.calculate(
                CalculationRequest(
                    modelID: provider.descriptor.id,
                    pressurePa: 3_000_000,
                    temperatureK: 293.15,
                    composition: [
                        .init(component: .carbonDioxide, moleFraction: 0.95),
                        .init(component: .hydrogen, moleFraction: 0.05)
                    ],
                    requestedProperties: [.density],
                    clientVersion: "test"
                )
            )
        }, { error in
            XCTAssertEqual(
                error as? ProviderError,
                .invalidRequest(
                    "Advanced CCS Properties supports pure CO₂ plus validation-gated CO₂+H₂ and CO₂+CH₄ homogeneous density domains only. No CoolProp fallback is used."
                )
            )
        })
    }

    func testHydrogenGasDensityDomainBoundariesAreExact() async throws {
        let provider = TeqpProvider(engine: MockEngine())
        let supportedStates = [
            (pressurePa: 513_520.0, temperatureK: 273.15),
            (pressurePa: 3_035_960.0, temperatureK: 273.15),
            (pressurePa: 503_160.0, temperatureK: 293.15),
            (pressurePa: 4_984_890.0, temperatureK: 293.15),
            (pressurePa: 549_210.0, temperatureK: 323.15),
            (pressurePa: 5_997_370.0, temperatureK: 323.15)
        ]

        for state in supportedStates {
            let response = try await provider.calculate(hydrogenRequest(
                pressurePa: state.pressurePa,
                temperatureK: state.temperatureK,
                hydrogenMoleFraction: 0.05362
            ))
            XCTAssertEqual(response.phase, .gas)
            XCTAssertEqual(
                response.properties.first { $0.property == .density }?.status,
                .calculated
            )
        }
    }

    func testHydrogenGasDensityRejectsOutsideExactDomain() async {
        let provider = TeqpProvider(engine: FailingEngine())
        let rejectedRequests = [
            (
                request: hydrogenRequest(
                    pressurePa: 513_519,
                    temperatureK: 273.15,
                    hydrogenMoleFraction: 0.05362
                ),
                message: "pressure is outside"
            ),
            (
                request: hydrogenRequest(
                    pressurePa: 3_035_961,
                    temperatureK: 273.15,
                    hydrogenMoleFraction: 0.05362
                ),
                message: "pressure is outside"
            ),
            (
                request: hydrogenRequest(
                    pressurePa: 3_000_000,
                    temperatureK: 293.18,
                    hydrogenMoleFraction: 0.05362
                ),
                message: "validated only at 273.15 K, 293.15 K or 323.15 K"
            ),
            (
                request: hydrogenRequest(
                    pressurePa: 3_000_000,
                    temperatureK: 293.15,
                    hydrogenMoleFraction: 0.054
                ),
                message: "Advanced CCS Properties supports pure CO₂ plus validation-gated CO₂+H₂ and CO₂+CH₄"
            )
        ]

        for rejected in rejectedRequests {
            await XCTAssertThrowsErrorAsync({
                try await provider.calculate(rejected.request)
            }, { error in
                guard case let ProviderError.invalidRequest(message) = error else {
                    return XCTFail("Expected invalidRequest, got \(error).")
                }
                XCTAssertTrue(message.contains(rejected.message), message)
            })
        }
    }

    func testMethaneGasDensityLimitedDomainIsCalculatedWithoutFallback() async throws {
        let provider = TeqpProvider(engine: MockEngine())
        XCTAssertTrue(provider.descriptor.supportedComponents.contains(.methane))

        let response = try await provider.calculate(
            CalculationRequest(
                modelID: provider.descriptor.id,
                pressurePa: 4_979_790,
                temperatureK: 301.147,
                composition: [
                    .init(component: .carbonDioxide, moleFraction: 0.95),
                    .init(component: .methane, moleFraction: 0.05)
                ],
                requestedProperties: [
                    .density,
                    .molarMass,
                    .specificVolume,
                    .speedOfSound
                ],
                clientVersion: "test"
            )
        )

        XCTAssertEqual(response.phase, .gas)
        XCTAssertTrue(response.solver.method.contains("EOS-CG-2021 CO₂+CH₄"))
        XCTAssertTrue(response.solver.method.contains("teqp v0.23.1"))
        XCTAssertTrue(response.solver.method.contains("MethaneDensityDomainExpansion2026-08-15"))
        XCTAssertEqual(
            response.properties.first { $0.property == .density }?.value,
            117.93
        )
        XCTAssertEqual(
            response.properties.first { $0.property == .speedOfSound }?.status,
            .unavailable
        )
        XCTAssertTrue(
            response.properties.first { $0.property == .speedOfSound }?
                .message?
                .contains("Ghafri et al. 2016") == true
        )
        XCTAssertTrue(
            response.properties.first { $0.property == .speedOfSound }?
                .message?
                .contains("CoolProp fallback") == true
        )
        XCTAssertTrue(response.warnings.contains { $0.contains("LIMITED PASS") })
        XCTAssertTrue(response.warnings.contains { $0.contains("Phase equilibrium") })
    }

    func testMethaneOutOfValidatedDomainIsRejectedBeforeEngineCall() async {
        let provider = TeqpProvider(engine: FailingEngine())

        await XCTAssertThrowsErrorAsync({
            try await provider.calculate(
                CalculationRequest(
                    modelID: provider.descriptor.id,
                    pressurePa: 8_000_000,
                    temperatureK: 301.14,
                    composition: [
                        .init(component: .carbonDioxide, moleFraction: 0.95),
                        .init(component: .methane, moleFraction: 0.05)
                    ],
                    requestedProperties: [.density],
                    clientVersion: "test"
                )
            )
        }, { error in
            XCTAssertEqual(
                error as? ProviderError,
                .invalidRequest(
                    "CO₂+CH₄ teqp density pressure is outside the validated range for this Ghafri et al. 2016 isotherm slice."
                )
            )
        })
    }

    func testMethaneGasDensityDomainBoundariesAreExact() async throws {
        let provider = TeqpProvider(engine: MockEngine())
        let supportedStates = [
            (pressurePa: 1_990_460.0, temperatureK: 301.133),
            (pressurePa: 6_976_000.0, temperatureK: 301.153),
            (pressurePa: 4_979_790.0, temperatureK: 301.14),
            (pressurePa: 7_971_800.0, temperatureK: 308.137),
            (pressurePa: 9_967_260.0, temperatureK: 308.177),
            (pressurePa: 7_973_280.0, temperatureK: 313.140),
            (pressurePa: 9_768_430.0, temperatureK: 313.182)
        ]

        for state in supportedStates {
            let response = try await provider.calculate(methaneRequest(
                pressurePa: state.pressurePa,
                temperatureK: state.temperatureK,
                methaneMoleFraction: 0.05
            ))
            XCTAssertEqual(response.phase, .gas)
            XCTAssertEqual(
                response.properties.first { $0.property == .density }?.status,
                .calculated
            )
        }
    }

    func testMethaneHighTemperatureSupercriticalSliceIsCalculatedWithoutFallback() async throws {
        let provider = TeqpProvider(
            engine: MockEngine(methanePhaseIdentifier: "supercritical")
        )

        let response = try await provider.calculate(methaneRequest(
            pressurePa: 8_970_000,
            temperatureK: 310.15,
            methaneMoleFraction: 0.05
        ))

        XCTAssertEqual(response.phase, .supercritical)
        XCTAssertEqual(
            response.properties.first { $0.property == .density }?.status,
            .calculated
        )
        XCTAssertTrue(
            response.warnings.contains {
                $0.contains("gas/supercritical T/P slices")
            }
        )
    }

    func testMethaneGasDensityRejectsOutsideExactDomain() async {
        let provider = TeqpProvider(engine: FailingEngine())
        let rejectedRequests = [
            (
                request: methaneRequest(
                    pressurePa: 1_990_459,
                    temperatureK: 301.14,
                    methaneMoleFraction: 0.05
                ),
                message: "pressure is outside"
            ),
            (
                request: methaneRequest(
                    pressurePa: 6_976_001,
                    temperatureK: 301.14,
                    methaneMoleFraction: 0.05
                ),
                message: "pressure is outside"
            ),
            (
                request: methaneRequest(
                    pressurePa: 4_000_000,
                    temperatureK: 301.132,
                    methaneMoleFraction: 0.05
                ),
                message: "validated only within"
            ),
            (
                request: methaneRequest(
                    pressurePa: 4_000_000,
                    temperatureK: 301.154,
                    methaneMoleFraction: 0.05
                ),
                message: "validated only within"
            ),
            (
                request: methaneRequest(
                    pressurePa: 9_967_261,
                    temperatureK: 308.15,
                    methaneMoleFraction: 0.05
                ),
                message: "pressure is outside"
            ),
            (
                request: methaneRequest(
                    pressurePa: 4_000_000,
                    temperatureK: 301.14,
                    methaneMoleFraction: 0.051
                ),
                message: "Advanced CCS Properties supports pure CO₂ plus validation-gated CO₂+H₂ and CO₂+CH₄"
            )
        ]

        for rejected in rejectedRequests {
            await XCTAssertThrowsErrorAsync({
                try await provider.calculate(rejected.request)
            }, { error in
                guard case let ProviderError.invalidRequest(message) = error else {
                    return XCTFail("Expected invalidRequest, got \(error).")
                }
                XCTAssertTrue(message.contains(rejected.message), message)
            })
        }
    }

    func testPureCO2PhaseEnvelopeUsesTeqpSaturation() async throws {
        let provider = TeqpProvider(engine: MockEngine())
        let response = try await provider.phaseEnvelope(
            PhaseEnvelopeRequest(
                modelID: provider.descriptor.id,
                composition: [.init(component: .carbonDioxide, moleFraction: 1)]
            )
        )

        XCTAssertTrue(response.isAvailable)
        XCTAssertEqual(response.boundaryKind, .pureFluidSaturation)
        XCTAssertEqual(response.points.count, 81)
        XCTAssertEqual(response.points.last?.branch, .critical)
        XCTAssertEqual(response.points.first?.branch, .bubble)
        XCTAssertEqual(response.solver?.converged, true)
        XCTAssertTrue(response.solver?.method.contains("teqp pure-CO₂ VLE") == true)
        XCTAssertTrue(
            response.warnings.contains {
                $0.contains("Impurity phase-envelope generation remains validation-gated")
            }
        )
    }

    func testTeqpPhaseEnvelopeRejectsUnsupportedMixturesWithoutFallback() async {
        let provider = TeqpProvider(engine: FailingEngine())

        await XCTAssertThrowsErrorAsync({
            try await provider.phaseEnvelope(
                PhaseEnvelopeRequest(
                    modelID: provider.descriptor.id,
                    composition: [
                        .init(component: .carbonDioxide, moleFraction: 0.97),
                        .init(component: .nitrogen, moleFraction: 0.03)
                    ]
                )
            )
        }, { error in
            XCTAssertEqual(
                error as? ProviderError,
                .invalidRequest(
                    "Advanced CCS Properties phase diagrams are available only for pure CO₂ or the validated CO₂+CH₄ VLE gate at xCH₄ = 0.05. H₂ phase envelopes remain unavailable and no CoolProp fallback is used."
                )
            )
        })
    }

    func testMethaneVLEPhaseClassificationReportsTwoPhaseWithoutDensity() async throws {
        let provider = TeqpProvider(engine: MockEngine())
        let response = try await provider.calculate(
            CalculationRequest(
                modelID: provider.descriptor.id,
                pressurePa: 7_000_000,
                temperatureK: 293.13,
                composition: [
                    .init(component: .carbonDioxide, moleFraction: 0.95),
                    .init(component: .methane, moleFraction: 0.05)
                ],
                requestedProperties: [.density, .molarMass],
                clientVersion: "test"
            )
        )

        XCTAssertEqual(response.phase, .twoPhase)
        XCTAssertEqual(
            response.properties.first(where: { $0.property == .density })?.status,
            .unavailable
        )
        XCTAssertTrue(
            response.solver.method.contains("CO₂+CH₄ binary VLE classification")
        )
        XCTAssertTrue(
            response.warnings.contains {
                $0.contains("Bulk density, phase fraction")
            }
        )
    }

    func testMethaneVLEPhaseClassificationReportsVaporDenseAndBoundaryStates() async throws {
        let provider = TeqpProvider(engine: MockEngine())
        let composition = [
            MixtureComponent(component: .carbonDioxide, moleFraction: 0.95),
            MixtureComponent(component: .methane, moleFraction: 0.05)
        ]

        let vapor = try await provider.calculate(
            CalculationRequest(
                modelID: provider.descriptor.id,
                pressurePa: 6_000_000,
                temperatureK: 293.13,
                composition: composition,
                requestedProperties: [.density],
                clientVersion: "test"
            )
        )
        XCTAssertEqual(vapor.phase, .gas)
        XCTAssertEqual(vapor.properties.first?.status, .unavailable)
        XCTAssertTrue(vapor.solver.method.contains("below the validated dew pressure"))

        let dense = try await provider.calculate(
            CalculationRequest(
                modelID: provider.descriptor.id,
                pressurePa: 7_500_000,
                temperatureK: 293.13,
                composition: composition,
                requestedProperties: [.density],
                clientVersion: "test"
            )
        )
        XCTAssertEqual(dense.phase, .dense)
        XCTAssertEqual(dense.properties.first?.status, .unavailable)
        XCTAssertTrue(dense.solver.method.contains("above the validated bubble pressure"))

        for boundaryPressure in [6_500_000.0, 7_000_000.0, 6_501_000.0, 6_499_000.0] {
            let boundary = try await provider.calculate(
                CalculationRequest(
                    modelID: provider.descriptor.id,
                    pressurePa: boundaryPressure,
                    temperatureK: 293.13,
                    composition: composition,
                    requestedProperties: [.density, .vapourFraction],
                    clientVersion: "test"
                )
            )
            XCTAssertEqual(boundary.phase, .twoPhase)
            XCTAssertEqual(
                boundary.properties.first { $0.property == .density }?.status,
                .unavailable
            )
            XCTAssertEqual(
                boundary.properties.first { $0.property == .vapourFraction }?.status,
                .unavailable
            )
            XCTAssertNil(boundary.properties.first { $0.property == .density }?.value)
            XCTAssertNil(
                boundary.properties.first { $0.property == .vapourFraction }?.value
            )
        }
    }

    func testMethaneVLEClassificationUsesContinuousProductionInterval() async throws {
        let provider = TeqpProvider(engine: MockEngine())
        let composition = [
            MixtureComponent(component: .carbonDioxide, moleFraction: 0.95),
            MixtureComponent(component: .methane, moleFraction: 0.05)
        ]
        let response = try await provider.calculate(
            CalculationRequest(
                modelID: provider.descriptor.id,
                pressurePa: 6_750_000,
                temperatureK: 295.636,
                composition: composition,
                requestedProperties: [.density, .isobaricHeatCapacity],
                clientVersion: "test"
            )
        )

        XCTAssertEqual(response.phase, .twoPhase)
        XCTAssertEqual(
            response.properties.first { $0.property == .density }?.status,
            .unavailable
        )
        XCTAssertEqual(
            response.properties.first { $0.property == .isobaricHeatCapacity }?.status,
            .unavailable
        )
        XCTAssertTrue(
            response.warnings.contains {
                $0.contains("from 293.13 K to 298.142 K")
            }
        )
        XCTAssertTrue(
            response.warnings.contains {
                $0.contains("experimentally validated Petropoulou")
            }
        )
    }

    func testMethaneVLEPhaseClassificationRejectsUnsupportedTemperatureAndComposition() async {
        let provider = TeqpProvider(engine: FailingEngine())

        await XCTAssertThrowsErrorAsync({
            try await provider.calculate(
                CalculationRequest(
                    modelID: provider.descriptor.id,
                    pressurePa: 6_600_000,
                    temperatureK: 273.13,
                    composition: [
                        .init(component: .carbonDioxide, moleFraction: 0.95),
                        .init(component: .methane, moleFraction: 0.05)
                    ],
                    requestedProperties: [.density],
                    clientVersion: "test"
                )
            )
        }, { error in
            guard case let ProviderError.invalidRequest(message) = error else {
                return XCTFail("Expected invalidRequest, got \(error).")
            }
            XCTAssertTrue(message.contains("Ghafri density slices"))
        XCTAssertTrue(message.contains("Petropoulou 2018 ordinary VLE temperature interval"))
        XCTAssertTrue(message.contains("293.13 K (19.98 °C)"))
        XCTAssertTrue(message.contains("298.142 K (24.99 °C)"))
        })

        await XCTAssertThrowsErrorAsync({
            try await provider.phaseEnvelope(
                PhaseEnvelopeRequest(
                    modelID: provider.descriptor.id,
                    composition: [
                        .init(component: .carbonDioxide, moleFraction: 0.96),
                        .init(component: .methane, moleFraction: 0.04)
                    ]
                )
            )
        }, { error in
            guard case let ProviderError.invalidRequest(message) = error else {
                return XCTFail("Expected invalidRequest, got \(error).")
            }
            XCTAssertTrue(
                message.contains("pure CO₂ or the validated CO₂+CH₄ VLE gate")
            )
        })
    }

    func testMethanePhaseEnvelopeUsesValidatedVLEGate() async throws {
        let provider = TeqpProvider(engine: MockEngine())
        let response = try await provider.phaseEnvelope(
            PhaseEnvelopeRequest(
                modelID: provider.descriptor.id,
                composition: [
                    .init(component: .carbonDioxide, moleFraction: 0.95),
                    .init(component: .methane, moleFraction: 0.05)
                ]
            )
        )

        XCTAssertTrue(response.isAvailable)
        XCTAssertEqual(response.boundaryKind, .mixtureEnvelope)
        XCTAssertEqual(response.points.count, 82)
        XCTAssertEqual(
            response.points.filter { $0.branch == .bubble }.count,
            41
        )
        XCTAssertEqual(
            response.points.filter { $0.branch == .dew }.count,
            41
        )
        XCTAssertTrue(
            response.points.contains {
                $0.branch == .bubble && abs($0.temperatureK - 293.13) <= 1e-6
            }
        )
        XCTAssertTrue(
            response.points.contains {
                $0.branch == .dew && abs($0.temperatureK - 298.142) <= 1e-6
            }
        )
        XCTAssertTrue(
            response.points.contains {
                abs($0.temperatureK - 295.636) <= 1e-6
            }
        )
        XCTAssertFalse(
            response.points.contains {
                abs($0.temperatureK - 303.145) <= 1e-6
            }
        )
        XCTAssertTrue(
            response.warnings.contains {
                $0.contains("Critical termination is not drawn")
            }
        )
        XCTAssertTrue(
            response.warnings.contains {
                $0.contains("production-enabled only")
            }
        )
        XCTAssertTrue(
            response.solver?.method.contains("production VLE interpolation") == true
        )
        XCTAssertTrue(
            response.solver?.method.contains("pressure AARD 0.608899%") == true
        )
        XCTAssertTrue(
            response.warnings.contains {
                $0.contains("only the anchor isotherms are direct experimental validation rows")
            }
        )
    }

    func testStableSelectedResultWithMultipleMathematicalRootsIsAccepted() async throws {
        let provider = TeqpProvider(
            engine: MockEngine(
                result: TeqpEngineResult(
                    densityKilogramsPerCubicMetre: 500,
                    densityRootCount: 2,
                    phaseIdentifier: "liquid"
                )
            )
        )

        let response = try await provider.calculate(
            CalculationRequest(
                modelID: provider.descriptor.id,
                pressurePa: 6_000_000,
                temperatureK: 280,
                composition: [.init(component: .carbonDioxide, moleFraction: 1)],
                requestedProperties: [.density],
                clientVersion: "test"
            )
        )

        XCTAssertEqual(response.phase, .liquid)
        XCTAssertEqual(response.properties.first { $0.property == .density }?.value, 500)
    }

    func testMissingDefensibleDensityRootFailsExplicitly() async {
        let provider = TeqpProvider(
            engine: MockEngine(
                result: TeqpEngineResult(
                    densityKilogramsPerCubicMetre: 500,
                    densityRootCount: 0,
                    phaseIdentifier: "unknown"
                )
            )
        )

        await XCTAssertThrowsErrorAsync({
            try await provider.calculate(
                CalculationRequest(
                    modelID: provider.descriptor.id,
                    pressurePa: 6_000_000,
                    temperatureK: 280,
                    composition: [.init(component: .carbonDioxide, moleFraction: 1)],
                    requestedProperties: [.density],
                    clientVersion: "test"
                )
            )
        }, { error in
            XCTAssertEqual(
                error as? ProviderError,
                .malformedResponse("teqp did not return a defensible density root.")
            )
        })
    }

    func testProductionRegistryKeepsCoolPropDefaultAndIncludesTeqpDescriptor() {
        let registry = ProviderRegistry()

        XCTAssertEqual(registry.providers.first?.descriptor.id, "coolprop-heos")
        XCTAssertTrue(registry.descriptors.contains { $0.id == "teqp-pure-co2-experimental" })
        XCTAssertNil(registry.provider(id: "ife-model"))
    }

    func testHydrogenGuidanceAdvertisesOnlyAcceptedProductionGate() async throws {
        let provider = TeqpProvider(engine: MockEngine())
        let composition = [
            MixtureComponent(component: .carbonDioxide, moleFraction: 0.94638),
            MixtureComponent(component: .hydrogen, moleFraction: 0.05362)
        ]

        let guidance = try XCTUnwrap(provider.operatingRangeGuidance(
            for: OperatingGuidanceContext(
                pressurePa: 2_000_000,
                temperatureK: 293.15,
                composition: composition,
                requestedProperties: [.density, .speedOfSound]
            )
        ))

        XCTAssertTrue(guidance.summary.contains {
            $0.title == "H₂ validated composition" && $0.detail == "53620 ppm"
        })
        XCTAssertTrue(guidance.summary.contains {
            $0.title == "Validated temperature" && $0.detail.contains("0 °C, 20 °C or 50 °C")
        })
        XCTAssertTrue(guidance.summary.contains {
            $0.title == "Validated pressure" && $0.detail == "5.0–49.8 bar(a)"
        })
        XCTAssertTrue(guidance.phaseDiagram.contains {
            $0.detail == "Phase diagram not yet validated for CO₂+H₂."
        })
        XCTAssertTrue(guidance.propertyAvailability.contains {
            $0.title == "Cp/Cv/speed"
                && $0.detail.contains("not production-validated for CO₂+H₂")
        })

        let acceptedTemperatures = [273.15, 293.15, 323.15]
        for temperature in acceptedTemperatures {
            let capability = try XCTUnwrap(
                TeqpFormulationCatalog.co2HydrogenEOSCGGasDensity
                    .propertyCapabilities
                    .first?
                    .isothermPressureLimits
                    .first(where: { $0.temperatureK == temperature })
            )
            let response = try await provider.calculate(hydrogenRequest(
                pressurePa: 0.5 * (capability.minimumPressurePa + capability.maximumPressurePa),
                temperatureK: temperature,
                hydrogenMoleFraction: 0.05362
            ))
            XCTAssertEqual(response.properties.first { $0.property == .density }?.status, .calculated)
        }
    }

    func testHydrogenGuidancePressureRangeUpdatesForEachValidatedIsotherm() async throws {
        let provider = TeqpProvider(engine: MockEngine())
        let composition = hydrogenComposition(hydrogenMoleFraction: 0.05362)
        let expectedPressureRanges: [(temperatureK: Double, detail: String)] = [
            (273.15, "5.1–30.4 bar(a)"),
            (293.15, "5.0–49.8 bar(a)"),
            (323.15, "5.5–60.0 bar(a)")
        ]

        for expected in expectedPressureRanges {
            let capability = try XCTUnwrap(
                TeqpFormulationCatalog.co2HydrogenEOSCGGasDensity
                    .propertyCapabilities
                    .first?
                    .isothermPressureLimits
                    .first(where: { $0.temperatureK == expected.temperatureK })
            )
            let pressurePa = 0.5 * (capability.minimumPressurePa + capability.maximumPressurePa)
            let guidance = try XCTUnwrap(provider.operatingRangeGuidance(
                for: OperatingGuidanceContext(
                    pressurePa: pressurePa,
                    temperatureK: expected.temperatureK,
                    composition: composition,
                    requestedProperties: [.density]
                )
            ))

            XCTAssertTrue(guidance.summary.contains {
                $0.title == "Validated pressure" && $0.detail == expected.detail
            }, "Missing \(expected.detail) for \(expected.temperatureK) K")
            XCTAssertFalse(guidance.currentInputIssues.contains {
                $0.title == "Pressure outside validated range"
            })

            let response = try await provider.calculate(hydrogenRequest(
                pressurePa: pressurePa,
                temperatureK: expected.temperatureK,
                hydrogenMoleFraction: 0.05362
            ))
            XCTAssertEqual(response.properties.first { $0.property == .density }?.status, .calculated)
        }
    }

    func testHydrogenGuidanceFlagsPressureOutsideResolvedIsothermRange() async throws {
        let provider = TeqpProvider(engine: FailingEngine())
        let capability = try XCTUnwrap(
            TeqpFormulationCatalog.co2HydrogenEOSCGGasDensity
                .propertyCapabilities
                .first?
                .isothermPressureLimits
                .first(where: { $0.temperatureK == 293.15 })
        )
        let pressurePa = capability.maximumPressurePa + 100_000

        let guidance = try XCTUnwrap(provider.operatingRangeGuidance(
            for: OperatingGuidanceContext(
                pressurePa: pressurePa,
                temperatureK: 293.15,
                composition: hydrogenComposition(hydrogenMoleFraction: 0.05362),
                requestedProperties: [.density]
            )
        ))

        XCTAssertTrue(guidance.summary.contains {
            $0.title == "Validated pressure" && $0.detail == "5.0–49.8 bar(a)"
        })
        XCTAssertTrue(guidance.currentInputIssues.contains {
            $0.title == "Pressure outside validated range"
                && $0.detail.contains("50.8 bar(a)")
                && $0.detail.contains("5.0–49.8 bar(a)")
        })

        await XCTAssertThrowsErrorAsync({
            try await provider.calculate(hydrogenRequest(
                pressurePa: pressurePa,
                temperatureK: 293.15,
                hydrogenMoleFraction: 0.05362
            ))
        }, { error in
            XCTAssertEqual(
                error as? ProviderError,
                .invalidRequest(
                    "CO₂+H₂ teqp density pressure is outside the validated gas range for this isotherm."
                )
            )
        })
    }

    func testHydrogenGuidanceFlagsUnsupportedTemperatureBeforeCalculation() {
        let provider = TeqpProvider(engine: MockEngine())
        let guidance = provider.operatingRangeGuidance(
            for: OperatingGuidanceContext(
                pressurePa: 2_000_000,
                temperatureK: 298.15,
                composition: [
                    .init(component: .carbonDioxide, moleFraction: 0.94638),
                    .init(component: .hydrogen, moleFraction: 0.05362)
                ]
            )
        )

        XCTAssertTrue(guidance?.currentInputIssues.contains {
            $0.title == "Temperature outside validation set"
                && $0.detail.contains("25 °C is outside")
        } == true)
        XCTAssertFalse(guidance?.summary.contains { $0.title == "Validated pressure" } == true)
    }

    func testMethaneGuidanceMatchesDensityAndPhaseEnvelopeGates() async throws {
        let provider = TeqpProvider(engine: MockEngine())
        let composition = [
            MixtureComponent(component: .carbonDioxide, moleFraction: 0.95),
            MixtureComponent(component: .methane, moleFraction: 0.05)
        ]

        let densityGuidance = try XCTUnwrap(provider.operatingRangeGuidance(
            for: OperatingGuidanceContext(
                pressurePa: 8_500_000,
                temperatureK: 310.15,
                composition: composition,
                requestedProperties: [.density, .isobaricHeatCapacity]
            )
        ))

        XCTAssertTrue(densityGuidance.summary.contains {
            $0.title == "CH₄ validated composition" && $0.detail == "50000 ppm"
        })
        XCTAssertTrue(densityGuidance.summary.contains {
            $0.title == "Validated density pressure" && $0.detail == "79.7–99.7 bar(a)"
        })
        XCTAssertTrue(densityGuidance.propertyAvailability.contains {
            $0.title == "Cp/Cv/speed"
                && $0.detail.contains("not production-validated for CO₂+CH₄")
        })
        XCTAssertTrue(densityGuidance.phaseDiagram.contains {
            $0.detail.contains("19.98 °C to 24.99 °C")
                && $0.detail.contains("no validated critical marker")
        })

        let densityResponse = try await provider.calculate(methaneRequest(
            pressurePa: 8_500_000,
            temperatureK: 310.15,
            methaneMoleFraction: 0.05
        ))
        XCTAssertEqual(densityResponse.properties.first { $0.property == .density }?.status, .calculated)

        let envelope = try await provider.phaseEnvelope(
            PhaseEnvelopeRequest(
                modelID: provider.descriptor.id,
                composition: composition
            )
        )
        XCTAssertTrue(envelope.isAvailable)
        XCTAssertEqual(envelope.boundaryKind, .mixtureEnvelope)
        XCTAssertEqual(envelope.points.count, 82)
    }

    func testMethaneGuidanceFlagsUnsupportedCompositionBeforeCalculation() {
        let provider = TeqpProvider(engine: MockEngine())
        let guidance = provider.operatingRangeGuidance(
            for: OperatingGuidanceContext(
                pressurePa: 8_500_000,
                temperatureK: 310.15,
                composition: [
                    .init(component: .carbonDioxide, moleFraction: 0.948),
                    .init(component: .methane, moleFraction: 0.052)
                ]
            )
        )

        XCTAssertTrue(guidance?.currentInputIssues.contains {
            $0.title == "Composition outside validated value"
                && $0.detail.contains("Entered 52000 ppm CH₄")
                && $0.detail.contains("50000 ppm")
        } == true)
        XCTAssertEqual(guidance?.suggestions.first?.label, "Use 50000 ppm CH₄")
    }

    private func hydrogenRequest(
        pressurePa: Double,
        temperatureK: Double,
        hydrogenMoleFraction: Double
    ) -> CalculationRequest {
        CalculationRequest(
            modelID: "teqp-pure-co2-experimental",
            pressurePa: pressurePa,
            temperatureK: temperatureK,
            composition: [
                .init(component: .carbonDioxide, moleFraction: 1 - hydrogenMoleFraction),
                .init(component: .hydrogen, moleFraction: hydrogenMoleFraction)
            ],
            requestedProperties: [.density],
            clientVersion: "test"
        )
    }

    private func hydrogenComposition(
        hydrogenMoleFraction: Double
    ) -> [MixtureComponent] {
        [
            .init(component: .carbonDioxide, moleFraction: 1 - hydrogenMoleFraction),
            .init(component: .hydrogen, moleFraction: hydrogenMoleFraction)
        ]
    }

    private func methaneRequest(
        pressurePa: Double,
        temperatureK: Double,
        methaneMoleFraction: Double
    ) -> CalculationRequest {
        CalculationRequest(
            modelID: "teqp-pure-co2-experimental",
            pressurePa: pressurePa,
            temperatureK: temperatureK,
            composition: [
                .init(component: .carbonDioxide, moleFraction: 1 - methaneMoleFraction),
                .init(component: .methane, moleFraction: methaneMoleFraction)
            ],
            requestedProperties: [.density],
            clientVersion: "test"
        )
    }
}

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: () async throws -> T,
    _ errorHandler: (Error) -> Void = { _ in },
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected expression to throw.", file: file, line: line)
    } catch {
        errorHandler(error)
    }
}
