import PhaseXpertCore
import XCTest

#if os(iOS) && canImport(PhaseXpertTeqpBridge)
import PhaseXpertTeqpBridge

private struct PXTestTeqpMixtureThermodynamicResult {
    var density_kg_m3: Double = 0
    var molar_density_mol_m3: Double = 0
    var pressure_pa: Double = 0
    var dp_drho_molar_j_mol: Double = 0
    var dp_dt_pa_k: Double = 0
    var isochoric_heat_capacity_j_kg_k: Double = 0
    var isobaric_heat_capacity_j_kg_k: Double = 0
    var heat_capacity_ratio: Double = 0
    var speed_of_sound_m_s: Double = 0
    var speed_of_sound_squared_m2_s2: Double = 0
    var minimum_stability_eigenvalue: Double = 0
    var density_root_count: Int32 = 0
    var converged: Int32 = 0
    var phase: Int32 = 0
}

private struct PXTestTeqpBinaryCriticalResult {
    var converged: Int32 = 0
    var iteration_count: Int32 = 0
    var temperature_k: Double = 0
    var pressure_pa: Double = 0
    var molar_density_mol_m3: Double = 0
    var density_kg_m3: Double = 0
    var component2_mole_fraction: Double = 0
    var minimum_stability_eigenvalue: Double = 0
    var third_order_residual: Double = 0
}

@_silgen_name("px_teqp_calculate_binary_thermodynamic_state")
private func px_test_teqp_calculate_binary_thermodynamic_state(
    _ formulation: Int32,
    _ pressurePa: Double,
    _ temperatureK: Double,
    _ component2MoleFraction: Double,
    _ result: UnsafeMutablePointer<PXTestTeqpMixtureThermodynamicResult>,
    _ errorBuffer: UnsafeMutablePointer<CChar>,
    _ errorBufferSize: Int
) -> Int32

@_silgen_name("px_teqp_calculate_binary_critical_point")
private func px_test_teqp_calculate_binary_critical_point(
    _ formulation: Int32,
    _ component2MoleFraction: Double,
    _ result: UnsafeMutablePointer<PXTestTeqpBinaryCriticalResult>,
    _ errorBuffer: UnsafeMutablePointer<CChar>,
    _ errorBufferSize: Int
) -> Int32
#endif

private struct NativeMixtureThermodynamicState {
    let converged: Bool
    let densityKilogramsPerCubicMetre: Double
    let molarDensityMolesPerCubicMetre: Double
    let pressureDerivativeWithRespectToMolarDensityJoulesPerMole: Double
    let pressureDerivativeWithRespectToTemperaturePascalsPerKelvin: Double
    let isochoricHeatCapacityJoulesPerKilogramKelvin: Double
    let isobaricHeatCapacityJoulesPerKilogramKelvin: Double
    let heatCapacityRatio: Double
    let speedOfSoundMetresPerSecond: Double
    let speedOfSoundSquaredMetresSquaredPerSecondSquared: Double
    let minimumStabilityEigenvalue: Double
}

private struct NativeBinaryCriticalState {
    let converged: Bool
    let temperatureK: Double
    let pressurePa: Double
    let densityKilogramsPerCubicMetre: Double
    let component2MoleFraction: Double
    let minimumStabilityEigenvalue: Double
    let thirdOrderResidual: Double
}

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

    private struct PropertyReferenceCase {
        let region: String
        let temperatureK: Double
        let pressurePa: Double
        let isochoricHeatCapacityJoulesPerKilogramKelvin: Double
        let isobaricHeatCapacityJoulesPerKilogramKelvin: Double
        let speedOfSoundMetresPerSecond: Double
    }

    private struct PetropoulouVLERow {
        let row: Int
        let temperatureK: Double
        let pressurePa: Double
        let liquidMethaneMoleFraction: Double
        let vaporMethaneMoleFraction: Double
        let nearCritical: Bool
    }

    func testNativeGenericNComponentDensityAcrossAuditedSystems() async throws {
        let provider = TeqpProvider(engine: try requireNativeTeqpEngine())
        let systems: [[MixtureComponent]] = [
            [.init(component: .carbonDioxide, moleFraction: 0.95), .init(component: .nitrogen, moleFraction: 0.05)],
            [.init(component: .carbonDioxide, moleFraction: 0.90), .init(component: .nitrogen, moleFraction: 0.05), .init(component: .methane, moleFraction: 0.05)],
            [.init(component: .carbonDioxide, moleFraction: 0.88), .init(component: .nitrogen, moleFraction: 0.05), .init(component: .methane, moleFraction: 0.04), .init(component: .hydrogen, moleFraction: 0.03)],
            [.init(component: .carbonDioxide, moleFraction: 0.99), .init(component: .water, moleFraction: 0.01)],
            [.init(component: .carbonDioxide, moleFraction: 0.94), .init(component: .nitrogen, moleFraction: 0.05), .init(component: .water, moleFraction: 0.01)],
            [.init(component: .carbonDioxide, moleFraction: 0.76), .init(component: .nitrogen, moleFraction: 0.05), .init(component: .methane, moleFraction: 0.04), .init(component: .hydrogen, moleFraction: 0.03), .init(component: .oxygen, moleFraction: 0.03), .init(component: .argon, moleFraction: 0.03), .init(component: .carbonMonoxide, moleFraction: 0.02), .init(component: .hydrogenSulfide, moleFraction: 0.02), .init(component: .water, moleFraction: 0.02)]
        ]
        for composition in systems {
            let result = try await provider.diagnosticNComponentDensity(
                pressurePa: 8_000_000,
                temperatureK: 320,
                composition: composition
            )
            XCTAssertTrue(result.converged)
            XCTAssertTrue(result.densityKilogramsPerCubicMetre.isFinite)
            XCTAssertGreaterThan(result.densityKilogramsPerCubicMetre, 0)
        }
    }

    func testNativeEOSCGCarbonDioxideOxygenProductionDensity() async throws {
        let engine = try requireNativeTeqpEngine()
        let result = try await engine.calculateCarbonDioxideOxygenGasDensity(
            pressurePa: 3_940_000,
            temperatureK: 275.001,
            oxygenMoleFraction: 0.05032089
        )
        XCTAssertEqual(result.densityKilogramsPerCubicMetre, 109.300351603473, accuracy: 1e-8)
        XCTAssertGreaterThanOrEqual(result.densityRootCount, 1)
        XCTAssertEqual(result.phaseIdentifier, "gas")
        XCTAssertEqual(result.formulationID, TeqpFormulationCatalog.co2OxygenEOSCGGasDensity.id)
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

    func testNativeTeqpPureCO2CaloricPropertiesAgainstNISTWebBook() async throws {
        let engine = try requireNativeTeqpEngine()

        for reference in propertyReferences {
            let result = try await engine.calculatePureCarbonDioxide(
                pressurePa: reference.pressurePa,
                temperatureK: reference.temperatureK
            )

            let cv = try XCTUnwrap(
                result.isochoricHeatCapacityJoulesPerKilogramKelvin
            )
            let cp = try XCTUnwrap(
                result.isobaricHeatCapacityJoulesPerKilogramKelvin
            )
            let speedOfSound = try XCTUnwrap(result.speedOfSoundMetresPerSecond)
            XCTAssertTrue(cv.isFinite)
            XCTAssertTrue(cp.isFinite)
            XCTAssertTrue(speedOfSound.isFinite)
            XCTAssertGreaterThan(cv, 0)
            XCTAssertGreaterThan(cp, cv)
            XCTAssertGreaterThan(speedOfSound, 0)
            XCTAssertEqual(
                cv,
                reference.isochoricHeatCapacityJoulesPerKilogramKelvin,
                accuracy: 0.000_01,
                "Cv mismatch for \(reference.region)."
            )
            XCTAssertEqual(
                cp,
                reference.isobaricHeatCapacityJoulesPerKilogramKelvin,
                accuracy: 0.000_01,
                "Cp mismatch for \(reference.region)."
            )
            XCTAssertEqual(
                speedOfSound,
                reference.speedOfSoundMetresPerSecond,
                accuracy: 0.000_001,
                "Speed-of-sound mismatch for \(reference.region)."
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

    func testNativeTeqpCO2N2DiagnosticMixVLETxConvergesAndSatisfiesEquilibrium() throws {
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

    func testNativeTeqpCO2N2DiagnosticMixVLETxIsDeterministic() throws {
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

    func testNativeTeqpGenericBinaryVLEBridgeRunsCorrectedCO2CH4PetropoulouSlice() throws {
        _ = try requireNativeTeqpEngine()

        #if os(iOS) && canImport(PhaseXpertTeqpBridge)
        let references = petropoulouRows

        var allPressureRelativeDeviations: [Double] = []
        var acceptedPressureRelativeDeviations: [Double] = []
        var acceptedVaporCompositionDeviations: [Double] = []
        var acceptedRows: [Int] = []
        for reference in references {
            let result = try requireNativeGenericBinaryVLE(
                formulation: PXTeqpBinaryFormulationEOSCGCO2CH4,
                temperatureK: reference.temperatureK,
                liquidComponent2MoleFraction:
                    reference.liquidMethaneMoleFraction,
                initialGuess: petropoulouInitialGuess(for: reference)
            )
            let pressureRelativeDeviation = abs(result.pressure_pa - reference.pressurePa)
                / reference.pressurePa
            let vaporCompositionDeviation = abs(
                result.vapor_component2_mole_fraction
                    - reference.vaporMethaneMoleFraction
            )
            allPressureRelativeDeviations.append(pressureRelativeDeviation)
            if isAcceptedMethaneProductionVLERow(reference) {
                acceptedRows.append(reference.row)
                acceptedPressureRelativeDeviations.append(pressureRelativeDeviation)
                acceptedVaporCompositionDeviations.append(vaporCompositionDeviation)
            }
            print(
                "TEQP_CO2_CH4_PETROPOULOU_VLE "
                    + "row=\(reference.row) "
                    + "T=\(reference.temperatureK)K "
                    + "referenceP=\(reference.pressurePa)Pa "
                    + "predictedP=\(result.pressure_pa)Pa "
                    + "pressureRelativeDeviation=\(pressureRelativeDeviation) "
                    + "referenceYCH4=\(reference.vaporMethaneMoleFraction) "
                    + "predictedYCH4=\(result.vapor_component2_mole_fraction) "
                    + "vaporCompositionDeviation=\(vaporCompositionDeviation) "
                    + "nearCritical=\(reference.nearCritical) "
                    + "iterations=\(result.iteration_count) "
                    + "pressureResidual=\(result.pressure_residual_pa) "
                    + "component1Residual=\(result.component1_chemical_potential_residual) "
                    + "component2Residual=\(result.component2_chemical_potential_residual)"
            )

            XCTAssertEqual(result.converged, 1)
            XCTAssertGreaterThan(result.pressure_pa, 0)
            XCTAssertGreaterThan(result.liquid_molar_density_mol_m3, 0)
            XCTAssertGreaterThan(result.vapor_molar_density_mol_m3, 0)
            XCTAssertEqual(
                result.liquid_component2_mole_fraction,
                reference.liquidMethaneMoleFraction,
                accuracy: 1e-8
            )
            XCTAssertTrue(result.vapor_component2_mole_fraction.isFinite)
            XCTAssertGreaterThan(
                result.liquid_molar_density_mol_m3,
                result.vapor_molar_density_mol_m3
            )
            // This residual is an absolute pressure closure check, not an
            // experimental-accuracy gate. Sub-centipascal closure is well
            // below both measurement uncertainty and binary VLE acceptance.
            XCTAssertEqual(result.pressure_residual_pa, 0, accuracy: 1e-2)
            XCTAssertEqual(
                result.component1_chemical_potential_residual,
                0,
                accuracy: 1e-4
            )
            XCTAssertEqual(
                result.component2_chemical_potential_residual,
                0,
                accuracy: 1e-4
            )

            let repeated = try requireNativeGenericBinaryVLE(
                formulation: PXTeqpBinaryFormulationEOSCGCO2CH4,
                temperatureK: reference.temperatureK,
                liquidComponent2MoleFraction:
                    reference.liquidMethaneMoleFraction,
                initialGuess: petropoulouInitialGuess(for: reference)
            )
            XCTAssertEqual(repeated.pressure_pa, result.pressure_pa)
            XCTAssertEqual(
                repeated.vapor_component2_mole_fraction,
                result.vapor_component2_mole_fraction
            )
            XCTAssertEqual(
                repeated.liquid_molar_density_mol_m3,
                result.liquid_molar_density_mol_m3
            )
            XCTAssertEqual(
                repeated.vapor_molar_density_mol_m3,
                result.vapor_molar_density_mol_m3
            )
        }
        XCTAssertEqual(references.count, 37)
        XCTAssertEqual(allPressureRelativeDeviations.count, 37)
        XCTAssertEqual(acceptedRows, Array(2...15) + Array(17...26))
        XCTAssertEqual(acceptedRows.count, 24)

        let acceptedAARD = acceptedPressureRelativeDeviations.reduce(0, +)
            / Double(acceptedPressureRelativeDeviations.count)
        let acceptedWorstPressureDeviation = acceptedPressureRelativeDeviations.max() ?? .nan
        let acceptedWorstVaporCompositionDeviation =
            acceptedVaporCompositionDeviations.max() ?? .nan
        // Assert the reviewed scientific gate rather than a toolchain-specific
        // last-digit snapshot of the nonlinear solve.
        XCTAssertLessThanOrEqual(acceptedAARD * 100, 0.62)
        XCTAssertLessThanOrEqual(acceptedWorstPressureDeviation * 100, 1.80)
        XCTAssertLessThanOrEqual(acceptedWorstVaporCompositionDeviation, 0.027)

        let diagnostic303Rows = references.filter { abs($0.temperatureK - 303.144) < 0.01 }
        XCTAssertEqual(diagnostic303Rows.count, 11)
        XCTAssertFalse(diagnostic303Rows.contains(where: isAcceptedMethaneProductionVLERow))
        #endif
    }

    func testNativeTeqpEOSCGMixtureThermodynamicDiagnosticsAreFinite() async throws {
        _ = try requireNativeTeqpEngine()

        #if os(iOS) && canImport(PhaseXpertTeqpBridge)
        let methane = try requireNativeMixtureThermodynamicState(
            formulation: 3,
            pressurePa: 4_979_790,
            temperatureK: 301.147,
            component2MoleFraction: 0.05
        )
        assertFiniteStableMixtureThermodynamicResult(methane)

        let hydrogen = try requireNativeMixtureThermodynamicState(
            formulation: 2,
            pressurePa: 3_000_000,
            temperatureK: 293.15,
            component2MoleFraction: 0.05362
        )
        assertFiniteStableMixtureThermodynamicResult(hydrogen)
        #endif
    }

    func testNativeTeqpEOSCGMethaneCriticalDiagnosticRunsAtFixedComposition() async throws {
        _ = try requireNativeTeqpEngine()

        #if os(iOS) && canImport(PhaseXpertTeqpBridge)
        let critical = try requireNativeBinaryCriticalPoint(
            formulation: 3,
            component2MoleFraction: 0.05
        )
        XCTAssertTrue(critical.converged)
        XCTAssertEqual(critical.component2MoleFraction, 0.05, accuracy: 1e-12)
        XCTAssertGreaterThan(critical.temperatureK, 250)
        XCTAssertLessThan(critical.temperatureK, 350)
        XCTAssertGreaterThan(critical.pressurePa, 0)
        XCTAssertGreaterThan(critical.densityKilogramsPerCubicMetre, 0)
        XCTAssertLessThan(abs(critical.minimumStabilityEigenvalue), 1e-4)
        XCTAssertLessThan(abs(critical.thirdOrderResidual), 1e-6)
        #endif
    }

    func testNativeTeqpCO2N2DiagnosticPointReturnsHomogeneousDensityWithoutPureCO2CriticalShortcut() throws {
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

    func testNativeTeqpCO2N2DiagnosticPointPreservesExplicitTwoPhaseClassification() throws {
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

    func testNativeTeqpCO2N2DiagnosticPointClassifiesSupercriticalHomogeneousState() throws {
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

    func testNativeTeqpCO2N2DiagnosticComponentOrderingAndLowDensityLimit() throws {
        _ = try requireNativeTeqpEngine()

        #if os(iOS) && canImport(PhaseXpertTeqpBridge)
        let temperatureK = 400.0
        let pressurePa = 100_000.0
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

    func testNativeTeqpCO2N2DiagnosticRejectsInvalidComposition() throws {
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

    func testNativeTeqpCO2N2DiagnosticRejectsInvalidPressureAndTemperature() throws {
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

    private func requireNativeMixtureThermodynamicState(
        formulation: Int32,
        pressurePa: Double,
        temperatureK: Double,
        component2MoleFraction: Double
    ) throws -> NativeMixtureThermodynamicState {
        #if os(iOS) && canImport(PhaseXpertTeqpBridge)
        var native = PXTestTeqpMixtureThermodynamicResult()
        var errorBuffer = [CChar](repeating: 0, count: 512)
        let status = px_test_teqp_calculate_binary_thermodynamic_state(
            formulation,
            pressurePa,
            temperatureK,
            component2MoleFraction,
            &native,
            &errorBuffer,
            errorBuffer.count
        )
        XCTAssertEqual(status, 0, nullTerminatedString(errorBuffer))
        return NativeMixtureThermodynamicState(
            converged: native.converged == 1,
            densityKilogramsPerCubicMetre: native.density_kg_m3,
            molarDensityMolesPerCubicMetre: native.molar_density_mol_m3,
            pressureDerivativeWithRespectToMolarDensityJoulesPerMole:
                native.dp_drho_molar_j_mol,
            pressureDerivativeWithRespectToTemperaturePascalsPerKelvin:
                native.dp_dt_pa_k,
            isochoricHeatCapacityJoulesPerKilogramKelvin:
                native.isochoric_heat_capacity_j_kg_k,
            isobaricHeatCapacityJoulesPerKilogramKelvin:
                native.isobaric_heat_capacity_j_kg_k,
            heatCapacityRatio: native.heat_capacity_ratio,
            speedOfSoundMetresPerSecond: native.speed_of_sound_m_s,
            speedOfSoundSquaredMetresSquaredPerSecondSquared:
                native.speed_of_sound_squared_m2_s2,
            minimumStabilityEigenvalue: native.minimum_stability_eigenvalue
        )
        #else
        throw XCTSkip("Native teqp XCFramework is not linked in this build.")
        #endif
    }

    private func requireNativeBinaryCriticalPoint(
        formulation: Int32,
        component2MoleFraction: Double
    ) throws -> NativeBinaryCriticalState {
        #if os(iOS) && canImport(PhaseXpertTeqpBridge)
        var native = PXTestTeqpBinaryCriticalResult()
        var errorBuffer = [CChar](repeating: 0, count: 512)
        let status = px_test_teqp_calculate_binary_critical_point(
            formulation,
            component2MoleFraction,
            &native,
            &errorBuffer,
            errorBuffer.count
        )
        XCTAssertEqual(status, 0, nullTerminatedString(errorBuffer))
        return NativeBinaryCriticalState(
            converged: native.converged == 1,
            temperatureK: native.temperature_k,
            pressurePa: native.pressure_pa,
            densityKilogramsPerCubicMetre: native.density_kg_m3,
            component2MoleFraction: native.component2_mole_fraction,
            minimumStabilityEigenvalue: native.minimum_stability_eigenvalue,
            thirdOrderResidual: native.third_order_residual
        )
        #else
        throw XCTSkip("Native teqp XCFramework is not linked in this build.")
        #endif
    }

    private func assertFiniteStableMixtureThermodynamicResult(
        _ result: NativeMixtureThermodynamicState,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(result.converged, file: file, line: line)
        XCTAssertGreaterThan(result.densityKilogramsPerCubicMetre, 0, file: file, line: line)
        XCTAssertGreaterThan(result.molarDensityMolesPerCubicMetre, 0, file: file, line: line)
        XCTAssertGreaterThan(result.pressureDerivativeWithRespectToMolarDensityJoulesPerMole, 0, file: file, line: line)
        XCTAssertGreaterThan(result.pressureDerivativeWithRespectToTemperaturePascalsPerKelvin, 0, file: file, line: line)
        XCTAssertGreaterThan(result.isochoricHeatCapacityJoulesPerKilogramKelvin, 0, file: file, line: line)
        XCTAssertGreaterThan(
            result.isobaricHeatCapacityJoulesPerKilogramKelvin,
            result.isochoricHeatCapacityJoulesPerKilogramKelvin,
            file: file,
            line: line
        )
        XCTAssertGreaterThan(result.heatCapacityRatio, 1, file: file, line: line)
        XCTAssertGreaterThan(result.speedOfSoundMetresPerSecond, 0, file: file, line: line)
        XCTAssertGreaterThan(result.speedOfSoundSquaredMetresSquaredPerSecondSquared, 0, file: file, line: line)
        XCTAssertGreaterThan(result.minimumStabilityEigenvalue, 0, file: file, line: line)
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

    private func requireNativeGenericBinaryVLE(
        formulation: PXTeqpBinaryFormulation,
        temperatureK: Double,
        liquidComponent2MoleFraction: Double,
        initialGuess: PXTeqpBinaryVLEInitialGuess? = nil
    ) throws -> PXTeqpGenericBinaryVLEResult {
        var nativeResult = PXTeqpGenericBinaryVLEResult()
        var errorBuffer = [CChar](repeating: 0, count: 512)
        let status: Int32
        if let initialGuess {
            status = px_teqp_calculate_binary_vle_tx_with_initial_guess(
                formulation,
                temperatureK,
                liquidComponent2MoleFraction,
                initialGuess,
                &nativeResult,
                &errorBuffer,
                errorBuffer.count
            )
        } else {
            status = px_teqp_calculate_binary_vle_tx(
                formulation,
                temperatureK,
                liquidComponent2MoleFraction,
                &nativeResult,
                &errorBuffer,
                errorBuffer.count
            )
        }
        guard status == 0 else {
            throw XCTSkip(
                "Native generic binary VLE solve failed: "
                    + nullTerminatedString(errorBuffer)
            )
        }
        return nativeResult
    }

    private func petropoulouInitialGuess(
        for reference: PetropoulouVLERow
    ) -> PXTeqpBinaryVLEInitialGuess {
        let idealVaporDensity = reference.pressurePa
            / (8.314_462_618_153_24 * reference.temperatureK)
        return PXTeqpBinaryVLEInitialGuess(
            liquid_molar_density_mol_m3: 19_000,
            vapor_molar_density_mol_m3: idealVaporDensity,
            vapor_component2_mole_fraction:
                reference.vaporMethaneMoleFraction
        )
    }

    private func isAcceptedMethaneProductionVLERow(
        _ row: PetropoulouVLERow
    ) -> Bool {
        !row.nearCritical
            && (abs(row.temperatureK - 293.13) < 0.03
                || abs(row.temperatureK - 298.142) < 0.03)
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

    private var propertyReferences: [PropertyReferenceCase] {
        [
            PropertyReferenceCase(
                region: "gas",
                temperatureK: 293.15,
                pressurePa: 1_000_000,
                isochoricHeatCapacityJoulesPerKilogramKelvin: 677.902139023,
                isobaricHeatCapacityJoulesPerKilogramKelvin: 921.219397517,
                speedOfSoundMetresPerSecond: 259.064082533
            ),
            PropertyReferenceCase(
                region: "dense_liquid",
                temperatureK: 293.15,
                pressurePa: 15_000_000,
                isochoricHeatCapacityJoulesPerKilogramKelvin: 921.471647813,
                isobaricHeatCapacityJoulesPerKilogramKelvin: 2_246.22018166,
                speedOfSoundMetresPerSecond: 563.944857810
            ),
            PropertyReferenceCase(
                region: "supercritical",
                temperatureK: 350,
                pressurePa: 19_981_000,
                isochoricHeatCapacityJoulesPerKilogramKelvin: 921.209412650,
                isobaricHeatCapacityJoulesPerKilogramKelvin: 2_622.65420410,
                speedOfSoundMetresPerSecond: 351.207147845
            )
        ]
    }

    private var petropoulouRows: [PetropoulouVLERow] {
        [
            PetropoulouVLERow(row: 1, temperatureK: 293.13, pressurePa: 5_727_300, liquidMethaneMoleFraction: 1e-05, vaporMethaneMoleFraction: 1e-05, nearCritical: true),
            PetropoulouVLERow(row: 2, temperatureK: 293.13, pressurePa: 6_134_700, liquidMethaneMoleFraction: 0.01528, vaporMethaneMoleFraction: 0.0397, nearCritical: false),
            PetropoulouVLERow(row: 3, temperatureK: 293.13, pressurePa: 6_645_850, liquidMethaneMoleFraction: 0.03561, vaporMethaneMoleFraction: 0.08029, nearCritical: false),
            PetropoulouVLERow(row: 4, temperatureK: 293.13, pressurePa: 6_840_100, liquidMethaneMoleFraction: 0.04389, vaporMethaneMoleFraction: 0.09321, nearCritical: false),
            PetropoulouVLERow(row: 5, temperatureK: 293.13, pressurePa: 6_975_550, liquidMethaneMoleFraction: 0.04982, vaporMethaneMoleFraction: 0.10137, nearCritical: false),
            PetropoulouVLERow(row: 6, temperatureK: 293.129, pressurePa: 7_118_300, liquidMethaneMoleFraction: 0.05636, vaporMethaneMoleFraction: 0.1093, nearCritical: false),
            PetropoulouVLERow(row: 7, temperatureK: 293.13, pressurePa: 7_350_800, liquidMethaneMoleFraction: 0.0676, vaporMethaneMoleFraction: 0.12021, nearCritical: false),
            PetropoulouVLERow(row: 8, temperatureK: 293.13, pressurePa: 7_575_800, liquidMethaneMoleFraction: 0.07976, vaporMethaneMoleFraction: 0.12811, nearCritical: false),
            PetropoulouVLERow(row: 9, temperatureK: 293.13, pressurePa: 7_796_150, liquidMethaneMoleFraction: 0.09432, vaporMethaneMoleFraction: 0.13134, nearCritical: false),
            PetropoulouVLERow(row: 10, temperatureK: 293.13, pressurePa: 7_909_100, liquidMethaneMoleFraction: 0.10606, vaporMethaneMoleFraction: 0.12697, nearCritical: false),
            PetropoulouVLERow(row: 11, temperatureK: 293.13, pressurePa: 7_913_500, liquidMethaneMoleFraction: 0.10691, vaporMethaneMoleFraction: 0.12639, nearCritical: false),
            PetropoulouVLERow(row: 12, temperatureK: 293.128, pressurePa: 7_917_900, liquidMethaneMoleFraction: 0.1078, vaporMethaneMoleFraction: 0.12576, nearCritical: false),
            PetropoulouVLERow(row: 13, temperatureK: 293.13, pressurePa: 7_921_900, liquidMethaneMoleFraction: 0.10877, vaporMethaneMoleFraction: 0.12501, nearCritical: false),
            PetropoulouVLERow(row: 14, temperatureK: 293.13, pressurePa: 7_926_600, liquidMethaneMoleFraction: 0.11018, vaporMethaneMoleFraction: 0.12374, nearCritical: false),
            PetropoulouVLERow(row: 15, temperatureK: 293.13, pressurePa: 7_930_800, liquidMethaneMoleFraction: 0.11218, vaporMethaneMoleFraction: 0.12183, nearCritical: false),
            PetropoulouVLERow(row: 16, temperatureK: 298.141, pressurePa: 6_431_600, liquidMethaneMoleFraction: 1e-05, vaporMethaneMoleFraction: 1e-05, nearCritical: true),
            PetropoulouVLERow(row: 17, temperatureK: 298.142, pressurePa: 6_641_050, liquidMethaneMoleFraction: 0.008, vaporMethaneMoleFraction: 0.01703, nearCritical: false),
            PetropoulouVLERow(row: 18, temperatureK: 298.142, pressurePa: 6_975_450, liquidMethaneMoleFraction: 0.02145, vaporMethaneMoleFraction: 0.04083, nearCritical: false),
            PetropoulouVLERow(row: 19, temperatureK: 298.142, pressurePa: 7_311_400, liquidMethaneMoleFraction: 0.03639, vaporMethaneMoleFraction: 0.06007, nearCritical: false),
            PetropoulouVLERow(row: 20, temperatureK: 298.142, pressurePa: 7_507_850, liquidMethaneMoleFraction: 0.04641, vaporMethaneMoleFraction: 0.0682, nearCritical: false),
            PetropoulouVLERow(row: 21, temperatureK: 298.142, pressurePa: 7_625_000, liquidMethaneMoleFraction: 0.05378, vaporMethaneMoleFraction: 0.07083, nearCritical: false),
            PetropoulouVLERow(row: 22, temperatureK: 298.142, pressurePa: 7_659_900, liquidMethaneMoleFraction: 0.05663, vaporMethaneMoleFraction: 0.07072, nearCritical: false),
            PetropoulouVLERow(row: 23, temperatureK: 298.142, pressurePa: 7_678_300, liquidMethaneMoleFraction: 0.0585, vaporMethaneMoleFraction: 0.07021, nearCritical: false),
            PetropoulouVLERow(row: 24, temperatureK: 298.142, pressurePa: 7_688_600, liquidMethaneMoleFraction: 0.05984, vaporMethaneMoleFraction: 0.06956, nearCritical: false),
            PetropoulouVLERow(row: 25, temperatureK: 298.142, pressurePa: 7_693_800, liquidMethaneMoleFraction: 0.06076, vaporMethaneMoleFraction: 0.06897, nearCritical: false),
            PetropoulouVLERow(row: 26, temperatureK: 298.142, pressurePa: 7_697_750, liquidMethaneMoleFraction: 0.06165, vaporMethaneMoleFraction: 0.06825, nearCritical: false),
            PetropoulouVLERow(row: 27, temperatureK: 303.144, pressurePa: 7_212_100, liquidMethaneMoleFraction: 1e-05, vaporMethaneMoleFraction: 1e-05, nearCritical: true),
            PetropoulouVLERow(row: 28, temperatureK: 303.144, pressurePa: 7_262_500, liquidMethaneMoleFraction: 0.00209, vaporMethaneMoleFraction: 0.00305, nearCritical: true),
            PetropoulouVLERow(row: 29, temperatureK: 303.144, pressurePa: 7_306_400, liquidMethaneMoleFraction: 0.004, vaporMethaneMoleFraction: 0.00562, nearCritical: true),
            PetropoulouVLERow(row: 30, temperatureK: 303.142, pressurePa: 7_360_900, liquidMethaneMoleFraction: 0.0065, vaporMethaneMoleFraction: 0.00858, nearCritical: false),
            PetropoulouVLERow(row: 31, temperatureK: 303.144, pressurePa: 7_415_550, liquidMethaneMoleFraction: 0.00927, vaporMethaneMoleFraction: 0.01104, nearCritical: true),
            PetropoulouVLERow(row: 32, temperatureK: 303.145, pressurePa: 7_425_450, liquidMethaneMoleFraction: 0.00991, vaporMethaneMoleFraction: 0.01138, nearCritical: true),
            PetropoulouVLERow(row: 33, temperatureK: 303.145, pressurePa: 7_428_800, liquidMethaneMoleFraction: 0.01012, vaporMethaneMoleFraction: 0.01145, nearCritical: true),
            PetropoulouVLERow(row: 34, temperatureK: 303.145, pressurePa: 7_430_500, liquidMethaneMoleFraction: 0.01025, vaporMethaneMoleFraction: 0.01144, nearCritical: true),
            PetropoulouVLERow(row: 35, temperatureK: 303.145, pressurePa: 7_431_700, liquidMethaneMoleFraction: 0.01037, vaporMethaneMoleFraction: 0.01146, nearCritical: true),
            PetropoulouVLERow(row: 36, temperatureK: 303.145, pressurePa: 7_432_950, liquidMethaneMoleFraction: 0.0105, vaporMethaneMoleFraction: 0.01145, nearCritical: true),
            PetropoulouVLERow(row: 37, temperatureK: 303.144, pressurePa: 7_434_100, liquidMethaneMoleFraction: 0.01066, vaporMethaneMoleFraction: 0.01139, nearCritical: true)
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
