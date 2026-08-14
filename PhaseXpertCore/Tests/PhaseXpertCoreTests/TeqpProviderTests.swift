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
                phaseIdentifier: "gas",
                formulationID: TeqpFormulationCatalog.co2MethaneEOSCGGasDensity.id
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
                    && $0.supportsPhaseEnvelope
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
                    "Advanced CCS Properties supports pure CO₂ plus narrow CO₂+H₂ and CO₂+CH₄ homogeneous gas-density validation domains only. No CoolProp fallback is used."
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
                    "Advanced CCS Properties supports pure CO₂ plus narrow CO₂+H₂ and CO₂+CH₄ homogeneous gas-density validation domains only. No CoolProp fallback is used."
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
                .contains("no CoolProp fallback") == true
        )
        XCTAssertTrue(
            response.warnings.contains {
                $0.contains("LIMITED PASS")
            }
        )
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
                    "Advanced CCS Properties supports pure CO₂ plus narrow CO₂+H₂ and CO₂+CH₄ homogeneous gas-density validation domains only. No CoolProp fallback is used."
                )
            )
        })
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
                .contains("no CoolProp fallback") == true
        )
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
                    "CO₂+CH₄ teqp density pressure is outside the validated gas range."
                )
            )
        })
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
                    "The experimental teqp provider supports phase-envelope generation only for exactly 100 mol% CO₂. No CoolProp fallback is used."
                )
            )
        })
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
