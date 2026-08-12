import PhaseXpertCore
import XCTest

/// Native teqp checks for the experimental pure-CO₂ provider.
///
/// These tests intentionally run in the iOS XCTest target because the teqp
/// XCFramework is an iOS-only artifact. They skip when that generated local
/// artifact is absent rather than substituting a mock engine.
final class TeqpNativeBridgeValidationTests: XCTestCase {
    private struct DensityReferenceCase {
        let region: String
        let temperatureK: Double
        let pressurePa: Double
        let densityKilogramsPerCubicMetre: Double
        let expandedUncertaintyKilogramsPerCubicMetre: Double

        var toleranceKilogramsPerCubicMetre: Double {
            expandedUncertaintyKilogramsPerCubicMetre
                + 0.001 * densityKilogramsPerCubicMetre
        }
    }

    func testProductionRegistryMarksNativeTeqpSelectableWhenLinked() throws {
        let engine = try requireNativeTeqpEngine()
        XCTAssertTrue(engine.isAvailable)

        let registry = ProviderRegistry()
        XCTAssertEqual(registry.providers.first?.descriptor.id, "coolprop-heos")

        let provider = try XCTUnwrap(
            registry.provider(id: "teqp-pure-co2-experimental")
        )
        XCTAssertEqual(provider.descriptor.id, "teqp-pure-co2-experimental")
        XCTAssertEqual(provider.descriptor.availability, .preliminary)
        XCTAssertNotEqual(provider.descriptor.availability, .unavailable)

        let descriptor = try XCTUnwrap(
            registry.descriptors.first {
                $0.id == "teqp-pure-co2-experimental"
            }
        )
        XCTAssertEqual(descriptor.availability, .preliminary)
        XCTAssertTrue(descriptor.availability != .unavailable)
    }

    func testNativeTeqpDensityAgainstMantillaExperimentalData() async throws {
        let engine = try requireNativeTeqpEngine()
        XCTAssertTrue(engine.libraryVersion.contains("teqp 0.23.1"))

        for reference in densityReferences {
            let result = try await engine.calculatePureCarbonDioxide(
                pressurePa: reference.pressurePa,
                temperatureK: reference.temperatureK
            )
            let actual = result.densityKilogramsPerCubicMetre
            let absoluteDeviation = abs(
                actual - reference.densityKilogramsPerCubicMetre
            )
            let relativeDeviation = absoluteDeviation
                / reference.densityKilogramsPerCubicMetre

            XCTAssertTrue(actual.isFinite)
            XCTAssertGreaterThan(actual, 0)
            XCTAssertEqual(result.densityRootCount, 1)
            print(
                "TEQP_DENSITY_VALIDATION \(reference.region) "
                    + "T=\(reference.temperatureK)K "
                    + "P=\(reference.pressurePa)Pa "
                    + "reference=\(reference.densityKilogramsPerCubicMetre)kg/m3 "
                    + "teqp=\(actual)kg/m3 "
                    + "absoluteDeviation=\(absoluteDeviation)kg/m3 "
                    + "relativeDeviation=\(relativeDeviation)"
            )

            XCTAssertLessThanOrEqual(
                absoluteDeviation,
                reference.toleranceKilogramsPerCubicMetre,
                "teqp density failed Mantilla 2010 tolerance at "
                    + "\(reference.temperatureK) K and "
                    + "\(reference.pressurePa) Pa."
            )
        }
    }

    func testNativeTeqpRepeatedEvaluationIsDeterministic() async throws {
        let engine = try requireNativeTeqpEngine()
        let pressurePa = 19_981_000.0
        let temperatureK = 350.0
        let first = try await engine.calculatePureCarbonDioxide(
            pressurePa: pressurePa,
            temperatureK: temperatureK
        )

        for _ in 0..<10 {
            let repeated = try await engine.calculatePureCarbonDioxide(
                pressurePa: pressurePa,
                temperatureK: temperatureK
            )
            XCTAssertEqual(repeated, first)
        }
    }

    func testNativeTeqpRejectsInvalidStateInputs() async throws {
        let engine = try requireNativeTeqpEngine()
        let invalidStates = [
            (Double.nan, 310.0),
            (Double.infinity, 310.0),
            (0.0, 310.0),
            (-1.0, 310.0),
            (1_000_000.0, Double.nan),
            (1_000_000.0, Double.infinity),
            (1_000_000.0, 0.0),
            (1_000_000.0, -1.0)
        ]

        for (pressurePa, temperatureK) in invalidStates {
            await XCTAssertThrowsErrorAsync {
                try await engine.calculatePureCarbonDioxide(
                    pressurePa: pressurePa,
                    temperatureK: temperatureK
                )
            } errorHandler: { error in
                guard case let .malformedResponse(message) = error as? ProviderError else {
                    XCTFail("Expected malformedResponse, got \(error).")
                    return
                }
                XCTAssertTrue(message.contains("finite and positive"))
            }
        }
    }

    func testNativeTeqpRejectsKnownTwoPhaseStateWithoutChoosingRoot() async throws {
        let engine = try requireNativeTeqpEngine()

        await XCTAssertThrowsErrorAsync {
            try await engine.calculatePureCarbonDioxide(
                pressurePa: 6_000_000,
                temperatureK: 280
            )
        } errorHandler: { error in
            guard case let .malformedResponse(message) = error as? ProviderError else {
                XCTFail("Expected malformedResponse, got \(error).")
                return
            }
            XCTAssertTrue(message.contains("multiple pure-CO2 density roots"))
        }
    }

    private func requireNativeTeqpEngine() throws -> NativeTeqpEngine {
        let engine = NativeTeqpEngine()
        guard engine.isAvailable else {
            throw XCTSkip(
                "The generated teqp XCFramework is not available to this "
                    + "test build."
            )
        }
        return engine
    }

    private var densityReferences: [DensityReferenceCase] {
        [
            DensityReferenceCase(
                region: "gas_like",
                temperatureK: 310,
                pressurePa: 1_998_000,
                densityKilogramsPerCubicMetre: 37.614,
                expandedUncertaintyKilogramsPerCubicMetre: 0.209
            ),
            DensityReferenceCase(
                region: "near_critical_dense",
                temperatureK: 310,
                pressurePa: 10_014_000,
                densityKilogramsPerCubicMetre: 686.160,
                expandedUncertaintyKilogramsPerCubicMetre: 0.361
            ),
            DensityReferenceCase(
                region: "dense_liquid_like",
                temperatureK: 310,
                pressurePa: 29_966_000,
                densityKilogramsPerCubicMetre: 921.817,
                expandedUncertaintyKilogramsPerCubicMetre: 0.066
            ),
            DensityReferenceCase(
                region: "supercritical",
                temperatureK: 350,
                pressurePa: 19_981_000,
                densityKilogramsPerCubicMetre: 613.586,
                expandedUncertaintyKilogramsPerCubicMetre: 0.215
            ),
            DensityReferenceCase(
                region: "high_temperature_supercritical",
                temperatureK: 400,
                pressurePa: 29_994_000,
                densityKilogramsPerCubicMetre: 561.435,
                expandedUncertaintyKilogramsPerCubicMetre: 0.118
            )
        ]
    }
}

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: () async throws -> T,
    errorHandler: (Error) -> Void = { _ in },
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
