import PhaseXpertCore
import XCTest

/// Exact native regressions for the source-based CCS cases.
///
/// These run only when the locally generated CoolProp XCFramework is linked.
/// They verify executable coverage of the stored P/T/composition inputs; they
/// are not independent experimental-accuracy validation.
final class BuiltInCaseNativeCoolPropTests: XCTestCase {
    func testPinnedCoolPropCalculatesEveryBuiltInCaseWithoutDroppingComponents() async throws {
        let provider = try requireNativeCoolPropProvider()
        let advertised = Set(provider.descriptor.supportedComponents)
        var calculatedCaseCount = 0

        for builtInCase in BuiltInCaseCatalog.cases {
            guard let composition = builtInCase.composition,
                  let pressurePa = builtInCase.defaultPressurePa,
                  let temperatureK = builtInCase.defaultTemperatureK else {
                continue
            }
            calculatedCaseCount += 1
            let required = Set(composition.map(\.component))
            XCTAssertTrue(
                required.isSubset(of: advertised),
                "\(builtInCase.name) contains a component not advertised by General Properties."
            )

            let request = CalculationRequest(
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
                clientVersion: "built-in-native-coverage"
            )
            let response = try await provider.calculate(request)

            XCTAssertEqual(response.model.id, "coolprop-heos")
            XCTAssertEqual(response.model.availability, .preliminary)
            XCTAssertTrue(response.isScientificResult)
            XCTAssertTrue(
                response.warnings.contains { $0.contains("VALIDATION PENDING") },
                "\(builtInCase.name) lost the preliminary-validation warning."
            )

            for property in [
                PropertyID.density,
                .molarMass,
                .specificVolume,
                .compressibilityFactor
            ] {
                let result = try XCTUnwrap(
                    response.properties.first { $0.property == property },
                    "\(builtInCase.name) did not return \(property.rawValue)."
                )
                XCTAssertEqual(
                    result.status,
                    .calculated,
                    "\(builtInCase.name) did not calculate \(property.rawValue): \(result.message ?? "")"
                )
                let value = try XCTUnwrap(result.value)
                XCTAssertTrue(
                    value.isFinite && value > 0,
                    "\(builtInCase.name) returned invalid \(property.rawValue)."
                )
            }

            XCTAssertNotEqual(
                response.phase,
                .unavailable,
                "\(builtInCase.name) returned an unavailable phase after a successful state calculation."
            )
        }
        XCTAssertEqual(calculatedCaseCount, 4)
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
