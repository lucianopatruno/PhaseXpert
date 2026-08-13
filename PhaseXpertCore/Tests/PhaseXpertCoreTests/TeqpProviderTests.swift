import XCTest
@testable import PhaseXpertCore

final class TeqpProviderTests: XCTestCase {
    private struct MockEngine: TeqpEngine {
        let isAvailable = true
        let libraryVersion = "teqp-test"
        var result = TeqpEngineResult(
            densityKilogramsPerCubicMetre: 801.2,
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
    }

    func testUnavailableEngineDoesNotClaimCapabilities() {
        let provider = TeqpProvider(engine: UnavailableTeqpEngine())

        XCTAssertEqual(provider.descriptor.id, "teqp-pure-co2-experimental")
        XCTAssertEqual(provider.descriptor.name, "Advanced Phase & Mixture Model (teqp)")
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
            ["teqp-v0.23.1-pure-co2-span-wagner-density"]
        )
        XCTAssertTrue(TeqpFormulationCatalog.pureCarbonDioxide.supportsPhaseEnvelope)
        XCTAssertEqual(
            TeqpFormulationCatalog.productionSupportedComponents,
            [.carbonDioxide]
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
        XCTAssertFalse(
            TeqpFormulationCatalog.productionFormulations.contains {
                $0.components.contains(.nitrogen)
            }
        )
        XCTAssertFalse(
            TeqpFormulationCatalog.productionFormulations.contains {
                !$0.components.isSubset(of: [.carbonDioxide])
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
                    "The experimental teqp provider supports only exactly 100 mol% CO₂. No CoolProp fallback is used."
                )
            )
        })
    }

    func testCO2N2RemainsValidationGatedDespiteNativeDiagnosticBridge() async {
        let provider = TeqpProvider(engine: FailingEngine())
        let descriptor = provider.descriptor
        XCTAssertEqual(descriptor.supportedComponents, [.carbonDioxide])
        XCTAssertFalse(descriptor.supportedComponents.contains(.nitrogen))
        XCTAssertTrue(
            descriptor.limitations.contains {
                $0.contains("CO₂ mixtures, including CO₂+N₂, are unsupported")
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
                    "The experimental teqp provider supports only exactly 100 mol% CO₂. No CoolProp fallback is used."
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
