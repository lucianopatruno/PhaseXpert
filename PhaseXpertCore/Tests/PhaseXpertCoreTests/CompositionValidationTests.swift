import XCTest
@testable import PhaseXpertCore

final class CompositionValidationTests: XCTestCase {
    private let validator = CalculationValidator()
    private let supported = Set(ComponentID.allCases)

    func testValidCompositionPasses() {
        let report = validate([
            .init(component: .carbonDioxide, moleFraction: 0.97),
            .init(component: .nitrogen, moleFraction: 0.03)
        ])
        XCTAssertTrue(report.canCalculate)
        XCTAssertNil(report.normalizedComposition)
    }

    func testNormalizationIsOfferedButNeverSilentlyApplied() {
        let report = validate([
            .init(component: .carbonDioxide, moleFraction: 0.9705),
            .init(component: .nitrogen, moleFraction: 0.03)
        ])
        XCTAssertFalse(report.canCalculate)
        XCTAssertNotNil(report.normalizedComposition)
        XCTAssertTrue(report.issues.contains { $0.code == .normalizationAvailable })
    }

    func testLargeCompositionDeviationCannotNormalize() {
        let report = validate([
            .init(component: .carbonDioxide, moleFraction: 0.95),
            .init(component: .nitrogen, moleFraction: 0.03)
        ])
        XCTAssertFalse(report.canCalculate)
        XCTAssertNil(report.normalizedComposition)
        XCTAssertTrue(report.issues.contains { $0.code == .compositionTotal })
    }

    func testDuplicateAndNonLargestCO2Fail() {
        let report = validate([
            .init(component: .carbonDioxide, moleFraction: 0.4),
            .init(component: .nitrogen, moleFraction: 0.4),
            .init(component: .nitrogen, moleFraction: 0.2)
        ])
        XCTAssertFalse(report.canCalculate)
        XCTAssertTrue(report.issues.contains { $0.code == .duplicateComponent })
        XCTAssertTrue(report.issues.contains { $0.code == .carbonDioxideNotLargest })
    }

    func testNaNIsRejected() {
        let report = validate([
            .init(component: .carbonDioxide, moleFraction: .nan)
        ])
        XCTAssertFalse(report.canCalculate)
        XCTAssertTrue(report.issues.contains { $0.code == .nonFiniteInput })
    }

    func testInfinityAndOutOfRangeStateAreRejected() {
        let report = validator.validate(
            pressurePa: .infinity,
            temperatureK: 500,
            composition: [.init(component: .carbonDioxide, moleFraction: 1)],
            supportedComponents: supported,
            domain: .initialCO2Transport
        )

        XCTAssertFalse(report.canCalculate)
        XCTAssertTrue(report.issues.contains { $0.code == .nonFiniteInput })
        XCTAssertTrue(report.issues.contains { $0.code == .pressureOutsideDomain })
        XCTAssertTrue(report.issues.contains { $0.code == .temperatureOutsideDomain })
    }

    func testUnsupportedComponentIsRejected() {
        let report = validator.validate(
            pressurePa: 15_000_000,
            temperatureK: 293.15,
            composition: [
                .init(component: .carbonDioxide, moleFraction: 0.99),
                .init(component: .hydrogenSulfide, moleFraction: 0.01)
            ],
            supportedComponents: [.carbonDioxide],
            domain: .initialCO2Transport
        )

        XCTAssertFalse(report.canCalculate)
        XCTAssertTrue(report.issues.contains { $0.code == .unsupportedComponent })
    }

    private func validate(_ composition: [MixtureComponent]) -> ValidationReport {
        validator.validate(
            pressurePa: 15_000_000,
            temperatureK: 293.15,
            composition: composition,
            supportedComponents: supported,
            domain: .initialCO2Transport
        )
    }
}
