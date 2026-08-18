import PhaseXpertCore
import XCTest

/// Native CoolProp phase-map regressions.
///
/// These assert executable crash resistance for validation-pending provider
/// calls. They are not independent thermodynamic accuracy validation.
final class CoolPropPhaseMapNativeTests: XCTestCase {
    func testHistoricalCO2NitrogenPhaseMapCompletesWithUsefulCoverage() async throws {
        let provider = try requireNativeCoolPropProvider()

        for resolution in [PhaseMapResolution.five, .ten, .twenty] {
            let request = historicalCO2NitrogenRequest(
                provider: provider,
                resolution: resolution
            )
            let result = try await PhaseMapRunner(provider: provider).run(request)

            try assertHistoricalCO2NitrogenResult(result, request: request)
        }
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

            let result = try await PhaseMapRunner(provider: provider).run(request)

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
            composition: [
                MixtureComponent(component: .carbonDioxide, moleFraction: 0.95),
                MixtureComponent(component: .nitrogen, moleFraction: 0.05)
            ],
            range: .automatic(pressurePa: 15_000_000, temperatureK: 293.15),
            resolution: resolution,
            clientVersion: "coolprop-phase-map-native-regression"
        )
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
            Double(unknown.count) / Double(result.evaluations.count),
            0.01,
            "Historical CO2/N2 Phase Map returned more than 1% unknown points: \(unknown.count)/\(result.evaluations.count)"
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
    }
}
