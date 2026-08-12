import PhaseXpertCore
import XCTest

#if os(iOS) && canImport(PhaseXpertTeqpBridge)
import PhaseXpertTeqpBridge
#endif

/// Native teqp checks for the experimental pure-CO₂ provider.
///
/// These tests intentionally run in the iOS XCTest target because the teqp
/// XCFramework is an iOS-only artifact. They skip when that generated local
/// artifact is absent rather than substituting a mock engine.
final class TeqpNativeBridgeValidationTests: XCTestCase {
    private struct SaturationState {
        let pressurePa: Double
        let liquidDensityKilogramsPerCubicMetre: Double
        let vaporDensityKilogramsPerCubicMetre: Double
    }

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

    func testNativeTeqpSelectsStableLiquidForReportedCompressedState() async throws {
        let engine = try requireNativeTeqpEngine()
        let saturation = try requireNativeSaturation(temperatureK: 293.15)
        let result = try await engine.calculatePureCarbonDioxide(
            pressurePa: 15_000_000,
            temperatureK: 293.15
        )

        XCTAssertGreaterThan(
            15_000_000,
            saturation.pressurePa + saturationPressureTolerance(saturation.pressurePa)
        )
        XCTAssertTrue(result.densityKilogramsPerCubicMetre.isFinite)
        XCTAssertGreaterThan(result.densityKilogramsPerCubicMetre, 0)
        XCTAssertEqual(result.phaseIdentifier, "liquid")
        XCTAssertEqual(result.densityRootCount, 3)
        XCTAssertGreaterThan(
            result.densityKilogramsPerCubicMetre,
            saturation.liquidDensityKilogramsPerCubicMetre
        )
        XCTAssertEqual(
            result.densityKilogramsPerCubicMetre,
            903.956424708662,
            accuracy: 0.001
        )
    }

    func testNativeTeqpSelectsStableVaporBelowSaturation() async throws {
        let engine = try requireNativeTeqpEngine()
        let saturation = try requireNativeSaturation(temperatureK: 293.15)
        let result = try await engine.calculatePureCarbonDioxide(
            pressurePa: 1_000_000,
            temperatureK: 293.15
        )

        XCTAssertLessThan(
            1_000_000,
            saturation.pressurePa - saturationPressureTolerance(saturation.pressurePa)
        )
        XCTAssertTrue(result.densityKilogramsPerCubicMetre.isFinite)
        XCTAssertGreaterThan(result.densityKilogramsPerCubicMetre, 0)
        XCTAssertEqual(result.phaseIdentifier, "gas")
        XCTAssertEqual(result.densityRootCount, 3)
        XCTAssertLessThan(
            result.densityKilogramsPerCubicMetre,
            saturation.vaporDensityKilogramsPerCubicMetre
        )
        XCTAssertEqual(
            result.densityKilogramsPerCubicMetre,
            19.0985287213064,
            accuracy: 0.001
        )
    }

    func testNativeTeqpSelectsStableLiquidForFormerMultipleRootState() async throws {
        let engine = try requireNativeTeqpEngine()
        let saturation = try requireNativeSaturation(temperatureK: 293.15)
        let result = try await engine.calculatePureCarbonDioxide(
            pressurePa: 6_000_000,
            temperatureK: 293.15
        )

        XCTAssertGreaterThan(
            6_000_000,
            saturation.pressurePa + saturationPressureTolerance(saturation.pressurePa)
        )
        XCTAssertTrue(result.densityKilogramsPerCubicMetre.isFinite)
        XCTAssertGreaterThan(result.densityKilogramsPerCubicMetre, 0)
        XCTAssertEqual(result.phaseIdentifier, "liquid")
        XCTAssertEqual(result.densityRootCount, 5)
        XCTAssertGreaterThan(
            result.densityKilogramsPerCubicMetre,
            saturation.liquidDensityKilogramsPerCubicMetre
        )
        XCTAssertEqual(
            result.densityKilogramsPerCubicMetre,
            782.648269336157,
            accuracy: 0.001
        )
    }

    func testNativeTeqpRejectsSaturationLineAsNonUniqueHomogeneousState() async throws {
        let engine = try requireNativeTeqpEngine()
        let saturation = try requireNativeSaturation(temperatureK: 293.15)

        await XCTAssertThrowsErrorAsync {
            try await engine.calculatePureCarbonDioxide(
                pressurePa: saturation.pressurePa,
                temperatureK: 293.15
            )
        } errorHandler: { error in
            guard case let .malformedResponse(message) = error as? ProviderError else {
                XCTFail("Expected malformedResponse, got \(error).")
                return
            }
            XCTAssertTrue(message.contains("saturation"))
            XCTAssertTrue(message.contains("unique homogeneous bulk density"))
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

    private func requireNativeSaturation(
        temperatureK: Double
    ) throws -> SaturationState {
        #if os(iOS) && canImport(PhaseXpertTeqpBridge)
        var nativeResult = PXTeqpSaturationResult()
        var errorBuffer = [CChar](repeating: 0, count: 512)
        let status = px_teqp_saturation_pure_co2(
            temperatureK,
            &nativeResult,
            &errorBuffer,
            errorBuffer.count
        )
        guard status == 0 else {
            XCTFail(String(cString: errorBuffer))
            throw XCTSkip("teqp saturation result was unavailable.")
        }
        return SaturationState(
            pressurePa: nativeResult.pressure_pa,
            liquidDensityKilogramsPerCubicMetre: nativeResult.liquid_density_kg_m3,
            vaporDensityKilogramsPerCubicMetre: nativeResult.vapor_density_kg_m3
        )
        #else
        throw XCTSkip(
            "The generated teqp XCFramework is not available to this test build."
        )
        #endif
    }

    private func saturationPressureTolerance(_ pressurePa: Double) -> Double {
        max(1.0, 1e-8 * abs(pressurePa))
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
