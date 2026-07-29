import XCTest
@testable import PhaseXpertCore

final class UnitConversionTests: XCTestCase {
    func testPressureConversions() {
        XCTAssertEqual(PressureUnit.megapascal.toPascal(15), 15_000_000, accuracy: 1e-9)
        XCTAssertEqual(PressureUnit.bar.toPascal(1), 100_000, accuracy: 1e-9)
        XCTAssertEqual(PressureUnit.psi.toPascal(1), 6_894.757_293_168, accuracy: 1e-9)
    }

    func testGaugePressureUsesExplicitAtmosphericReference() {
        XCTAssertEqual(
            PressureUnit.barg.toPascal(10, atmosphericReferencePa: 101_325),
            1_101_325,
            accuracy: 1e-9
        )
    }

    func testTemperatureConversions() {
        XCTAssertEqual(TemperatureUnit.celsius.toKelvin(0), 273.15, accuracy: 1e-12)
        XCTAssertEqual(TemperatureUnit.fahrenheit.toKelvin(32), 273.15, accuracy: 1e-12)
        XCTAssertEqual(TemperatureUnit.kelvin.fromKelvin(300), 300, accuracy: 1e-12)
    }
}

