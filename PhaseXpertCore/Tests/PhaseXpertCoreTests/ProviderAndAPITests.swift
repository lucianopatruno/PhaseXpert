import XCTest
@testable import PhaseXpertCore

final class ProviderAndAPITests: XCTestCase {
    private struct TestOnlyProvider: ThermodynamicModelProvider {
        let descriptor = ModelDescriptor(
            id: "test-only-provider",
            name: "Test-only provider",
            modelVersion: "test",
            providerVersion: "test",
            availability: .available,
            calculationMode: .local,
            supportedComponents: [.carbonDioxide],
            supportedProperties: [.density],
            domain: .initialCO2Transport,
            scientificBasis: "Test double for provider-contract tests.",
            equationOrMethod: "Test double",
            limitations: ["Not compiled into production defaults."],
            references: []
        )

        func calculate(_ request: CalculationRequest) async throws -> CalculationResponse {
            CalculationResponse(
                requestID: request.requestID,
                model: descriptor,
                phase: .gas,
                properties: [
                    PropertyValue(
                        property: .density,
                        value: 42,
                        unit: "kg/m³",
                        status: .calculated,
                        message: "Test value."
                    )
                ],
                solver: SolverMetadata(
                    method: "Test double",
                    converged: true,
                    durationMilliseconds: 0
                ),
                warnings: [],
                isScientificResult: false
            )
        }

        func phaseEnvelope(_ request: PhaseEnvelopeRequest) async throws -> PhaseEnvelopeResponse {
            PhaseEnvelopeResponse(
                requestID: request.requestID,
                points: [
                    .init(temperatureK: 250, pressurePa: 1_785_000, branch: .bubble),
                    .init(temperatureK: 304.1, pressurePa: 7_377_000, branch: .critical)
                ],
                warnings: ["Test fixture"],
                isAvailable: true,
                boundaryKind: .pureFluidSaturation,
                model: descriptor,
                generatedAt: Date(timeIntervalSince1970: 1_800_000_000),
                solver: .init(
                    method: "Test envelope",
                    converged: true,
                    durationMilliseconds: 12.5
                )
            )
        }
    }

    func testProviderSelectionUsesStableIdentifier() {
        let registry = ProviderRegistry()
        XCTAssertEqual(registry.provider(id: "coolprop-heos")?.descriptor.id, "coolprop-heos")
        XCTAssertEqual(
            registry.provider(id: "coolprop-heos")?.descriptor.availability,
            expectedDefaultCoolPropAvailability
        )
        XCTAssertNil(registry.provider(id: "missing"))
    }

    func testProductionRegistryExcludesArchitectureDemoAndKeepsIFEUnavailable() {
        let registry = ProviderRegistry()

        XCTAssertNil(registry.provider(id: "architecture-demo"))
        XCTAssertFalse(registry.descriptors.contains { $0.id == "architecture-demo" })

        let ife = registry.descriptors.first { $0.id == "ife-model" }
        XCTAssertEqual(ife?.name, "IFE Model")
        XCTAssertEqual(ife?.availability, .unavailable)
        XCTAssertEqual(ife?.limitations, ["This model is not available in this version."])
        XCTAssertNil(registry.provider(id: "ife-model"))
    }

    private var expectedDefaultCoolPropAvailability: ModelAvailability {
        #if os(iOS) && canImport(PhaseXpertCoolPropBridge)
        .preliminary
        #else
        .unavailable
        #endif
    }

    func testAPIRequestRoundTripsWithoutLosingSIUnits() throws {
        let request = IFECalculationRequestV1(
            modelID: "ife-model",
            pressurePa: 15_000_000,
            temperatureK: 293.15,
            composition: [
                .init(component: .carbonDioxide, moleFraction: 0.98),
                .init(component: .nitrogen, moleFraction: 0.02)
            ],
            requestedProperties: [.density, .dynamicViscosity],
            phaseEnvelopeSettings: .init(maximumPointCount: 120),
            clientAppVersion: "0.1.0"
        )

        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(IFECalculationRequestV1.self, from: data)

        XCTAssertEqual(decoded, request)
        XCTAssertEqual(decoded.pressure.unit, "Pa")
        XCTAssertEqual(decoded.temperature.unit, "K")
        XCTAssertEqual(decoded.phaseEnvelopeSettings?.maximumPointCount, 120)
    }

    func testTestOnlyProviderDoesNotAppearInProductionDefaults() async throws {
        let provider = TestOnlyProvider()
        let request = CalculationRequest(
            modelID: provider.descriptor.id,
            pressurePa: 15_000_000,
            temperatureK: 293.15,
            composition: [.init(component: .carbonDioxide, moleFraction: 1)],
            requestedProperties: [.density],
            clientVersion: "test"
        )

        let response = try await provider.calculate(request)
        XCTAssertNil(ProviderRegistry().provider(id: provider.descriptor.id))
        XCTAssertFalse(response.isScientificResult)
        XCTAssertEqual(response.properties.first?.value, 42)
        XCTAssertEqual(response.properties.first?.status, .calculated)
    }

    func testCalculationRecordRoundTripsWithOriginalAndNormalizedInput() async throws {
        let provider = TestOnlyProvider()
        let request = CalculationRequest(
            modelID: provider.descriptor.id,
            pressurePa: 15_000_000,
            temperatureK: 293.15,
            composition: [.init(component: .carbonDioxide, moleFraction: 1)],
            requestedProperties: [.density],
            clientVersion: "1.0 (42)"
        )
        let response = try await provider.calculate(request)
        let record = CalculationRecord(
            request: request,
            input: CalculationInputSnapshot(
                pressureValue: 150,
                pressureUnit: .bara,
                pressurePa: 15_000_000,
                temperatureValue: 20,
                temperatureUnit: .celsius,
                temperatureK: 293.15,
                originalComposition: [
                    .init(component: .carbonDioxide, value: 99.99, unit: .molePercent)
                ],
                normalizedComposition: [
                    .init(component: .carbonDioxide, moleFraction: 1)
                ]
            ),
            response: response,
            application: ApplicationIdentity(version: "1.0", build: "42")
        )

        let data = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(CalculationRecord.self, from: data)

        XCTAssertEqual(decoded, record)
        XCTAssertEqual(decoded.input.originalComposition.first?.value, 99.99)
        XCTAssertEqual(decoded.input.normalizedComposition?.first?.moleFraction, 1)
        XCTAssertEqual(decoded.response.model, response.model)
    }

    func testNonFiniteCalculatedPropertyIsNotDisplayable() {
        let property = PropertyValue(
            property: .density,
            value: .nan,
            unit: "kg/m³",
            status: .calculated
        )

        XCTAssertFalse(property.hasFiniteCalculatedValue)
    }

    func testPPMCompositionSnapshotRoundTripsWithoutChangingBasis() throws {
        let snapshot = CompositionInputSnapshot(
            component: .nitrogen,
            value: 2_500,
            unit: .partsPerMillion
        )

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(CompositionInputSnapshot.self, from: data)

        XCTAssertEqual(decoded, snapshot)
        XCTAssertEqual(decoded.unit, .partsPerMillion)
        XCTAssertEqual(decoded.value, 2_500)
    }

    func testPhaseEnvelopeTraceabilityRoundTrips() throws {
        let generatedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let response = PhaseEnvelopeResponse(
            requestID: UUID(),
            points: [
                .init(temperatureK: 250, pressurePa: 1_785_000, branch: .bubble),
                .init(temperatureK: 304.1, pressurePa: 7_377_000, branch: .critical)
            ],
            warnings: ["Validation pending"],
            isAvailable: true,
            boundaryKind: .pureFluidSaturation,
            model: TestOnlyProvider().descriptor,
            generatedAt: generatedAt,
            solver: .init(
                method: "Deterministic test method",
                converged: true,
                durationMilliseconds: 12.5
            )
        )

        let data = try JSONEncoder().encode(response)
        let decoded = try JSONDecoder().decode(PhaseEnvelopeResponse.self, from: data)

        XCTAssertEqual(decoded, response)
        XCTAssertEqual(decoded.boundaryKind, .pureFluidSaturation)
        XCTAssertEqual(decoded.generatedAt, generatedAt)
        XCTAssertEqual(decoded.solver?.method, "Deterministic test method")
    }
}
