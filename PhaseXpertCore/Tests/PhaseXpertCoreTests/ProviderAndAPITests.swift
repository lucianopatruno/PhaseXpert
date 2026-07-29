import XCTest
@testable import PhaseXpertCore

final class ProviderAndAPITests: XCTestCase {
    func testProviderSelectionUsesStableIdentifier() {
        let registry = ProviderRegistry()
        XCTAssertEqual(registry.provider(id: "coolprop-heos")?.descriptor.id, "coolprop-heos")
        XCTAssertNil(registry.provider(id: "missing"))
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
}
