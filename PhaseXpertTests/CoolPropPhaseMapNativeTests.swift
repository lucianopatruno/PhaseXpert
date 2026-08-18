import PhaseXpertCore
import XCTest

/// Native CoolProp phase-map regressions.
///
/// These assert executable crash resistance for validation-pending provider
/// calls. They are not independent thermodynamic accuracy validation.
final class CoolPropPhaseMapNativeTests: XCTestCase {
    func testHistoricalCO2NitrogenFiveByFivePhaseMapCompletesAndContinuesAfterRecoverableFailure() async throws {
        let provider = try requireNativeCoolPropProvider()
        let request = PhaseMapRequest(
            modelID: provider.descriptor.id,
            pressurePa: 15_000_000,
            temperatureK: 293.15,
            composition: [
                MixtureComponent(component: .carbonDioxide, moleFraction: 0.95),
                MixtureComponent(component: .nitrogen, moleFraction: 0.05)
            ],
            range: .automatic(pressurePa: 15_000_000, temperatureK: 293.15),
            resolution: .five,
            clientVersion: "coolprop-phase-map-native-regression"
        )

        let result = try await PhaseMapRunner(provider: provider).run(request)

        XCTAssertEqual(result.evaluations.count, PhaseMapResolution.five.expectedEvaluationCount)
        XCTAssertEqual(result.request.composition, request.composition)
        XCTAssertEqual(result.evaluations[5].point.pressurePa, 7_500_000)
        XCTAssertEqual(result.evaluations[5].point.temperatureK, 280.65, accuracy: 1e-9)
        XCTAssertEqual(result.evaluations[5].classification.classification, .failed)
        XCTAssertNotNil(result.evaluations[5].failureReason)
        XCTAssertTrue(result.evaluations.dropFirst(6).contains { $0.failureReason == nil })
    }

    func testBuiltInCasePhaseMapsCompleteWithoutProcessTermination() async throws {
        let provider = try requireNativeCoolPropProvider()
        let cases: [(id: String, resolution: PhaseMapResolution, expectedCount: Int)] = [
            ("northern-lights-cargo-specification-example", .ten, 100),
            ("brevik-ccs-conditioned-export-example", .five, 25),
            ("porthos-pipeline-specification-example", .five, 25),
            ("aramis-ship-specification-example", .five, 25)
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

            XCTAssertEqual(result.evaluations.count, entry.expectedCount, builtInCase.name)
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
}
