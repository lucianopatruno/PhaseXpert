import XCTest
@testable import PhaseXpertCore

final class ValidationEvidenceEvaluatorTests: XCTestCase {
    private let evaluator = ValidationEvidenceEvaluator()

    func testEveryProductionPropertyCapabilityBecomesIndependentEvidenceAtItsExactState() throws {
        for formulation in TeqpFormulationCatalog.productionFormulations where formulation.components.count > 1 {
            for capability in formulation.propertyCapabilities {
                let limit = try XCTUnwrap(capability.isothermPressureLimits.first)
                let evidence = evaluator.evaluate(
                    composition: try exactComposition(formulation, capability),
                    pressurePa: limit.minimumPressurePa,
                    temperatureK: limit.temperatureK,
                    properties: [capability.property]
                )
                XCTAssertEqual(evidence.first?.status, .independentlyValidated, formulation.id)
                XCTAssertEqual(evidence.first?.formulationID, formulation.id)
            }
        }
    }

    func testOxygenAcousticEvidenceDoesNotValidateDensity() throws {
        let formulation = TeqpFormulationCatalog.co2OxygenEOSCGDenseSpeedOfSound
        let capability = try XCTUnwrap(formulation.propertyCapabilities.first)
        let limit = try XCTUnwrap(capability.isothermPressureLimits.first)
        let evidence = evaluator.evaluate(
            composition: try exactComposition(formulation, capability),
            pressurePa: limit.minimumPressurePa,
            temperatureK: limit.temperatureK,
            properties: [.density, .speedOfSound]
        )
        XCTAssertEqual(evidence.first(where: { $0.property == .speedOfSound })?.status, .independentlyValidated)
        XCTAssertNotEqual(evidence.first(where: { $0.property == .density })?.status, .independentlyValidated)
    }

    func testNearbyEvidenceIsInformationalAndDeterministic() throws {
        let formulation = TeqpFormulationCatalog.co2NitrogenGernertGasDensity
        let capability = try XCTUnwrap(formulation.propertyCapabilities.first)
        let limit = try XCTUnwrap(capability.isothermPressureLimits.first)
        var composition = try exactComposition(formulation, capability)
        let nitrogen = try XCTUnwrap(composition.firstIndex { $0.component == .nitrogen })
        let carbonDioxide = try XCTUnwrap(composition.firstIndex { $0.component == .carbonDioxide })
        composition[nitrogen] = .init(component: .nitrogen, moleFraction: composition[nitrogen].moleFraction + 0.001)
        composition[carbonDioxide] = .init(component: .carbonDioxide, moleFraction: composition[carbonDioxide].moleFraction - 0.001)
        let first = evaluator.evaluate(composition: composition, pressurePa: limit.minimumPressurePa, temperatureK: limit.temperatureK, properties: [.density])
        let second = evaluator.evaluate(composition: composition, pressurePa: limit.minimumPressurePa, temperatureK: limit.temperatureK, properties: [.density])
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.first?.status, .nearby)
    }

    func testNearbyEvidenceRejectsAdditionalComponentAndFarState() throws {
        let compatible: [MixtureComponent] = [
            .init(component: .carbonDioxide, moleFraction: 0.9863),
            .init(component: .nitrogen, moleFraction: 0.0127),
            .init(component: .methane, moleFraction: 0.001)
        ]
        XCTAssertEqual(evaluator.evaluate(composition: compatible, pressurePa: 1_000_000, temperatureK: 283.15, properties: [.density]).first?.status, .unavailable)
        let far: [MixtureComponent] = [
            .init(component: .carbonDioxide, moleFraction: 0.9),
            .init(component: .nitrogen, moleFraction: 0.1)
        ]
        XCTAssertEqual(evaluator.evaluate(composition: far, pressurePa: 100_000_000, temperatureK: 400, properties: [.density]).first?.status, .unavailable)
    }

    func testTemperatureAndPressureJustOutsideDomainAreNearbyNotValidated() throws {
        let formulation = TeqpFormulationCatalog.co2NitrogenGernertGasDensity
        let capability = try XCTUnwrap(formulation.propertyCapabilities.first)
        let limit = try XCTUnwrap(capability.isothermPressureLimits.first)
        let composition = try exactComposition(formulation, capability)
        let temperature = evaluator.evaluate(
            composition: composition,
            pressurePa: limit.minimumPressurePa,
            temperatureK: limit.maximumTemperatureK + 1,
            properties: [.density]
        )
        XCTAssertEqual(temperature.first?.status, .nearby)
        XCTAssertEqual(try XCTUnwrap(temperature.first?.deltas?.temperatureK), 1, accuracy: 1e-12)

        let pressure = evaluator.evaluate(
            composition: composition,
            pressurePa: limit.maximumPressurePa + 100_000,
            temperatureK: limit.temperatureK,
            properties: [.density]
        )
        XCTAssertEqual(pressure.first?.status, .nearby)
        XCTAssertEqual(try XCTUnwrap(pressure.first?.deltas?.pressurePa), 100_000, accuracy: 1e-12)
    }

    private func exactComposition(_ formulation: TeqpFormulation, _ capability: TeqpPropertyCapability) throws -> [MixtureComponent] {
        var values = capability.compositionLimits.map {
            MixtureComponent(component: $0.component, moleFraction: $0.minimumMoleFraction)
        }
        if formulation.components.contains(.carbonDioxide), !values.contains(where: { $0.component == .carbonDioxide }) {
            values.append(.init(component: .carbonDioxide, moleFraction: 1 - values.reduce(0) { $0 + $1.moleFraction }))
        }
        XCTAssertEqual(Set(values.map(\.component)), formulation.components)
        return values
    }
}
