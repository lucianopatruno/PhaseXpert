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
        var binaryResult = CoolPropBinaryEngineResult(
            densityKilogramsPerCubicMetre: 760.2,
            phaseIdentifier: "supercritical_liquid"
        )
        var saturationLimits = CoolPropSaturationLimits(
            triplePointTemperatureK: 216.6,
            criticalPointTemperatureK: 304.1,
            criticalPointPressurePa: 7_377_000
        )
        var saturationPressure: @Sendable (Double) -> Double = { temperature in
            temperature * 20_000
        }

        func calculatePureCarbonDioxide(
            pressurePa: Double,
            temperatureK: Double
        ) async throws -> CoolPropEngineResult {
            result
        }

        func calculateCarbonDioxideNitrogen(
            pressurePa: Double,
            temperatureK: Double,
            carbonDioxideMoleFraction: Double,
            nitrogenMoleFraction: Double
        ) async throws -> CoolPropBinaryEngineResult {
            binaryResult
        }

        func pureCarbonDioxideSaturationLimits() async throws -> CoolPropSaturationLimits {
            saturationLimits
        }

        func pureCarbonDioxideSaturationPressure(
            temperatureK: Double
        ) async throws -> Double {
            saturationPressure(temperatureK)
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

    func testCO2NitrogenDensityIsPreliminaryAndViscosityRemainsUnavailable() async throws {
        let provider = CoolPropProvider(engine: MockEngine())
        XCTAssertEqual(
            provider.descriptor.supportedComponents,
            [.carbonDioxide, .nitrogen]
        )
        let request = CalculationRequest(
            modelID: provider.descriptor.id,
            pressurePa: 15_000_000,
            temperatureK: 293.15,
            composition: [
                .init(component: .carbonDioxide, moleFraction: 0.95),
                .init(component: .nitrogen, moleFraction: 0.05)
            ],
            requestedProperties: [.density, .dynamicViscosity],
            clientVersion: "test"
        )

        let response = try await provider.calculate(request)

        XCTAssertEqual(response.phase, .dense)
        XCTAssertTrue(response.warnings.contains { $0.contains("CO₂-N₂ MIXTURE SPIKE") })
        XCTAssertTrue(response.solver.method.contains("interaction data only"))
        XCTAssertEqual(
            response.properties.first { $0.property == .density }?.value,
            760.2
        )
        XCTAssertEqual(
            response.properties.first { $0.property == .dynamicViscosity }?.status,
            .unavailable
        )
    }

    func testNitrogenAboveSpikeCapIsRejected() async {
        let provider = CoolPropProvider(engine: MockEngine())
        let request = CalculationRequest(
            modelID: provider.descriptor.id,
            pressurePa: 15_000_000,
            temperatureK: 293.15,
            composition: [
                .init(component: .carbonDioxide, moleFraction: 0.89),
                .init(component: .nitrogen, moleFraction: 0.11)
            ],
            requestedProperties: [.density],
            clientVersion: "test"
        )

        do {
            _ = try await provider.calculate(request)
            XCTFail("The temporary 10 mol% N₂ cap must be enforced.")
        } catch let error as ProviderError {
            XCTAssertEqual(
                error,
                .invalidRequest(
                    "The CO₂-N₂ spike is temporarily limited to at most 10 mol% N₂."
                )
            )
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testUnapprovedThirdComponentIsRejected() async {
        let provider = CoolPropProvider(engine: MockEngine())
        let request = CalculationRequest(
            modelID: provider.descriptor.id,
            pressurePa: 15_000_000,
            temperatureK: 293.15,
            composition: [
                .init(component: .carbonDioxide, moleFraction: 0.98),
                .init(component: .nitrogen, moleFraction: 0.01),
                .init(component: .oxygen, moleFraction: 0.01)
            ],
            requestedProperties: [.density],
            clientVersion: "test"
        )

        do {
            _ = try await provider.calculate(request)
            XCTFail("An unapproved binary pair must not be calculated.")
        } catch let error as ProviderError {
            XCTAssertEqual(error, .unsupportedComponent(.oxygen))
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

    func testNonFiniteBinaryDensityIsRejected() async {
        let invalidEngine = MockEngine(binaryResult: .init(
            densityKilogramsPerCubicMetre: .infinity,
            phaseIdentifier: "gas"
        ))
        let provider = CoolPropProvider(engine: invalidEngine)
        let request = CalculationRequest(
            modelID: provider.descriptor.id,
            pressurePa: 10_000_000,
            temperatureK: 303.15,
            composition: [
                .init(component: .carbonDioxide, moleFraction: 0.95),
                .init(component: .nitrogen, moleFraction: 0.05)
            ],
            requestedProperties: [.density],
            clientVersion: "test"
        )

        do {
            _ = try await provider.calculate(request)
            XCTFail("Non-finite binary output must be rejected.")
        } catch let error as ProviderError {
            XCTAssertEqual(
                error,
                .malformedResponse(
                    "CoolProp returned a non-finite or non-positive density."
                )
            )
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testPureCO2SaturationBoundaryIsFiniteOrderedAndIncludesCriticalPoint() async throws {
        let provider = CoolPropProvider(engine: MockEngine())
        let request = PhaseEnvelopeRequest(
            modelID: provider.descriptor.id,
            composition: [.init(component: .carbonDioxide, moleFraction: 1)]
        )

        let response = try await provider.phaseEnvelope(request)

        XCTAssertTrue(response.isAvailable)
        XCTAssertEqual(response.boundaryKind, .pureFluidSaturation)
        XCTAssertEqual(response.model?.modelVersion, "8.0.0-test")
        XCTAssertEqual(response.solver?.converged, true)
        XCTAssertEqual(response.points.count, 82)
        XCTAssertTrue(response.warnings.contains { $0.contains("VALIDATION PENDING") })
        XCTAssertTrue(response.points.allSatisfy {
            $0.temperatureK.isFinite && $0.pressurePa.isFinite && $0.pressurePa > 0
        })
        let saturationPoints = response.points.filter { $0.branch == .bubble }
        XCTAssertEqual(saturationPoints.count, 81)
        XCTAssertTrue(zip(saturationPoints, saturationPoints.dropFirst()).allSatisfy { pair in
            pair.0.temperatureK < pair.1.temperatureK
                && pair.0.pressurePa < pair.1.pressurePa
        })
        let critical = try XCTUnwrap(response.points.last)
        XCTAssertEqual(critical.branch, .critical)
        XCTAssertEqual(critical.temperatureK, 304.1, accuracy: 1e-12)
        XCTAssertEqual(critical.pressurePa, 7_377_000, accuracy: 1e-12)
    }

    func testMixtureSaturationBoundaryIsExplicitlyUnavailable() async throws {
        let provider = CoolPropProvider(engine: MockEngine())
        let request = PhaseEnvelopeRequest(
            modelID: provider.descriptor.id,
            composition: [
                .init(component: .carbonDioxide, moleFraction: 0.99),
                .init(component: .nitrogen, moleFraction: 0.01)
            ]
        )

        let response = try await provider.phaseEnvelope(request)

        XCTAssertFalse(response.isAvailable)
        XCTAssertTrue(response.points.isEmpty)
        XCTAssertTrue(response.warnings.contains { $0.contains("100 mol% CO₂") })
    }

    func testNonFiniteSaturationPressureIsRejected() async {
        let provider = CoolPropProvider(engine: MockEngine(
            saturationPressure: { _ in .nan }
        ))
        let request = PhaseEnvelopeRequest(
            modelID: provider.descriptor.id,
            composition: [.init(component: .carbonDioxide, moleFraction: 1)]
        )

        do {
            _ = try await provider.phaseEnvelope(request)
            XCTFail("A non-finite boundary point must be rejected.")
        } catch let error as ProviderError {
            XCTAssertEqual(
                error,
                .malformedResponse(
                    "CoolProp returned a non-finite or non-positive saturation pressure."
                )
            )
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testCancelledSaturationBoundaryStopsBeforeEngineWork() async {
        let provider = CoolPropProvider(engine: MockEngine())
        let request = PhaseEnvelopeRequest(
            modelID: provider.descriptor.id,
            composition: [.init(component: .carbonDioxide, moleFraction: 1)]
        )
        let task = Task {
            try await provider.phaseEnvelope(request)
        }
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("A cancelled envelope request must not complete.")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
