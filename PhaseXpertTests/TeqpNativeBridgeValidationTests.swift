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

    func testNativeTeqpVersionReportsCO2N2ProvenanceWhenLinked() throws {
        _ = try requireNativeTeqpEngine()

        #if os(iOS) && canImport(PhaseXpertTeqpBridge)
        var buffer = [CChar](repeating: 0, count: 256)
        XCTAssertEqual(px_teqp_copy_version(&buffer, buffer.count), 0)
        let version = nullTerminatedString(buffer)
        XCTAssertTrue(version.contains("teqp 0.23.1"))
        XCTAssertTrue(version.contains("Span-JPCRD-1996"))
        XCTAssertTrue(version.contains("Span-JPCRD-2000"))
        XCTAssertTrue(version.contains("Gernert-Thesis-2013"))
        XCTAssertTrue(version.contains("Kunz-JCED-2012"))
        XCTAssertTrue(version.contains("betaT=0.994140013"))
        XCTAssertTrue(version.contains("gammaT=1.107654104"))
        XCTAssertTrue(version.contains("betaV=1.022709642"))
        XCTAssertTrue(version.contains("gammaV=1.047578256"))
        #endif
    }

    func testNativeTeqpCO2N2MixVLETxConvergesAndSatisfiesEquilibrium() throws {
        _ = try requireNativeTeqpEngine()

        #if os(iOS) && canImport(PhaseXpertTeqpBridge)
        let result = try requireNativeBinaryVLE(
            temperatureK: 293.15,
            liquidNitrogenMoleFraction: 0.03
        )

        XCTAssertEqual(result.converged, 1)
        XCTAssertGreaterThan(result.pressure_pa, 0)
        XCTAssertEqual(result.pressure_pa, 7_040_930, accuracy: 1_000)
        XCTAssertEqual(result.liquid_n2_mole_fraction, 0.03, accuracy: 1e-8)
        XCTAssertEqual(result.vapor_n2_mole_fraction, 0.0909, accuracy: 5e-4)
        XCTAssertEqual(result.pressure_residual_pa, 0, accuracy: 1e-3)
        XCTAssertEqual(result.co2_chemical_potential_residual, 0, accuracy: 1e-4)
        XCTAssertEqual(result.n2_chemical_potential_residual, 0, accuracy: 1e-4)
        XCTAssertGreaterThan(
            result.liquid_molar_density_mol_m3,
            result.vapor_molar_density_mol_m3
        )
        #endif
    }

    func testNativeTeqpCO2N2MixVLETxIsDeterministic() throws {
        _ = try requireNativeTeqpEngine()

        #if os(iOS) && canImport(PhaseXpertTeqpBridge)
        let first = try requireNativeBinaryVLE(
            temperatureK: 293.15,
            liquidNitrogenMoleFraction: 0.05
        )
        for _ in 0..<5 {
            let repeated = try requireNativeBinaryVLE(
                temperatureK: 293.15,
                liquidNitrogenMoleFraction: 0.05
            )
            XCTAssertEqual(repeated.pressure_pa, first.pressure_pa)
            XCTAssertEqual(repeated.liquid_n2_mole_fraction, first.liquid_n2_mole_fraction)
            XCTAssertEqual(repeated.vapor_n2_mole_fraction, first.vapor_n2_mole_fraction)
        }
        #endif
    }

    func testNativeTeqpCO2N2PointReturnsHomogeneousDensityWithoutPureCO2CriticalShortcut() throws {
        _ = try requireNativeTeqpEngine()

        #if os(iOS) && canImport(PhaseXpertTeqpBridge)
        let homogeneous = try requireNativeBinaryPoint(
            pressurePa: 1_031_000,
            temperatureK: 300.0,
            nitrogenMoleFraction: 0.09079
        )
        XCTAssertEqual(homogeneous.phase, PXTeqpPhaseSupercritical)
        XCTAssertEqual(homogeneous.density_root_count, 1)
        XCTAssertEqual(homogeneous.density_kg_m3, 18.4416249412, accuracy: 0.001)
        XCTAssertTrue(homogeneous.dew_pressure_pa.isNaN)
        XCTAssertTrue(homogeneous.bubble_pressure_pa.isNaN)
        #endif
    }

    func testNativeTeqpCO2N2PointPreservesExplicitTwoPhaseClassification() throws {
        _ = try requireNativeTeqpEngine()

        #if os(iOS) && canImport(PhaseXpertTeqpBridge)
        let result = try requireNativeBinaryPoint(
            pressurePa: 6_000_000,
            temperatureK: 290.0,
            nitrogenMoleFraction: 0.02
        )
        XCTAssertEqual(result.phase, PXTeqpPhaseTwoPhase)
        XCTAssertTrue(result.density_kg_m3.isNaN)
        XCTAssertGreaterThan(result.bubble_pressure_pa, result.dew_pressure_pa)
        #endif
    }

    func testNativeTeqpCO2N2PointClassifiesSupercriticalHomogeneousState() throws {
        _ = try requireNativeTeqpEngine()

        #if os(iOS) && canImport(PhaseXpertTeqpBridge)
        let result = try requireNativeBinaryPoint(
            pressurePa: 12_000_000,
            temperatureK: 320.0,
            nitrogenMoleFraction: 0.03
        )

        XCTAssertEqual(result.phase, PXTeqpPhaseSupercritical)
        XCTAssertGreaterThan(result.density_kg_m3, 0)
        XCTAssertTrue(result.dew_pressure_pa.isNaN)
        XCTAssertTrue(result.bubble_pressure_pa.isNaN)
        XCTAssertEqual(result.dew_converged, 0)
        XCTAssertEqual(result.bubble_converged, 0)
        #endif
    }

    func testNativeTeqpCO2N2ComponentOrderingAndLowDensityLimit() throws {
        _ = try requireNativeTeqpEngine()

        #if os(iOS) && canImport(PhaseXpertTeqpBridge)
        let temperatureK = 400.0
        let pressurePa = 1_000_000.0
        let pureCO2 = try requireNativeBinaryPoint(
            pressurePa: pressurePa,
            temperatureK: temperatureK,
            nitrogenMoleFraction: 1e-8
        )
        let onePercentN2 = try requireNativeBinaryPoint(
            pressurePa: pressurePa,
            temperatureK: temperatureK,
            nitrogenMoleFraction: 0.01
        )
        let fivePercentN2 = try requireNativeBinaryPoint(
            pressurePa: pressurePa,
            temperatureK: temperatureK,
            nitrogenMoleFraction: 0.05
        )
        let tenPercentN2 = try requireNativeBinaryPoint(
            pressurePa: pressurePa,
            temperatureK: temperatureK,
            nitrogenMoleFraction: 0.10
        )

        XCTAssertGreaterThan(pureCO2.density_kg_m3, onePercentN2.density_kg_m3)
        XCTAssertGreaterThan(onePercentN2.density_kg_m3, fivePercentN2.density_kg_m3)
        XCTAssertGreaterThan(fivePercentN2.density_kg_m3, tenPercentN2.density_kg_m3)

        let densityPoints = [
            (nitrogenMoleFraction: 1e-8, result: pureCO2),
            (nitrogenMoleFraction: 0.01, result: onePercentN2),
            (nitrogenMoleFraction: 0.05, result: fivePercentN2),
            (nitrogenMoleFraction: 0.10, result: tenPercentN2)
        ]

        for densityPoint in densityPoints {
            let idealDensity = idealGasDensity(
                pressurePa: pressurePa,
                temperatureK: temperatureK,
                nitrogenMoleFraction: densityPoint.nitrogenMoleFraction
            )
            XCTAssertEqual(
                densityPoint.result.density_kg_m3,
                idealDensity,
                accuracy: 0.002 * idealDensity
            )
        }
        #endif
    }

    func testNativeTeqpCO2N2RejectsInvalidComposition() throws {
        _ = try requireNativeTeqpEngine()

        #if os(iOS) && canImport(PhaseXpertTeqpBridge)
        for nitrogenMoleFraction in [Double.nan, -0.01, 0.0, 1.0, 1.01] {
            var result = PXTeqpBinaryPointResult()
            var errorBuffer = [CChar](repeating: 0, count: 512)
            let status = px_teqp_calculate_co2_n2_point(
                1_000_000,
                293.15,
                nitrogenMoleFraction,
                &result,
                &errorBuffer,
                errorBuffer.count
            )
            XCTAssertNotEqual(status, 0)
            XCTAssertTrue(
                nullTerminatedString(errorBuffer)
                    .contains("Nitrogen mole fraction")
            )
        }
        #endif
    }

    func testNativeTeqpCO2N2RejectsInvalidPressureAndTemperature() throws {
        _ = try requireNativeTeqpEngine()

        #if os(iOS) && canImport(PhaseXpertTeqpBridge)
        let invalidStates = [
            (Double.nan, 293.15),
            (Double.infinity, 293.15),
            (0.0, 293.15),
            (-1.0, 293.15),
            (1_000_000.0, Double.nan),
            (1_000_000.0, Double.infinity),
            (1_000_000.0, 0.0),
            (1_000_000.0, -1.0)
        ]
        for (pressurePa, temperatureK) in invalidStates {
            var result = PXTeqpBinaryPointResult()
            var errorBuffer = [CChar](repeating: 0, count: 512)
            let status = px_teqp_calculate_co2_n2_point(
                pressurePa,
                temperatureK,
                0.03,
                &result,
                &errorBuffer,
                errorBuffer.count
            )
            XCTAssertNotEqual(status, 0)
            XCTAssertTrue(
                nullTerminatedString(errorBuffer)
                    .contains("finite and positive")
            )
        }
        #endif
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
            XCTFail(nullTerminatedString(errorBuffer))
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

    #if os(iOS) && canImport(PhaseXpertTeqpBridge)
    private func requireNativeBinaryVLE(
        temperatureK: Double,
        liquidNitrogenMoleFraction: Double
    ) throws -> PXTeqpBinaryVLEResult {
        var nativeResult = PXTeqpBinaryVLEResult()
        var errorBuffer = [CChar](repeating: 0, count: 512)
        let status = px_teqp_calculate_co2_n2_vle_tx(
            temperatureK,
            liquidNitrogenMoleFraction,
            &nativeResult,
            &errorBuffer,
            errorBuffer.count
        )
        guard status == 0 else {
            throw XCTSkip(
                "Native CO₂/N₂ VLE solve failed: "
                    + nullTerminatedString(errorBuffer)
            )
        }
        return nativeResult
    }

    private func requireNativeBinaryPoint(
        pressurePa: Double,
        temperatureK: Double,
        nitrogenMoleFraction: Double
    ) throws -> PXTeqpBinaryPointResult {
        var nativeResult = PXTeqpBinaryPointResult()
        var errorBuffer = [CChar](repeating: 0, count: 512)
        let status = px_teqp_calculate_co2_n2_point(
            pressurePa,
            temperatureK,
            nitrogenMoleFraction,
            &nativeResult,
            &errorBuffer,
            errorBuffer.count
        )
        guard status == 0 else {
            throw XCTSkip(
                "Native CO₂/N₂ point solve failed: "
                    + nullTerminatedString(errorBuffer)
            )
        }
        return nativeResult
    }
    #endif

    private func saturationPressureTolerance(_ pressurePa: Double) -> Double {
        max(1.0, 1e-8 * abs(pressurePa))
    }

    private func idealGasDensity(
        pressurePa: Double,
        temperatureK: Double,
        nitrogenMoleFraction: Double
    ) -> Double {
        let carbonDioxideMolarMass = 0.0440098
        let nitrogenMolarMass = 0.02801348
        let gasConstant = 8.31446261815324
        let mixtureMolarMass = (1 - nitrogenMoleFraction) * carbonDioxideMolarMass
            + nitrogenMoleFraction * nitrogenMolarMass
        return pressurePa * mixtureMolarMass / (gasConstant * temperatureK)
    }

    private func nullTerminatedString(_ buffer: [CChar]) -> String {
        let end = buffer.firstIndex(of: 0) ?? buffer.endIndex
        return String(decoding: buffer[..<end].map(UInt8.init(bitPattern:)), as: UTF8.self)
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
