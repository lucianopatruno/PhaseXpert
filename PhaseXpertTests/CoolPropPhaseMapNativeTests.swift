import PhaseXpertCore
import XCTest

/// Native CoolProp phase-map regressions.
///
/// These assert executable crash resistance for validation-pending provider
/// calls. They are not independent thermodynamic accuracy validation.
final class CoolPropPhaseMapNativeTests: XCTestCase {
    func testFirstHistoricalCO2NitrogenIOSCrashPointUsesSafeClassifier() async throws {
        let engine = NativeCoolPropEngine()

        let result = try await engine.identifyDryCarbonDioxideMixturePhase(
            pressurePa: 7_500_000,
            temperatureK: 268.15,
            composition: historicalCO2NitrogenComposition
        )

        XCTAssertEqual(result.phaseIdentifier, "liquid")
    }

    func testHistoricalCO2NitrogenLegacyDisagreementPointsUseEvidenceOutcomes() async throws {
        let engine = NativeCoolPropEngine()
        let cases: [(pressurePa: Double, temperatureK: Double, expectedPhase: String, note: String)] = [
            (7_500_000, 280.65, "liquid", "PhaseSI failed; independent comparison supports legacy liquid."),
            (19_166_667, 268.15, "liquid", "PhaseSI failed; independent comparison supports legacy liquid."),
            (7_500_000, 279.261111, "liquid", "PhaseSI failed; independent comparison supports legacy liquid."),
            (7_500_000, 284.816667, "unknown", "Boundary-adjacent disagreement remains unresolved."),
            (16_184_211, 273.413158, "liquid", "PhaseSI twophase; independent comparison supports legacy liquid."),
            (7_500_000, 278.676316, "liquid", "PhaseSI twophase; independent comparison supports legacy liquid."),
            (19_342_105, 278.676316, "liquid", "PhaseSI failed; independent comparison supports legacy liquid."),
            (19_342_105, 281.307895, "liquid", "PhaseSI twophase; independent comparison supports legacy liquid."),
            (20_921_053, 281.307895, "liquid", "PhaseSI twophase; independent comparison supports legacy liquid."),
            (7_500_000, 283.939474, "liquid", "Boundary-proximity diagnostic still supports legacy liquid."),
            (8_289_474, 283.939474, "liquid", "PhaseSI twophase; independent comparison supports legacy liquid."),
            (7_500_000, 286.571053, "unknown", "Boundary-adjacent disagreement remains unresolved.")
        ]

        for entry in cases {
            let result = try await engine.identifyDryCarbonDioxideMixturePhase(
                pressurePa: entry.pressurePa,
                temperatureK: entry.temperatureK,
                composition: historicalCO2NitrogenComposition
            )

            XCTAssertEqual(
                result.phaseIdentifier,
                entry.expectedPhase,
                "P=\(entry.pressurePa) Pa T=\(entry.temperatureK) K: \(entry.note)"
            )
        }
    }

    func testHistoricalCO2NitrogenFiveByFiveMatchesReference() async throws {
        try await assertHistoricalCO2NitrogenReference(resolution: .five)
    }

    func testHistoricalCO2NitrogenTenByTenMatchesReference() async throws {
        try await assertHistoricalCO2NitrogenReference(resolution: .ten)
    }

    func testHistoricalCO2NitrogenTwentyByTwentyMatchesReference() async throws {
        try await assertHistoricalCO2NitrogenReference(resolution: .twenty)
    }

    func testBuiltInCasePhaseMapsCompleteWithoutProcessTermination() async throws {
        let provider = try requireNativeCoolPropProvider()
        let cases: [(id: String, resolution: PhaseMapResolution)] = [
            ("northern-lights-cargo-specification-example", .ten),
            ("brevik-ccs-conditioned-export-example", .five),
            ("porthos-pipeline-specification-example", .five),
            ("aramis-ship-specification-example", .five)
        ]

        for entry in cases {
            let builtInCase = try XCTUnwrap(BuiltInCaseCatalog.caseWithID(entry.id))
            let request = PhaseMapRequest(
                modelID: provider.descriptor.id,
                pressurePa: builtInCase.defaultPressurePa,
                temperatureK: builtInCase.defaultTemperatureK,
                composition: builtInCase.composition,
                range: .automatic(
                    pressurePa: builtInCase.defaultPressurePa,
                    temperatureK: builtInCase.defaultTemperatureK
                ),
                resolution: entry.resolution,
                clientVersion: "coolprop-built-in-phase-map-native-regression"
            )

            let startedAt = Date()
            let result = try await PhaseMapRunner(provider: provider).run(request)
            let elapsed = Date().timeIntervalSince(startedAt)
            print(
                "BUILT_IN_PHASE_MAP id=\(entry.id) resolution=\(entry.resolution.rawValue) evaluations=\(result.evaluations.count) distribution=\(phaseDistributionString(result)) elapsed=\(elapsed)"
            )

            let expectedCount = try PhaseMapGridBuilder.points(for: request).count
            XCTAssertEqual(result.evaluations.count, expectedCount, builtInCase.name)
            XCTAssertEqual(result.request.composition, builtInCase.composition, builtInCase.name)
        }
    }

    private func requireNativeCoolPropProvider() throws
        -> any ThermodynamicModelProvider
    {
        let provider = try XCTUnwrap(
            ProviderRegistry().provider(id: "coolprop-heos")
        )
        guard provider.descriptor.availability == .preliminary else {
            throw XCTSkip(
                "The generated CoolProp XCFramework is not available to this iOS test build."
            )
        }
        return provider
    }

    private func historicalCO2NitrogenRequest(
        provider: any ThermodynamicModelProvider,
        resolution: PhaseMapResolution
    ) -> PhaseMapRequest {
        PhaseMapRequest(
            modelID: provider.descriptor.id,
            pressurePa: 15_000_000,
            temperatureK: 293.15,
            composition: historicalCO2NitrogenComposition,
            range: .automatic(pressurePa: 15_000_000, temperatureK: 293.15),
            resolution: resolution,
            clientVersion: "coolprop-phase-map-native-regression"
        )
    }

    private func assertHistoricalCO2NitrogenReference(
        resolution: PhaseMapResolution
    ) async throws {
        let provider = try requireNativeCoolPropProvider()
        let request = historicalCO2NitrogenRequest(
            provider: provider,
            resolution: resolution
        )
        let startedAt = Date()
        let result = try await PhaseMapRunner(provider: provider).run(request)
        let elapsed = Date().timeIntervalSince(startedAt)
        print(
            "CO2_N2_REFERENCE resolution=\(resolution.rawValue) evaluations=\(result.evaluations.count) distribution=\(phaseDistributionString(result)) elapsed=\(elapsed)"
        )

        try assertHistoricalCO2NitrogenResult(result, request: request)
    }

    private func phaseDistributionString(_ result: PhaseMapResult) -> String {
        let counts = Dictionary(grouping: result.evaluations) {
            $0.classification.classification
        }.mapValues(\.count)
        return PhaseMapClassification.allCases.map { classification in
            "\(classification.rawValue)=\(counts[classification, default: 0])"
        }.joined(separator: ",")
    }

    private func assertHistoricalCO2NitrogenResult(
        _ result: PhaseMapResult,
        request: PhaseMapRequest
    ) throws {
        let expectedCount = try PhaseMapGridBuilder.points(for: request).count
        XCTAssertEqual(result.evaluations.count, expectedCount)
        XCTAssertEqual(result.request.composition, request.composition)

        let failed = result.evaluations.filter {
            $0.classification.classification == .failed
        }
        XCTAssertLessThanOrEqual(
            Double(failed.count) / Double(result.evaluations.count),
            0.10,
            "Historical CO2/N2 Phase Map failed more than 10% of points: \(failed.count)/\(result.evaluations.count)"
        )
        let unknown = result.evaluations.filter {
            $0.classification.classification == .unknown
        }
        XCTAssertLessThanOrEqual(
            unknown.count,
            max(2, result.evaluations.count / 100),
            "Historical CO2/N2 Phase Map returned more than the expected small boundary-uncertainty count: \(unknown.count)/\(result.evaluations.count)"
        )

        let rows = Dictionary(grouping: result.evaluations) { evaluation in
            evaluation.point.temperatureK
        }
        for (temperature, row) in rows {
            let rowFailures = row.filter {
                $0.classification.classification == .failed
            }
            XCTAssertLessThan(
                rowFailures.count,
                row.count,
                "Entire historical CO2/N2 row failed at T=\(temperature) K"
            )
        }

        if let firstFailureIndex = result.evaluations.firstIndex(where: {
            $0.classification.classification == .failed
        }) {
            XCTAssertTrue(result.evaluations.dropFirst(firstFailureIndex + 1).contains {
                $0.classification.classification != .failed
            })
        }

        let counts = Dictionary(grouping: result.evaluations) {
            $0.classification.classification
        }.mapValues(\.count)
        let expected: [PhaseMapClassification: Int] = switch request.resolution {
        case .five:
            [.gas: 2, .liquid: 22, .multiphase: 1]
        case .ten:
            [.gas: 8, .liquid: 89, .multiphase: 2, .unknown: 2]
        case .twenty:
            [.gas: 25, .liquid: 369, .multiphase: 3, .unknown: 4]
        }
        for classification in PhaseMapClassification.allCases {
            XCTAssertEqual(
                counts[classification, default: 0],
                expected[classification, default: 0],
                "Unexpected historical CO2/N2 \(request.resolution.rawValue)x\(request.resolution.rawValue) \(classification.rawValue) count."
            )
        }
    }

    private var historicalCO2NitrogenComposition: [MixtureComponent] {
        [
            MixtureComponent(component: .carbonDioxide, moleFraction: 0.95),
            MixtureComponent(component: .nitrogen, moleFraction: 0.05)
        ]
    }
}
