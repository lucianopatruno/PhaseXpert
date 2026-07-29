import XCTest
@testable import PhaseXpertCore

final class CoolPropProviderTests: XCTestCase {
    private struct MockEngine: CoolPropEngine {
        let isAvailable = true
        let libraryVersion = "8.0.0-test"
        var result = CoolPropEngineResult(
            densityKilogramsPerCubicMetre: 821.4,
            dynamicViscosityPascalSeconds: 0.000071,
            phaseIdentifier: "supercritical_liquid"
        )

        func calculatePureCarbonDioxide(
            pressurePa: Double,
            temperatureK: Double
        ) async throws -> CoolPropEngineResult {
            result
        }
    }

    func testUnavailableEngineDoesNotClaimCapabilities() {
        let provider = CoolPropProvider(engine: UnavailableCoolPropEngine())

        XCTAssertEqual(provider.descriptor.availability, .unavailable)
        XCTAssertTrue(provider.descriptor.supportedComponents.isEmpty)
        XCTAssertTrue(provider.descriptor.supportedProperties.isEmpty)
    }

    func testPureCO2ResultIsPreliminaryAndTraceable() async throws {
        let provider = CoolPropProvider(engine: MockEngine())
        let request = CalculationRequest(
            modelID: provider.descriptor.id,
            pressurePa: 15_000_000,
            temperatureK: 293.15,
            composition: [.init(component: .carbonDioxide, moleFraction: 1)],
            requestedProperties: [.density, .dynamicViscosity, .enthalpy],
            clientVersion: "test"
        )

        let response = try await provider.calculate(request)

        XCTAssertEqual(response.model.modelVersion, "8.0.0-test")
        XCTAssertEqual(response.model.availability, .preliminary)
        XCTAssertEqual(response.phase, .dense)
        XCTAssertTrue(response.isScientificResult)
        XCTAssertTrue(response.warnings.contains { $0.contains("VALIDATION PENDING") })
        XCTAssertEqual(
            response.properties.first { $0.property == .density }?.status,
            .calculated
        )
        XCTAssertEqual(
            response.properties.first { $0.property == .dynamicViscosity }?.unit,
            "Pa·s"
        )
        XCTAssertEqual(
            response.properties.first { $0.property == .enthalpy }?.status,
            .unavailable
        )
    }

    func testMixtureIsRejectedDuringPureCO2Spike() async {
        let provider = CoolPropProvider(engine: MockEngine())
        let request = CalculationRequest(
            modelID: provider.descriptor.id,
            pressurePa: 15_000_000,
            temperatureK: 293.15,
            composition: [
                .init(component: .carbonDioxide, moleFraction: 0.99),
                .init(component: .nitrogen, moleFraction: 0.01)
            ],
            requestedProperties: [.density],
            clientVersion: "test"
        )

        do {
            _ = try await provider.calculate(request)
            XCTFail("A mixture must not be accepted in the pure-CO₂ spike.")
        } catch let error as ProviderError {
            XCTAssertEqual(
                error,
                .invalidRequest("The CoolProp spike accepts pure CO₂ only.")
            )
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testNonFiniteNativeResultIsRejected() async {
        let invalidEngine = MockEngine(result: .init(
            densityKilogramsPerCubicMetre: .nan,
            dynamicViscosityPascalSeconds: 0.000071,
            phaseIdentifier: "liquid"
        ))
        let provider = CoolPropProvider(engine: invalidEngine)
        let request = CalculationRequest(
            modelID: provider.descriptor.id,
            pressurePa: 15_000_000,
            temperatureK: 293.15,
            composition: [.init(component: .carbonDioxide, moleFraction: 1)],
            requestedProperties: [.density],
            clientVersion: "test"
        )

        do {
            _ = try await provider.calculate(request)
            XCTFail("Non-finite native output must be rejected.")
        } catch let error as ProviderError {
            XCTAssertEqual(
                error,
                .malformedResponse(
                    "CoolProp returned a non-finite or non-positive property."
                )
            )
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
