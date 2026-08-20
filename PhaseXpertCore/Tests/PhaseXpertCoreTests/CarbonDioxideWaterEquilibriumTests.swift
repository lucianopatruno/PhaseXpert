import XCTest
@testable import PhaseXpertCore

final class CarbonDioxideWaterEquilibriumTests: XCTestCase {
    private let model = SpycherPruess2003WaterEquilibrium()

    func testRepresentativeEquilibriumStateMatchesPrimaryEquationImplementation() throws {
        let result = try model.equilibrium(
            pressurePa: 10_040_000,
            temperatureK: 373.27,
            currentWaterMoleFraction: 0.0005
        )
        XCTAssertEqual(result.waterInCarbonDioxideRichPhaseMoleFraction, 0.01795729472, accuracy: 1e-10)
        XCTAssertEqual(result.carbonDioxideInWaterRichPhaseMoleFraction, 0.01413700671, accuracy: 1e-10)
        XCTAssertEqual(result.waterInCarbonDioxideRichPhasePPM, 17_957.29472, accuracy: 1e-5)
        XCTAssertEqual(try XCTUnwrap(result.currentWaterPPM), 500, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(result.marginToSaturationPPM), 17_457.29472, accuracy: 1e-5)
        XCTAssertEqual(result.waterStatus, .belowSaturation)
    }

    func testValidatedDomainBoundariesConvergeAndOutsideDomainIsRejected() throws {
        for (pressure, temperature) in [
            (499_900.0, 303.14),
            (5_005_500.0, 353.15),
            (4_700_000.0, 373.15),
            (15_090_000.0, 373.30)
        ] {
            let result = try model.equilibrium(
                pressurePa: pressure,
                temperatureK: temperature
            )
            XCTAssertTrue(result.waterInCarbonDioxideRichPhaseMoleFraction.isFinite)
            XCTAssertTrue(result.carbonDioxideInWaterRichPhaseMoleFraction.isFinite)
        }
        XCTAssertThrowsError(try model.equilibrium(
            pressurePa: 5_100_000,
            temperatureK: 360
        )) { error in
            XCTAssertEqual(error as? CarbonDioxideWaterEquilibriumError, .outsideValidatedDomain)
        }
        XCTAssertThrowsError(try model.equilibrium(
            pressurePa: 10_000_000,
            temperatureK: 373.31
        )) { error in
            XCTAssertEqual(error as? CarbonDioxideWaterEquilibriumError, .outsideValidatedDomain)
        }
    }

    func testIndependentMeyerHarvey2015ExpandedWaterValidation() throws {
        let rows = try meyerHarveyRows()
        XCTAssertEqual(rows.count, 50)
        let allMetrics = try relativeMetrics(rows.map { row in
            let calculated = try model.mutualSolubility(
                pressurePa: row.pressureMPa * 1_000_000,
                temperatureK: row.temperatureK
            ).water
            return (calculated, row.measuredWaterMoleFraction)
        })
        XCTAssertEqual(allMetrics.aardPercent, 3.297_874, accuracy: 1e-5)
        XCTAssertEqual(allMetrics.biasPercent, -3.288_853, accuracy: 1e-5)
        XCTAssertEqual(allMetrics.rmsPercent, 4.456_269, accuracy: 1e-5)
        XCTAssertEqual(allMetrics.worstPercent, 12.487_875, accuracy: 1e-5)

        let productionRows = rows.filter { $0.temperatureK >= 303.14 }
        let productionMetrics = try relativeMetrics(productionRows.map { row in
            let calculated = try model.equilibrium(
                pressurePa: row.pressureMPa * 1_000_000,
                temperatureK: row.temperatureK
            ).waterInCarbonDioxideRichPhaseMoleFraction
            return (calculated, row.measuredWaterMoleFraction)
        })
        XCTAssertEqual(productionMetrics.count, 40)
        XCTAssertEqual(productionMetrics.aardPercent, 2.494_200, accuracy: 1e-5)
        XCTAssertEqual(productionMetrics.biasPercent, -2.482_924, accuracy: 1e-5)
        XCTAssertEqual(productionMetrics.rmsPercent, 3.303_999, accuracy: 1e-5)
        XCTAssertEqual(productionMetrics.worstPercent, 7.708_346, accuracy: 1e-5)
    }

    func testWaterDropoutTemperatureUsesBoundedValidatedRegion() throws {
        let referenceTemperature = 333.18
        let pressure = 3_001_200.0
        let water = try model.equilibrium(
            pressurePa: pressure,
            temperatureK: referenceTemperature
        ).waterInCarbonDioxideRichPhaseMoleFraction
        XCTAssertEqual(
            try model.waterDropoutTemperatureK(
                pressurePa: pressure,
                waterMoleFraction: water
            ),
            referenceTemperature,
            accuracy: 1e-6
        )
        XCTAssertThrowsError(try model.waterDropoutTemperatureK(
            pressurePa: 10_000_000,
            waterMoleFraction: water
        ))
        XCTAssertThrowsError(try model.waterDropoutTemperatureK(
            pressurePa: pressure,
            waterMoleFraction: 1e-7
        )) { error in
            XCTAssertEqual(error as? CarbonDioxideWaterEquilibriumError, .dropoutTemperatureUnavailable)
        }
    }

    func testDirectMeyerHarveyDropoutTemperatureValidation() throws {
        let rows = try meyerHarveyRows().filter {
            (303.14..<353.14).contains($0.temperatureK)
        }
        let evaluated = rows.compactMap { row -> (row: MeyerHarveyArtifact.Row, error: Double)? in
            guard let predicted = try? model.waterDropoutTemperatureK(
                pressurePa: row.pressureMPa * 1_000_000,
                waterMoleFraction: row.measuredWaterMoleFraction
            ) else { return nil }
            return (row, predicted - row.temperatureK)
        }
        let errors = evaluated.map(\.error)
        XCTAssertEqual(errors.count, 30)
        let mae = errors.map(abs).reduce(0, +) / Double(errors.count)
        let bias = errors.reduce(0, +) / Double(errors.count)
        let rms = sqrt(errors.map { $0 * $0 }.reduce(0, +) / Double(errors.count))
        XCTAssertEqual(mae, 0.610_548, accuracy: 1e-5)
        XCTAssertEqual(bias, 0.610_548, accuracy: 1e-5)
        XCTAssertEqual(rms, 0.749_815, accuracy: 1e-5)
        XCTAssertEqual(try XCTUnwrap(errors.map(abs).max()), 1.520_787, accuracy: 1e-5)
        let worst = try XCTUnwrap(evaluated.max { abs($0.error) < abs($1.error) })
        XCTAssertEqual(worst.row.temperatureK, 303.14, accuracy: 1e-12)
        XCTAssertEqual(worst.row.pressureMPa, 4.5020, accuracy: 1e-12)
    }

    func testWaterStatusClassificationUsesIndependentValidationErrorBand() throws {
        let saturation = try model.equilibrium(
            pressurePa: 10_040_000,
            temperatureK: 373.27
        ).waterInCarbonDioxideRichPhaseMoleFraction
        XCTAssertEqual(try status(at: saturation - 0.002), .belowSaturation)
        XCTAssertEqual(try status(at: saturation), .atSaturation)
        XCTAssertEqual(try status(at: saturation + 0.002), .aqueousWaterExpected)
    }

    func testDropoutPressureUsesBoundedValidatedIsothermSolve() throws {
        let referencePressure = 10_040_000.0
        let water = try model.equilibrium(
            pressurePa: referencePressure,
            temperatureK: 373.27
        ).waterInCarbonDioxideRichPhaseMoleFraction
        let solved = try model.waterDropoutPressurePa(
            temperatureK: 373.27,
            waterMoleFraction: water
        )
        XCTAssertEqual(solved, referencePressure, accuracy: 0.1)

        XCTAssertThrowsError(try model.waterDropoutPressurePa(
            temperatureK: 373.27,
            waterMoleFraction: 0.0005
        )) { error in
            XCTAssertEqual(error as? CarbonDioxideWaterEquilibriumError, .dropoutPressureUnavailable)
        }
    }

    func testDirectMeyerHarveyDropoutPressureDiagnosticRemainsPreliminary() throws {
        let rows = try meyerHarveyRows().filter {
            (303.14...353.15).contains($0.temperatureK)
        }
        let evaluated = rows.compactMap { row -> (row: MeyerHarveyArtifact.Row, errorMPa: Double, relativeErrorPercent: Double)? in
            guard let predicted = try? model.waterDropoutPressurePa(
                temperatureK: row.temperatureK,
                waterMoleFraction: row.measuredWaterMoleFraction
            ) else { return nil }
            let predictedMPa = predicted / 1_000_000
            return (
                row,
                predictedMPa - row.pressureMPa,
                (predictedMPa - row.pressureMPa) / row.pressureMPa * 100
            )
        }
        let errors = evaluated.map(\.errorMPa)
        let relativeErrors = evaluated.map(\.relativeErrorPercent)
        let mae = errors.map(abs).reduce(0, +) / Double(errors.count)
        let bias = errors.reduce(0, +) / Double(errors.count)
        let rms = sqrt(errors.map { $0 * $0 }.reduce(0, +) / Double(errors.count))
        let aard = relativeErrors.map(abs).reduce(0, +) / Double(relativeErrors.count)
        let relativeBias = relativeErrors.reduce(0, +) / Double(relativeErrors.count)
        let relativeRMS = sqrt(relativeErrors.map { $0 * $0 }.reduce(0, +) / Double(relativeErrors.count))
        let worstAbsolute = try XCTUnwrap(evaluated.max { abs($0.errorMPa) < abs($1.errorMPa) })
        let worstRelative = try XCTUnwrap(evaluated.max {
            abs($0.relativeErrorPercent) < abs($1.relativeErrorPercent)
        })

        print("CO2_H2O_DROPOUT_PRESSURE_DIAGNOSTIC rows=\(rows.count) converged=\(evaluated.count) maeMPa=\(mae) biasMPa=\(bias) rmsMPa=\(rms) aardPercent=\(aard) biasPercent=\(relativeBias) rmsPercent=\(relativeRMS) worstAbsMPa=\(abs(worstAbsolute.errorMPa)) worstAbsState=T\(worstAbsolute.row.temperatureK)K_P\(worstAbsolute.row.pressureMPa)MPa worstRelPercent=\(abs(worstRelative.relativeErrorPercent)) worstRelState=T\(worstRelative.row.temperatureK)K_P\(worstRelative.row.pressureMPa)MPa")

        XCTAssertEqual(rows.count, 40)
        XCTAssertEqual(evaluated.count, 35)
        XCTAssertEqual(mae, 0.153_352, accuracy: 1e-5)
        XCTAssertEqual(bias, -0.153_352, accuracy: 1e-5)
        XCTAssertEqual(rms, 0.254_876, accuracy: 1e-5)
        XCTAssertEqual(aard, 4.208_242, accuracy: 1e-5)
        XCTAssertEqual(relativeBias, -4.208_242, accuracy: 1e-5)
        XCTAssertEqual(relativeRMS, 5.952_205, accuracy: 1e-5)
        XCTAssertEqual(abs(worstAbsolute.errorMPa), 0.812_114, accuracy: 1e-5)
        XCTAssertEqual(worstAbsolute.row.temperatureK, 303.15, accuracy: 1e-12)
        XCTAssertEqual(worstAbsolute.row.pressureMPa, 5.0055, accuracy: 1e-12)
        XCTAssertEqual(abs(worstRelative.relativeErrorPercent), 16.224_430, accuracy: 1e-5)
        XCTAssertEqual(worstRelative.row.temperatureK, 303.15, accuracy: 1e-12)
        XCTAssertEqual(worstRelative.row.pressureMPa, 5.0055, accuracy: 1e-12)
    }

    func testIndependentSanchezVicenteTrusler2022CarbonDioxideRichWaterRows() throws {
        let rows: [(temperature: Double, pressure: Double, experimentalWater: Double)] = [
            (373.27, 4.71, 1 - 0.97323),
            (373.27, 4.70, 1 - 0.97370),
            (373.27, 5.46, 1 - 0.97644),
            (373.27, 5.45, 1 - 0.97444),
            (373.27, 10.06, 1 - 0.98064),
            (373.28, 10.04, 1 - 0.98141),
            (373.27, 15.09, 1 - 0.98390)
        ]
        let metrics = try relativeMetrics(rows.map { row in
            let calculated = try model.equilibrium(
                pressurePa: row.pressure * 1_000_000,
                temperatureK: row.temperature
            ).waterInCarbonDioxideRichPhaseMoleFraction
            return (calculated, row.experimentalWater)
        })
        XCTAssertEqual(metrics.count, 7)
        XCTAssertEqual(metrics.aardPercent, 4.710_285, accuracy: 1e-5)
        XCTAssertEqual(metrics.biasPercent, 0.514_212, accuracy: 1e-5)
        XCTAssertEqual(metrics.rmsPercent, 5.308_226, accuracy: 1e-5)
        XCTAssertEqual(metrics.worstPercent, 9.270_172, accuracy: 1e-5)
    }

    func testIndependentSanchezVicenteTrusler2022WaterRichCarbonDioxideRows() throws {
        let rows: [(temperature: Double, pressure: Double, experimentalCarbonDioxide: Double)] = [
            (373.28, 4.71, 0.00780),
            (373.26, 5.45, 0.00899),
            (373.28, 10.07, 0.01434),
            (373.22, 10.03, 0.01393),
            (373.28, 15.09, 0.01784),
            (373.28, 15.09, 0.01822)
        ]
        let metrics = try relativeMetrics(rows.map { row in
            let calculated = try model.equilibrium(
                pressurePa: row.pressure * 1_000_000,
                temperatureK: row.temperature
            ).carbonDioxideInWaterRichPhaseMoleFraction
            return (calculated, row.experimentalCarbonDioxide)
        })
        XCTAssertEqual(metrics.count, 6)
        XCTAssertEqual(metrics.aardPercent, 1.165_421, accuracy: 1e-5)
        XCTAssertEqual(metrics.biasPercent, -0.189_465, accuracy: 1e-5)
        XCTAssertEqual(metrics.rmsPercent, 1.358_951, accuracy: 1e-5)
        XCTAssertEqual(metrics.worstPercent, 2.256_479, accuracy: 1e-5)
    }

    func testMulticomponentWetStreamsAreNotSilentlyAccepted() async {
        let provider = CoolPropProvider(engine: WaterEquilibriumMockEngine())
        let compositions: [[MixtureComponent]] = [
            [
                .init(component: .carbonDioxide, moleFraction: 0.9895),
                .init(component: .nitrogen, moleFraction: 0.01),
                .init(component: .water, moleFraction: 0.0005)
            ],
            [
                .init(component: .carbonDioxide, moleFraction: 0.9895),
                .init(component: .methane, moleFraction: 0.01),
                .init(component: .water, moleFraction: 0.0005)
            ],
            [
                .init(component: .carbonDioxide, moleFraction: 0.9895),
                .init(component: .oxygen, moleFraction: 0.01),
                .init(component: .water, moleFraction: 0.0005)
            ]
        ]

        for composition in compositions {
            XCTAssertTrue(provider.applicabilityIssues(for: composition).contains {
                $0.severity == .error && $0.message.contains("never drops additional components")
            })
            do {
                _ = try await provider.calculate(CalculationRequest(
                    modelID: provider.descriptor.id,
                    pressurePa: 4_710_000,
                    temperatureK: 373.27,
                    composition: composition,
                    requestedProperties: [.density],
                    clientVersion: "test"
                ))
                XCTFail("Binary water equilibrium must not be applied to wet multicomponent streams.")
            } catch let ProviderError.invalidRequest(message) {
                XCTAssertTrue(message.contains("binary CO₂/H₂O"))
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testCalculationResponseRoundTripsStructuredWaterEquilibrium() throws {
        let equilibrium = try model.equilibrium(
            pressurePa: 4_710_000,
            temperatureK: 373.27,
            currentWaterMoleFraction: 0.0005
        )
        let response = CalculationResponse(
            requestID: UUID(),
            model: WaterEquilibriumMockEngine().descriptor,
            phase: .gas,
            properties: [],
            solver: .init(method: "test", converged: true, durationMilliseconds: 0),
            warnings: [],
            isScientificResult: true,
            waterEquilibrium: equilibrium
        )
        XCTAssertEqual(
            try JSONDecoder().decode(CalculationResponse.self, from: JSONEncoder().encode(response)),
            response
        )
    }

    func testRepresentativePerformance() throws {
        let equilibriumStart = ContinuousClock.now
        let result = try model.equilibrium(
            pressurePa: 10_040_000,
            temperatureK: 373.27,
            currentWaterMoleFraction: 0.02
        )
        let equilibriumDuration = equilibriumStart.duration(to: .now)
        let dropoutStart = ContinuousClock.now
        _ = try model.waterDropoutPressurePa(
            temperatureK: 373.27,
            waterMoleFraction: result.waterInCarbonDioxideRichPhaseMoleFraction
        )
        let dropoutDuration = dropoutStart.duration(to: .now)
        let dropoutTemperatureStart = ContinuousClock.now
        _ = try model.waterDropoutTemperatureK(
            pressurePa: 3_001_200,
            waterMoleFraction: try model.equilibrium(
                pressurePa: 3_001_200,
                temperatureK: 333.18
            ).waterInCarbonDioxideRichPhaseMoleFraction
        )
        let dropoutTemperatureDuration = dropoutTemperatureStart.duration(to: .now)
        print("CO2_H2O_EQUILIBRIUM_PERFORMANCE state_and_saturation=\(equilibriumDuration) dropout_pressure=\(dropoutDuration) dropout_temperature=\(dropoutTemperatureDuration)")
    }

    private func status(at water: Double) throws -> WaterEquilibriumStatus {
        try model.equilibrium(
            pressurePa: 10_040_000,
            temperatureK: 373.27,
            currentWaterMoleFraction: water
        ).waterStatus
    }

    private func relativeMetrics(
        _ values: [(calculated: Double, experimental: Double)]
    ) throws -> (count: Int, aardPercent: Double, biasPercent: Double, rmsPercent: Double, worstPercent: Double) {
        let deviations = values.map { ($0.calculated - $0.experimental) / $0.experimental * 100 }
        return (
            deviations.count,
            deviations.map(abs).reduce(0, +) / Double(deviations.count),
            deviations.reduce(0, +) / Double(deviations.count),
            sqrt(deviations.map { $0 * $0 }.reduce(0, +) / Double(deviations.count)),
            deviations.map(abs).max() ?? 0
        )
    }

    private func meyerHarveyRows() throws -> [MeyerHarveyArtifact.Row] {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = repository.appendingPathComponent(
            "Documentation/Validation/MeyerHarvey2015CO2WaterDewPoint.json"
        )
        return try JSONDecoder().decode(
            MeyerHarveyArtifact.self,
            from: Data(contentsOf: url)
        ).rows
    }
}

private struct MeyerHarveyArtifact: Decodable {
    struct Row: Decodable {
        let temperatureK: Double
        let pressureMPa: Double
        let measuredWaterMoleFraction: Double
    }
    let rows: [Row]
}

private struct WaterEquilibriumMockEngine: CoolPropEngine {
    let isAvailable = true
    let libraryVersion = "test"
    var descriptor: ModelDescriptor {
        CoolPropProvider(engine: self).descriptor
    }

    func calculatePureCarbonDioxide(
        pressurePa: Double,
        temperatureK: Double
    ) async throws -> CoolPropEngineResult {
        .init(densityKilogramsPerCubicMetre: 1, dynamicViscosityPascalSeconds: 1, phaseIdentifier: "gas")
    }

    func pureCarbonDioxideSaturationLimits() async throws -> CoolPropSaturationLimits {
        .init(triplePointTemperatureK: 216, criticalPointTemperatureK: 304, criticalPointPressurePa: 7e6)
    }

    func pureCarbonDioxideSaturationPressure(temperatureK: Double) async throws -> Double { 1 }
}
