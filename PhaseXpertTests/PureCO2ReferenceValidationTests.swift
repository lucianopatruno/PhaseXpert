import Foundation
import PhaseXpertCore
import XCTest

/// Experimental pure-CO₂ checks for the validation-pending CoolProp adapter.
///
/// These tests run only when the locally generated CoolProp XCFramework is
/// available to the iOS test target. A clean clone without that artifact skips
/// the cases rather than substituting mock or fabricated scientific values.
final class PureCO2ReferenceValidationTests: XCTestCase {
    private struct ObservationComposition: Encodable {
        let component: String
        let moleFraction: Double

        enum CodingKeys: String, CodingKey {
            case component
            case moleFraction = "mole_fraction"
        }
    }

    private struct ProductionObservation: Encodable {
        let gate: String
        let fixtureSection: String
        let fixtureIndex: Int
        let referenceID: String
        let property: String
        let inputTemperatureK: Double?
        let inputPressurePa: Double?
        let normalizedComposition: [ObservationComposition]
        let compositionBasis: String
        let providerID: String
        let providerName: String
        let providerVersion: String
        let modelVersion: String
        let status: String
        let value: Double?
        let unit: String
        let phase: String
        let criticalTemperatureK: Double?
        let criticalPressurePa: Double?

        enum CodingKeys: String, CodingKey {
            case gate
            case fixtureSection = "fixture_section"
            case fixtureIndex = "fixture_index"
            case referenceID = "reference_id"
            case property
            case inputTemperatureK = "input_temperature_k"
            case inputPressurePa = "input_pressure_pa"
            case normalizedComposition = "normalized_composition"
            case compositionBasis = "composition_basis"
            case providerID = "provider_id"
            case providerName = "provider_name"
            case providerVersion = "provider_version"
            case modelVersion = "model_version"
            case status
            case value
            case unit
            case phase
            case criticalTemperatureK = "critical_temperature_k"
            case criticalPressurePa = "critical_pressure_pa"
        }
    }

    private struct ProductionObservationReport: Encodable {
        let schemaVersion: String
        let metadata: [String: String]
        let points: [ProductionObservation]

        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version"
            case metadata
            case points
        }
    }

    private struct DensityReferenceCase {
        let temperatureK: Double
        let pressureKPa: Double
        let densityKilogramsPerCubicMetre: Double
        let expandedUncertaintyKilogramsPerCubicMetre: Double
    }

    private struct ViscosityReferenceCase {
        let referenceID: String
        let temperatureK: Double
        let pressureKPa: Double
        let viscosityMicroPascalSeconds: Double
        let uncertaintyMicroPascalSeconds: Double
    }

    func testWritesProductionValidationObservationsWhenRequested() async throws {
        let provider = try requireNativeCoolPropProvider()
        var observations: [ProductionObservation] = []

        for (index, reference) in densityReferences.enumerated() {
            let response = try await calculate(
                provider: provider,
                temperatureK: reference.temperatureK,
                pressureKPa: reference.pressureKPa,
                property: .density
            )
            let result = try XCTUnwrap(
                response.properties.first { $0.property == .density }
            )
            observations.append(
                try observation(
                    gate: "pure_co2_density",
                    index: index,
                    referenceID: "mantilla-2010-pure-co2-density",
                    temperatureK: reference.temperatureK,
                    pressurePa: reference.pressureKPa * 1_000,
                    provider: provider,
                    property: .density,
                    result: result,
                    phase: response.phase
                )
            )
        }

        for (index, reference) in viscosityReferences.enumerated() {
            let response = try await calculate(
                provider: provider,
                temperatureK: reference.temperatureK,
                pressureKPa: reference.pressureKPa,
                property: .dynamicViscosity
            )
            let result = try XCTUnwrap(
                response.properties.first { $0.property == .dynamicViscosity }
            )
            observations.append(
                try observation(
                    gate: "pure_co2_viscosity",
                    index: index,
                    referenceID: reference.referenceID,
                    temperatureK: reference.temperatureK,
                    pressurePa: reference.pressureKPa * 1_000,
                    provider: provider,
                    property: .dynamicViscosity,
                    result: result,
                    phase: response.phase
                )
            )
        }

        let envelope = try await provider.phaseEnvelope(
            PhaseEnvelopeRequest(
                modelID: provider.descriptor.id,
                composition: [
                    MixtureComponent(component: .carbonDioxide, moleFraction: 1)
                ]
            )
        )
        let critical = try XCTUnwrap(
            envelope.points.first { $0.branch == .critical }
        )
        observations.append(
            ProductionObservation(
                gate: "pure_co2_critical_point",
                fixtureSection: "critical_points",
                fixtureIndex: 0,
                referenceID: "nist-webbook-co2-critical",
                property: "criticalPoint",
                inputTemperatureK: nil,
                inputPressurePa: nil,
                normalizedComposition: pureCO2Composition,
                compositionBasis: "mole_fraction",
                providerID: provider.descriptor.id,
                providerName: provider.descriptor.name,
                providerVersion: provider.descriptor.providerVersion,
                modelVersion: provider.descriptor.modelVersion,
                status: envelope.isAvailable ? "calculated" : "unavailable",
                value: nil,
                unit: "K,Pa",
                phase: "critical",
                criticalTemperatureK: critical.temperatureK,
                criticalPressurePa: critical.pressurePa
            )
        )

        let report = ProductionObservationReport(
            schemaVersion: "phasexpert-production-observations.v2",
            metadata: [
                "observation_kind": "native-production-ios-test",
                "source": "PhaseXpertTests/PureCO2ReferenceValidationTests.swift"
            ],
            points: observations
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(report)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        let attachment = XCTAttachment(string: json)
        attachment.name = "PhaseXpert production validation observations"
        attachment.lifetime = .keepAlways
        add(attachment)
        print(
            "PHASEXPERT_VALIDATION_OBSERVATIONS_BASE64="
                + data.base64EncodedString()
        )

        if let outputPath = ProcessInfo.processInfo.environment[
            "PHASEXPERT_VALIDATION_OBSERVATIONS_PATH"
        ], !outputPath.isEmpty {
            let url = URL(fileURLWithPath: outputPath)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url, options: .atomic)
        }
    }

    func testDensityAgainstMantillaExperimentalData() async throws {
        let provider = try requireNativeCoolPropProvider()
        for reference in densityReferences {
            let response = try await calculate(
                provider: provider,
                temperatureK: reference.temperatureK,
                pressureKPa: reference.pressureKPa,
                property: .density
            )
            let result = try XCTUnwrap(
                response.properties.first { $0.property == .density }
            )
            let actual = try XCTUnwrap(result.value)

            XCTAssertEqual(result.status, .calculated)
            XCTAssertEqual(result.unit, "kg/m³")

            // Fixed before observing PhaseXpert output: the experimental
            // expanded uncertainty plus a conservative 0.1% model allowance.
            let tolerance =
                reference.expandedUncertaintyKilogramsPerCubicMetre
                + 0.001 * reference.densityKilogramsPerCubicMetre

            XCTAssertEqual(
                actual,
                reference.densityKilogramsPerCubicMetre,
                accuracy: tolerance,
                "Density failed at \(reference.temperatureK) K and "
                    + "\(reference.pressureKPa) kPa."
            )
        }
    }

    func testLowDensityViscosityAgainstSchaeferExperimentalData() async throws {
        let provider = try requireNativeCoolPropProvider()
        for reference in lowDensityViscosityReferences {
            let actual = try await viscosity(
                provider: provider,
                reference: reference
            )

            // Fixed before observing PhaseXpert output: at least the reported
            // expanded uncertainty, with a 0.5% floor for state/rounding
            // sensitivity across the selected low-density cases.
            let toleranceMicroPascalSeconds = max(
                reference.uncertaintyMicroPascalSeconds,
                0.005 * reference.viscosityMicroPascalSeconds
            )

            XCTAssertEqual(
                actual,
                reference.viscosityMicroPascalSeconds * 1e-6,
                accuracy: toleranceMicroPascalSeconds * 1e-6,
                "Low-density viscosity failed at \(reference.temperatureK) K "
                    + "and \(reference.pressureKPa) kPa."
            )
        }
    }

    func testColdDenseViscosityAgainstChapoyExperimentalData() async throws {
        let provider = try requireNativeCoolPropProvider()
        for reference in coldDenseViscosityReferences {
            let actual = try await viscosity(
                provider: provider,
                reference: reference
            )

            // Fixed before observing PhaseXpert output: the larger of an
            // approximate 95% experimental interval (2u_c) and the paper's
            // stated 4% uncertainty for the reference correlation.
            let toleranceMicroPascalSeconds = max(
                2 * reference.uncertaintyMicroPascalSeconds,
                0.04 * reference.viscosityMicroPascalSeconds
            )

            XCTAssertEqual(
                actual,
                reference.viscosityMicroPascalSeconds * 1e-6,
                accuracy: toleranceMicroPascalSeconds * 1e-6,
                "Cold dense viscosity failed at \(reference.temperatureK) K "
                    + "and \(reference.pressureKPa) kPa."
            )
        }
    }

    private var densityReferences: [DensityReferenceCase] {
        [
            DensityReferenceCase(
                temperatureK: 310,
                pressureKPa: 1_998,
                densityKilogramsPerCubicMetre: 37.614,
                expandedUncertaintyKilogramsPerCubicMetre: 0.209
            ),
            DensityReferenceCase(
                temperatureK: 310,
                pressureKPa: 10_014,
                densityKilogramsPerCubicMetre: 686.160,
                expandedUncertaintyKilogramsPerCubicMetre: 0.361
            ),
            DensityReferenceCase(
                temperatureK: 310,
                pressureKPa: 29_966,
                densityKilogramsPerCubicMetre: 921.817,
                expandedUncertaintyKilogramsPerCubicMetre: 0.066
            ),
            DensityReferenceCase(
                temperatureK: 350,
                pressureKPa: 19_981,
                densityKilogramsPerCubicMetre: 613.586,
                expandedUncertaintyKilogramsPerCubicMetre: 0.215
            ),
            DensityReferenceCase(
                temperatureK: 400,
                pressureKPa: 29_994,
                densityKilogramsPerCubicMetre: 561.435,
                expandedUncertaintyKilogramsPerCubicMetre: 0.118
            )
        ]
    }

    private var lowDensityViscosityReferences: [ViscosityReferenceCase] {
        [
            ViscosityReferenceCase(
                referenceID: "schaefer-2015-pure-co2-viscosity",
                temperatureK: 253.146,
                pressureKPa: 153.0,
                viscosityMicroPascalSeconds: 12.714,
                uncertaintyMicroPascalSeconds: 0.052
            ),
            ViscosityReferenceCase(
                referenceID: "schaefer-2015-pure-co2-viscosity",
                temperatureK: 298.153,
                pressureKPa: 604.5,
                viscosityMicroPascalSeconds: 14.945,
                uncertaintyMicroPascalSeconds: 0.030
            ),
            ViscosityReferenceCase(
                referenceID: "schaefer-2015-pure-co2-viscosity",
                temperatureK: 323.160,
                pressureKPa: 304.9,
                viscosityMicroPascalSeconds: 16.099,
                uncertaintyMicroPascalSeconds: 0.051
            ),
            ViscosityReferenceCase(
                referenceID: "schaefer-2015-pure-co2-viscosity",
                temperatureK: 373.160,
                pressureKPa: 100.4,
                viscosityMicroPascalSeconds: 18.396,
                uncertaintyMicroPascalSeconds: 0.050
            )
        ]
    }

    private var coldDenseViscosityReferences: [ViscosityReferenceCase] {
        [
            ViscosityReferenceCase(
                referenceID: "chapoy-2024-pure-co2-viscosity",
                temperatureK: 220.05,
                pressureKPa: 8_260,
                viscosityMicroPascalSeconds: 257.77,
                uncertaintyMicroPascalSeconds: 3.51
            ),
            ViscosityReferenceCase(
                referenceID: "chapoy-2024-pure-co2-viscosity",
                temperatureK: 230.05,
                pressureKPa: 14_050,
                viscosityMicroPascalSeconds: 229.10,
                uncertaintyMicroPascalSeconds: 2.41
            ),
            ViscosityReferenceCase(
                referenceID: "chapoy-2024-pure-co2-viscosity",
                temperatureK: 240.05,
                pressureKPa: 28_320,
                viscosityMicroPascalSeconds: 217.85,
                uncertaintyMicroPascalSeconds: 3.86
            ),
            ViscosityReferenceCase(
                referenceID: "chapoy-2024-pure-co2-viscosity",
                temperatureK: 260.05,
                pressureKPa: 22_870,
                viscosityMicroPascalSeconds: 157.39,
                uncertaintyMicroPascalSeconds: 5.33
            ),
            ViscosityReferenceCase(
                referenceID: "chapoy-2024-pure-co2-viscosity",
                temperatureK: 280.00,
                pressureKPa: 22_470,
                viscosityMicroPascalSeconds: 126.34,
                uncertaintyMicroPascalSeconds: 4.93
            )
        ]
    }

    private var viscosityReferences: [ViscosityReferenceCase] {
        lowDensityViscosityReferences + coldDenseViscosityReferences
    }

    private var pureCO2Composition: [ObservationComposition] {
        [
            ObservationComposition(
                component: ComponentID.carbonDioxide.rawValue,
                moleFraction: 1
            )
        ]
    }

    private func observation(
        gate: String,
        index: Int,
        referenceID: String,
        temperatureK: Double,
        pressurePa: Double,
        provider: any ThermodynamicModelProvider,
        property: PropertyID,
        result: PropertyValue,
        phase: PhaseRegion
    ) throws -> ProductionObservation {
        ProductionObservation(
            gate: gate,
            fixtureSection: gate,
            fixtureIndex: index,
            referenceID: referenceID,
            property: property.rawValue,
            inputTemperatureK: temperatureK,
            inputPressurePa: pressurePa,
            normalizedComposition: pureCO2Composition,
            compositionBasis: "mole_fraction",
            providerID: provider.descriptor.id,
            providerName: provider.descriptor.name,
            providerVersion: provider.descriptor.providerVersion,
            modelVersion: provider.descriptor.modelVersion,
            status: result.status.rawValue,
            value: try XCTUnwrap(result.value),
            unit: result.unit,
            phase: phase.rawValue,
            criticalTemperatureK: nil,
            criticalPressurePa: nil
        )
    }

    private func requireNativeCoolPropProvider() throws
        -> any ThermodynamicModelProvider
    {
        let provider = try XCTUnwrap(
            ProviderRegistry().provider(id: "coolprop-heos")
        )
        guard provider.descriptor.availability == .preliminary else {
            throw XCTSkip(
                "The generated CoolProp XCFramework is not available to this "
                    + "iOS test build."
            )
        }
        return provider
    }

    private func calculate(
        provider: any ThermodynamicModelProvider,
        temperatureK: Double,
        pressureKPa: Double,
        property: PropertyID
    ) async throws -> CalculationResponse {
        try await provider.calculate(
            CalculationRequest(
                modelID: provider.descriptor.id,
                pressurePa: pressureKPa * 1_000,
                temperatureK: temperatureK,
                composition: [
                    MixtureComponent(
                        component: .carbonDioxide,
                        moleFraction: 1
                    )
                ],
                requestedProperties: [property],
                clientVersion: "reference-validation"
            )
        )
    }

    private func viscosity(
        provider: any ThermodynamicModelProvider,
        reference: ViscosityReferenceCase
    ) async throws -> Double {
        let response = try await calculate(
            provider: provider,
            temperatureK: reference.temperatureK,
            pressureKPa: reference.pressureKPa,
            property: .dynamicViscosity
        )
        let result = try XCTUnwrap(
            response.properties.first { $0.property == .dynamicViscosity }
        )
        XCTAssertEqual(result.status, .calculated)
        XCTAssertEqual(result.unit, "Pa·s")
        return try XCTUnwrap(result.value)
    }
}
