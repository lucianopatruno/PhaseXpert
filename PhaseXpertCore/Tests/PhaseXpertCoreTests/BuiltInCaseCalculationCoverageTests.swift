import XCTest
@testable import PhaseXpertCore

final class BuiltInCaseCalculationCoverageTests: XCTestCase {
    private struct BuiltInCaseMockCoolPropEngine: CoolPropEngine {
        let isAvailable = true
        let libraryVersion = "8.0.0-built-in-case-test"

        func calculatePureCarbonDioxide(
            pressurePa: Double,
            temperatureK: Double
        ) async throws -> CoolPropEngineResult {
            CoolPropEngineResult(
                densityKilogramsPerCubicMetre: 900,
                dynamicViscosityPascalSeconds: 0.00008,
                phaseIdentifier: "liquid"
            )
        }

        func calculateDryCarbonDioxideMixture(
            pressurePa: Double,
            temperatureK: Double,
            composition: [MixtureComponent]
        ) async throws -> CoolPropBinaryEngineResult {
            XCTAssertTrue(composition.contains { $0.component == .carbonDioxide })
            XCTAssertEqual(
                composition.reduce(0) { $0 + $1.moleFraction },
                1,
                accuracy: 1e-12
            )
            return CoolPropBinaryEngineResult(
                densityKilogramsPerCubicMetre: 850,
                phaseIdentifier: "liquid"
            )
        }

        func pureCarbonDioxideSaturationLimits() async throws -> CoolPropSaturationLimits {
            CoolPropSaturationLimits(
                triplePointTemperatureK: 216.6,
                criticalPointTemperatureK: 304.1,
                criticalPointPressurePa: 7_377_000
            )
        }

        func pureCarbonDioxideSaturationPressure(
            temperatureK: Double
        ) async throws -> Double {
            5_000_000
        }
    }

    func testPreliminaryCoolPropAdvertisesEveryBuiltInCaseComponent() {
        let provider = CoolPropProvider(engine: BuiltInCaseMockCoolPropEngine())
        let required = Set(
            BuiltInCaseCatalog.cases
                .compactMap(\.composition)
                .flatMap { $0 }
                .map(\.component)
        )
        let advertised = Set(provider.descriptor.supportedComponents)

        XCTAssertTrue(required.isSubset(of: advertised))
        XCTAssertTrue(advertised.contains(.carbonMonoxide))
        XCTAssertTrue(advertised.contains(.hydrogenSulfide))
        XCTAssertEqual(provider.descriptor.providerVersion, "0.11.0")
    }

    func testEveryBuiltInCasePassesPreliminaryProviderCompositionGate() async throws {
        let provider = CoolPropProvider(engine: BuiltInCaseMockCoolPropEngine())

        for builtInCase in BuiltInCaseCatalog.cases where builtInCase.hasCalculationPreset {
            let composition = try XCTUnwrap(builtInCase.composition)
            let pressurePa = try XCTUnwrap(builtInCase.defaultPressurePa)
            let temperatureK = try XCTUnwrap(builtInCase.defaultTemperatureK)
            let issues = provider.applicabilityIssues(for: composition)
            XCTAssertFalse(
                issues.contains { $0.severity == .error },
                "\(builtInCase.name) has provider applicability errors: \(issues)"
            )

            let response = try await provider.calculate(
                CalculationRequest(
                    modelID: provider.descriptor.id,
                    pressurePa: pressurePa,
                    temperatureK: temperatureK,
                    composition: composition,
                    requestedProperties: [
                        .density,
                        .molarMass,
                        .specificVolume,
                        .compressibilityFactor
                    ],
                    clientVersion: "built-in-case-coverage-test"
                )
            )

            XCTAssertTrue(response.isScientificResult)
            XCTAssertTrue(response.warnings.contains { $0.contains("VALIDATION PENDING") })
            for property in [
                PropertyID.density,
                .molarMass,
                .specificVolume,
                .compressibilityFactor
            ] {
                XCTAssertEqual(
                    response.properties.first { $0.property == property }?.status,
                    .calculated,
                    "\(builtInCase.name) did not calculate \(property.rawValue)"
                )
            }
            XCTAssertTrue(response.warnings.contains {
                $0.contains("Preliminary / validation pending")
                    || $0.contains("preliminary / validation pending")
                    || $0.contains("PRELIMINARY / VALIDATION PENDING")
            })
        }
    }

    func testBuiltInCaseTraceComponentsHaveReviewedMolarMasses() throws {
        let carbonMonoxide = try XCTUnwrap(
            ComponentID.carbonMonoxide.molarMassKilogramsPerMole
        )
        let hydrogenSulfide = try XCTUnwrap(
            ComponentID.hydrogenSulfide.molarMassKilogramsPerMole
        )

        XCTAssertEqual(carbonMonoxide, 0.028_010_1, accuracy: 1e-12)
        XCTAssertEqual(hydrogenSulfide, 0.034_081, accuracy: 1e-12)
    }
}
