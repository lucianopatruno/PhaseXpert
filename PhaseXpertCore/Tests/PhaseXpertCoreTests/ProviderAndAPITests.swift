import XCTest
@testable import PhaseXpertCore

final class ProviderAndAPITests: XCTestCase {
    func testProviderSelectionUsesStableIdentifier() {
        let registry = ProviderRegistry()
        XCTAssertEqual(registry.provider(id: "coolprop-heos")?.descriptor.id, "coolprop-heos")
        XCTAssertEqual(
            registry.provider(id: "coolprop-heos")?.descriptor.availability,
            expectedDefaultCoolPropAvailability
        )
        XCTAssertEqual(
            registry.provider(id: "thermopack-pr-classic-co2-n2")?.descriptor.id,
            "thermopack-pr-classic-co2-n2"
        )
        XCTAssertEqual(
            registry.provider(id: "thermopack-pr-classic-co2-n2")?.descriptor.availability,
            expectedDefaultThermoPackAvailability
        )
        XCTAssertNil(registry.provider(id: "missing"))
    }

    private var expectedDefaultCoolPropAvailability: ModelAvailability {
        #if os(iOS) && canImport(PhaseXpertCoolPropBridge)
        .preliminary
        #else
        .unavailable
        #endif
    }

    private var expectedDefaultThermoPackAvailability: ModelAvailability {
        #if os(iOS) && canImport(PhaseXpertThermoPackBridge)
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

    func testArchitectureDemoNeverClaimsScientificOutput() async throws {
        let provider = ArchitectureDemoProvider()
        let request = CalculationRequest(
            modelID: provider.descriptor.id,
            pressurePa: 15_000_000,
            temperatureK: 293.15,
            composition: [.init(component: .carbonDioxide, moleFraction: 1)],
            requestedProperties: [.density],
            clientVersion: "test"
        )

        let response = try await provider.calculate(request)
        XCTAssertFalse(response.isScientificResult)
        XCTAssertNil(response.properties.first?.value)
        XCTAssertEqual(response.properties.first?.status, .unavailable)
    }

    func testCalculationRecordRoundTripsWithOriginalAndNormalizedInput() async throws {
        let provider = ArchitectureDemoProvider()
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
            model: ArchitectureDemoProvider().descriptor,
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
